import CenttrailShell
import Interpreter
import Ledger
import Testing

private struct FakeLanguageModelBackend: LanguageModelBackend {
    let modelUnavailableReason: ModelUnavailableReason?
    let reportHandler: @Sendable (String, InterpretationContext, String?) throws -> ReportInterpretation
    let captureHandler: @Sendable (String, InterpretationContext) throws -> EntryDraft

    init(
        modelUnavailableReason: ModelUnavailableReason? = nil,
        reportHandler: @escaping @Sendable (String, InterpretationContext, String?) throws -> ReportInterpretation = { _, _, _ in
            .unsupported(Interpreter.supportedExplanation)
        },
        captureHandler: @escaping @Sendable (String, InterpretationContext) throws -> EntryDraft = { _, _ in
            EntryDraft()
        }
    ) {
        self.modelUnavailableReason = modelUnavailableReason
        self.reportHandler = reportHandler
        self.captureHandler = captureHandler
    }

    func interpretReport(
        _ text: String,
        context: InterpretationContext,
        resolvedName: String?
    ) throws -> ReportInterpretation {
        try reportHandler(text, context, resolvedName)
    }

    func interpretCapture(_ text: String, context: InterpretationContext) throws -> EntryDraft {
        try captureHandler(text, context)
    }
}

@Test func interpreterDelegatesToInjectedFakeBackendAndScoresEveryArgument() throws {
    let ledger = try Ledger.openInMemory()
    let restaurant = try namedCategory(ledger, "Restaurant")
    let today = try #require(ReportingDate(iso8601: "2026-04-10"))
    let range = DateRange(
        start: try #require(ReportingDate(iso8601: "2026-03-01")),
        end: try #require(ReportingDate(iso8601: "2026-03-31"))
    )

    let fake = FakeLanguageModelBackend(
        modelUnavailableReason: nil,
        reportHandler: { text, context, resolvedName in
            #expect(context.today == today)
            if let resolvedName {
                return .operation(.total(ReportQuery(measure: .spending, payeeName: resolvedName)))
            }
            if text == "search march" {
                return .operation(.search(ReportQuery(
                    measure: .spending,
                    range: range,
                    categoryID: restaurant.id,
                    payeeName: "Middle Eats",
                    amount: .greaterThan(Cents(1500))
                )))
            }
            if text == "ambiguous" {
                return .clarification(["Amazon", "Amazon Fresh"])
            }
            return .unsupported(Interpreter.supportedExplanation)
        },
        captureHandler: { _, context in
            EntryDraft(amount: Cents(2500), kind: .expense, payee: "REWE", reportingDate: context.today, categoryID: restaurant.id)
        }
    )

    let interpreter = Interpreter(ledger: ledger, today: today, backend: fake)
    #expect(interpreter.modelUnavailableReason == nil)

    let searchResult = try interpreter.interpretReport("search march")
    let expectedSearch = ReportInterpretation.operation(.search(ReportQuery(
        measure: .spending,
        range: range,
        categoryID: restaurant.id,
        payeeName: "Middle Eats",
        amount: .greaterThan(Cents(1500))
    )))
    #expect(interpreter.score(searchResult, expected: expectedSearch).passed)

    let wrongArg = ReportInterpretation.operation(.search(ReportQuery(
        measure: .income,
        range: range,
        categoryID: restaurant.id,
        payeeName: "Other",
        amount: .lessThan(Cents(1500))
    )))
    let score = interpreter.score(searchResult, expected: wrongArg)
    #expect(!score.passed)
    #expect(score.argumentMismatches == ["measure", "payee", "amount"])

    #expect(try interpreter.interpretReport("ambiguous") == .clarification(["Amazon", "Amazon Fresh"]))
    #expect(try interpreter.interpretReport("ambiguous", resolvedName: "Amazon") == .operation(.total(ReportQuery(measure: .spending, payeeName: "Amazon"))))

    if case .unsupported = try interpreter.interpretReport("unknown question") {
    } else {
        Issue.record("Expected unsupported")
    }

    let capture = try interpreter.interpretCapture("25 at REWE")
    #expect(capture.modelUnavailable == nil)
    #expect(capture.draft.amount == Cents(2500))
    #expect(capture.draft.payee == "REWE")
}

@Test func keywordParserHandlesComparisonClarificationAndRefusesMutations() throws {
    let ledger = try Ledger.openInMemory()
    _ = try recordEntry(ledger, cents: 1200, kind: .expense, payee: "Amazon", date: "2026-04-02", category: "Shopping")
    _ = try recordEntry(ledger, cents: 3400, kind: .expense, payee: "Amazon Fresh", date: "2026-04-03", category: "Supermarket")
    let restaurant = try namedCategory(ledger, "Restaurant")
    let today = try #require(ReportingDate(iso8601: "2026-04-10"))

    let interpreter = Interpreter(ledger: ledger, today: today, backend: KeywordLanguageModelBackend())

    let comparison = try interpreter.interpretReport("Restaurants this month vs last month")
    #expect(interpreter.score(
        comparison,
        expected: .operation(.comparison(measure: .spending, categoryID: restaurant.id, payeeName: nil))
    ).passed)

    let clarification = try interpreter.interpretReport("how much did I spend at Amazon")
    #expect(clarification == .clarification(["Amazon", "Amazon Fresh"]))

    let resolved = try interpreter.interpretReport("how much did I spend at Amazon", resolvedName: "Amazon")
    #expect(resolved == .operation(.total(ReportQuery(measure: .spending, payeeName: "Amazon"))))

    for mutation in ["delete my last transaction", "add 20 at REWE", "rename Supermarket"] {
        if case .unsupported = try interpreter.interpretReport(mutation) {
        } else {
            Issue.record("Expected unsupported for mutation: \(mutation)")
        }
    }
}

@Test @MainActor func askModelPresetsWorkWithNoModelAndHistoryClearsOnLaunch() throws {
    let ledger = try Ledger.openInMemory()
    _ = try recordEntry(ledger, cents: 3000, kind: .expense, payee: "REWE", date: "2026-03-05", category: "Supermarket")
    _ = try recordEntry(ledger, cents: 5500, kind: .expense, payee: "Middle Eats", date: "2026-04-04", category: "Restaurant")
    _ = try recordEntry(ledger, cents: 2000, kind: .expense, payee: "REWE", date: "2026-04-06", category: "Supermarket")
    _ = try recordEntry(ledger, cents: 9000, kind: .income, payee: "Employer", date: "2026-04-01", category: "Salary")
    let today = try #require(ReportingDate(iso8601: "2026-04-10"))

    let ask = AskModel(ledger: ledger, today: today, interpreter: nil)
    #expect(ask.messages.isEmpty)

    ask.runPreset(.thisMonthByCategory)
    #expect(ask.messages.count == 2)
    guard case .answer(_, let breakdownCard) = ask.messages.last?.content,
          case .breakdown(let rows, let grouping, let range) = breakdownCard else {
        Issue.record("Expected breakdown card")
        return
    }
    #expect(grouping == .category)
    #expect(range.start.iso8601 == "2026-04-01")
    #expect(range.end.iso8601 == "2026-04-30")
    #expect(rows.map(\.categoryName) == ["Restaurant", "Supermarket"])

    ask.runPreset(.thisMonthVsLastMonth)
    guard case .answer(_, let comparisonCard) = ask.messages.last?.content,
          case .comparison(let comparison) = comparisonCard else {
        Issue.record("Expected comparison card")
        return
    }
    #expect(comparison.earlier.range.start.iso8601 == "2026-03-01")
    #expect(comparison.earlier.range.end.iso8601 == "2026-03-10")
    #expect(comparison.later.range.start.iso8601 == "2026-04-01")
    #expect(comparison.later.range.end.iso8601 == "2026-04-10")
    #expect(comparison.earlier.cents == 3000)
    #expect(comparison.later.cents == 7500)

    ask.runPreset(.biggestExpenses)
    guard case .answer(_, let listCard) = ask.messages.last?.content,
          case .transactions(let transactions, let txRange) = listCard else {
        Issue.record("Expected transactions card")
        return
    }
    #expect(txRange.start.iso8601 == "2026-04-01")
    #expect(txRange.end.iso8601 == "2026-04-30")
    #expect(transactions.map(\.amount.value) == [5500, 2000])
}

@Test @MainActor func askModelHandlesComparisonClarificationAndDefaultPeriod() throws {
    let ledger = try Ledger.openInMemory()
    _ = try recordEntry(ledger, cents: 4000, kind: .expense, payee: "Middle Eats", date: "2026-03-05", category: "Restaurant")
    _ = try recordEntry(ledger, cents: 6000, kind: .expense, payee: "Middle Eats", date: "2026-04-05", category: "Restaurant")
    _ = try recordEntry(ledger, cents: 1200, kind: .expense, payee: "Amazon", date: "2026-04-06", category: "Shopping")
    _ = try recordEntry(ledger, cents: 3400, kind: .expense, payee: "Amazon Fresh", date: "2026-04-07", category: "Supermarket")
    let today = try #require(ReportingDate(iso8601: "2026-04-10"))

    let interpreter = Interpreter(ledger: ledger, today: today, backend: KeywordLanguageModelBackend())
    let ask = AskModel(ledger: ledger, today: today, interpreter: interpreter)

    ask.inputText = "Restaurants this month vs last month"
    ask.submitInput()
    #expect(ask.inputText.isEmpty)
    guard case .answer(_, let card) = ask.messages.last?.content,
          case .comparison(let comparison) = card else {
        Issue.record("Expected comparison card")
        return
    }
    #expect(comparison.earlier.cents == 4000)
    #expect(comparison.later.cents == 6000)
    #expect(comparison.earlier.range.start.iso8601 == "2026-03-01")
    #expect(comparison.later.range.start.iso8601 == "2026-04-01")

    ask.inputText = "how much did I spend at Amazon"
    ask.submitInput()
    guard case .clarification(let question, _, let options) = ask.messages.last?.content else {
        Issue.record("Expected clarification")
        return
    }
    #expect(options == ["Amazon", "Amazon Fresh"])
    ask.resolveClarification(question: question, choice: "Amazon")
    guard case .answer(_, let totalCard) = ask.messages.last?.content,
          case .total(let cents, let range) = totalCard else {
        Issue.record("Expected total card after clarification")
        return
    }
    #expect(cents == 1200)
    #expect(range.start.iso8601 == "2026-04-01")
    #expect(range.end.iso8601 == "2026-04-30")

    ask.inputText = "find purchases over 50"
    ask.submitInput()
    guard case .answer(_, let searchCard) = ask.messages.last?.content,
          case .transactions(let txs, let searchRange) = searchCard else {
        Issue.record("Expected search card")
        return
    }
    #expect(searchRange.start.iso8601 == "2026-04-01")
    #expect(searchRange.end.iso8601 == "2026-04-30")
    #expect(txs.map(\.payee!.name) == ["Middle Eats"])
}
