import CenttrailShell
import FoundationModels
import Interpreter
import Ledger
import Testing

@Test func appleFoundationModelAvailabilityMapsAllSystemStates() {
    #expect(AppleFoundationModelBackend.mapAvailability(.available) == nil)
    #expect(AppleFoundationModelBackend.mapAvailability(.unavailable(.deviceNotEligible)) == .deviceNotEligible)
    #expect(AppleFoundationModelBackend.mapAvailability(.unavailable(.appleIntelligenceNotEnabled)) == .appleIntelligenceOff)
    #expect(AppleFoundationModelBackend.mapAvailability(.unavailable(.modelNotReady)) == .modelNotReady)
}

@Test func appleFoundationModelFallsBackToKeywordBackendWhenUnavailable() throws {
    let ledger = try Ledger.openInMemory()
    let today = try #require(ReportingDate(iso8601: "2026-04-10"))
    let backend = AppleFoundationModelBackend(
        availabilityProvider: { .appleIntelligenceOff },
        reportGenerator: { _, _ in
            Issue.record("Report generator should not be called when model is unavailable")
            return GeneratedReportIntent(operation: .unsupported, measure: .spending)
        }
    )
    let interpreter = Interpreter(ledger: ledger, today: today, backend: backend)
    #expect(interpreter.modelUnavailableReason == .appleIntelligenceOff)

    let result = try interpreter.interpretReport("how much did I spend this month?")
    #expect(result == .operation(.total(ReportQuery(measure: .spending))))
}

@Test func appleFoundationModelValidatesGeneratedOperationsAndRejectsInvalidOutputs() async throws {
    let ledger = try Ledger.openInMemory()
    _ = try recordEntry(ledger, cents: 1200, kind: .expense, payee: "Amazon", date: "2026-04-06", category: "Shopping")
    _ = try recordEntry(ledger, cents: 3400, kind: .expense, payee: "Amazon Fresh", date: "2026-04-07", category: "Supermarket")
    let today = try #require(ReportingDate(iso8601: "2026-04-10"))
    let shopping = try namedCategory(ledger, "Shopping")

    // 1. Valid breakdown with explicit date range
    let validBackend = AppleFoundationModelBackend(
        availabilityProvider: { nil },
        reportGenerator: { _, _ in
            GeneratedReportIntent(
                operation: .breakdown,
                measure: .spending,
                startDate: "2026-03-01",
                endDate: "2026-03-31",
                categoryName: "Shopping",
                grouping: .month
            )
        }
    )
    let validInterpreter = Interpreter(ledger: ledger, today: today, backend: validBackend)
    let validResult = try await validInterpreter.interpretReportAsync("shopping over months in march")
    let expectedRange = DateRange(
        start: try #require(ReportingDate(iso8601: "2026-03-01")),
        end: try #require(ReportingDate(iso8601: "2026-03-31"))
    )
    #expect(validResult == .operation(.breakdown(ReportQuery(
        measure: .spending,
        range: expectedRange,
        categoryID: shopping.id,
        grouping: .month
    ))))

    // 2. Invalid date range (start > end) becomes plain explanation
    let badDateBackend = AppleFoundationModelBackend(
        availabilityProvider: { nil },
        reportGenerator: { _, _ in
            GeneratedReportIntent(
                operation: .total,
                measure: .spending,
                startDate: "2026-04-30",
                endDate: "2026-04-01"
            )
        }
    )
    let badDateResult = try await Interpreter(ledger: ledger, today: today, backend: badDateBackend)
        .interpretReportAsync("spent in april")
    guard case .unsupported = badDateResult else {
        Issue.record("Expected unsupported for inverted date range, got \(badDateResult)")
        return
    }

    // 3. Negative amount filter becomes plain explanation
    let badAmountBackend = AppleFoundationModelBackend(
        availabilityProvider: { nil },
        reportGenerator: { _, _ in
            GeneratedReportIntent(
                operation: .search,
                measure: .spending,
                amountComparison: .greaterThan,
                amountEuros: -10
            )
        }
    )
    let badAmountResult = try await Interpreter(ledger: ledger, today: today, backend: badAmountBackend)
        .interpretReportAsync("find purchases over -10")
    guard case .unsupported = badAmountResult else {
        Issue.record("Expected unsupported for negative amount, got \(badAmountResult)")
        return
    }

    // 4. Unknown category becomes plain explanation
    let unknownCategoryBackend = AppleFoundationModelBackend(
        availabilityProvider: { nil },
        reportGenerator: { _, _ in
            GeneratedReportIntent(
                operation: .total,
                measure: .spending,
                categoryName: "NonExistentCategory"
            )
        }
    )
    let unknownCategoryResult = try await Interpreter(ledger: ledger, today: today, backend: unknownCategoryBackend)
        .interpretReportAsync("how much on NonExistentCategory")
    guard case .unsupported = unknownCategoryResult else {
        Issue.record("Expected unsupported for unknown category, got \(unknownCategoryResult)")
        return
    }

    // 5. Ambiguous payee triggers clarification
    let ambiguousBackend = AppleFoundationModelBackend(
        availabilityProvider: { nil },
        reportGenerator: { _, _ in
            GeneratedReportIntent(
                operation: .total,
                measure: .spending,
                payeeName: "Amazon"
            )
        }
    )
    let ambiguousResult = try await Interpreter(ledger: ledger, today: today, backend: ambiguousBackend)
        .interpretReportAsync("how much did I spend at Amazon")
    #expect(ambiguousResult == .clarification(["Amazon", "Amazon Fresh"]))

    // 6. Resolved clarification selects exact payee
    let resolvedResult = try await Interpreter(ledger: ledger, today: today, backend: ambiguousBackend)
        .interpretReportAsync("how much did I spend at Amazon", resolvedName: "Amazon")
    #expect(resolvedResult == .operation(.total(ReportQuery(measure: .spending, payeeName: "Amazon"))))
}

@Test @MainActor func askModelShowsUnavailableNoteOnlyWhenModelIsUnavailable() throws {
    let ledger = try Ledger.openInMemory()
    let today = try #require(ReportingDate(iso8601: "2026-04-10"))

    let availableBackend = AppleFoundationModelBackend(availabilityProvider: { nil })
    let availableAsk = AskModel(
        ledger: ledger,
        today: today,
        interpreter: Interpreter(ledger: ledger, today: today, backend: availableBackend)
    )
    #expect(availableAsk.unavailableNote == nil)

    let notReadyBackend = AppleFoundationModelBackend(availabilityProvider: { .modelNotReady })
    let notReadyAsk = AskModel(
        ledger: ledger,
        today: today,
        interpreter: Interpreter(ledger: ledger, today: today, backend: notReadyBackend)
    )
    let notReadyNote = try #require(notReadyAsk.unavailableNote)
    #expect(notReadyNote.localizedCaseInsensitiveContains("not ready") || notReadyNote.localizedCaseInsensitiveContains("downloading"))

    let offBackend = AppleFoundationModelBackend(availabilityProvider: { .appleIntelligenceOff })
    let offAsk = AskModel(
        ledger: ledger,
        today: today,
        interpreter: Interpreter(ledger: ledger, today: today, backend: offBackend)
    )
    let offNote = try #require(offAsk.unavailableNote)
    #expect(offNote.localizedCaseInsensitiveContains("Apple Intelligence"))

    let ineligibleBackend = AppleFoundationModelBackend(availabilityProvider: { .deviceNotEligible })
    let ineligibleAsk = AskModel(
        ledger: ledger,
        today: today,
        interpreter: Interpreter(ledger: ledger, today: today, backend: ineligibleBackend)
    )
    let ineligibleNote = try #require(ineligibleAsk.unavailableNote)
    #expect(ineligibleNote.localizedCaseInsensitiveContains("eligible"))
}

@Test func askEvaluationSuiteRecordsOperationAndArgumentAccuracy() async throws {
    let ledger = try Ledger.openInMemory()
    _ = try recordEntry(ledger, cents: 4000, kind: .expense, payee: "Middle Eats", date: "2026-03-05", category: "Restaurant")
    _ = try recordEntry(ledger, cents: 6000, kind: .expense, payee: "REWE", date: "2026-04-02", category: "Supermarket")
    _ = try recordEntry(ledger, cents: 1200, kind: .expense, payee: "Amazon", date: "2026-04-06", category: "Shopping")
    _ = try recordEntry(ledger, cents: 3400, kind: .expense, payee: "Amazon Fresh", date: "2026-04-07", category: "Supermarket")
    let today = try #require(ReportingDate(iso8601: "2026-04-10"))

    let restaurant = try namedCategory(ledger, "Restaurant")
    let utilities = try namedCategory(ledger, "Utilities")
    let supermarket = try namedCategory(ledger, "Supermarket")
    let marchRange = DateRange(
        start: try #require(ReportingDate(iso8601: "2026-03-01")),
        end: try #require(ReportingDate(iso8601: "2026-03-31"))
    )

    struct EvalCase {
        let question: String
        let expected: ReportInterpretation
        let generated: GeneratedReportIntent
    }

    let cases: [EvalCase] = [
        EvalCase(
            question: "how much did I spend this month?",
            expected: .operation(.total(ReportQuery(measure: .spending))),
            generated: GeneratedReportIntent(operation: .total, measure: .spending)
        ),
        EvalCase(
            question: "how much income did I earn this month?",
            expected: .operation(.total(ReportQuery(measure: .income))),
            generated: GeneratedReportIntent(operation: .total, measure: .income)
        ),
        EvalCase(
            question: "how much did I spend last month?",
            expected: .operation(.total(ReportQuery(measure: .spending, range: marchRange))),
            generated: GeneratedReportIntent(operation: .total, measure: .spending, startDate: "2026-03-01", endDate: "2026-03-31")
        ),
        EvalCase(
            question: "monthly spending by category",
            expected: .operation(.breakdown(ReportQuery(measure: .spending, grouping: .category))),
            generated: GeneratedReportIntent(operation: .breakdown, measure: .spending, grouping: .category)
        ),
        EvalCase(
            question: "utilities over months",
            expected: .operation(.breakdown(ReportQuery(measure: .spending, categoryID: utilities.id, grouping: .month))),
            generated: GeneratedReportIntent(operation: .breakdown, measure: .spending, categoryName: "Utilities", grouping: .month)
        ),
        EvalCase(
            question: "supermarket by category each month",
            expected: .operation(.breakdown(ReportQuery(measure: .spending, categoryID: supermarket.id, grouping: .monthAndCategory))),
            generated: GeneratedReportIntent(operation: .breakdown, measure: .spending, categoryName: "Supermarket", grouping: .monthAndCategory)
        ),
        EvalCase(
            question: "spent on restaurants compared with last month",
            expected: .operation(.comparison(measure: .spending, categoryID: restaurant.id, payeeName: nil)),
            generated: GeneratedReportIntent(operation: .comparison, measure: .spending, categoryName: "Restaurant")
        ),
        EvalCase(
            question: "find purchases over 50",
            expected: .operation(.search(ReportQuery(measure: .spending, amount: .greaterThan(Cents(5000))))),
            generated: GeneratedReportIntent(operation: .search, measure: .spending, amountComparison: .greaterThan, amountEuros: 50)
        ),
        EvalCase(
            question: "find purchases under 25 at REWE",
            expected: .operation(.search(ReportQuery(measure: .spending, payeeName: "REWE", amount: .lessThan(Cents(2500))))),
            generated: GeneratedReportIntent(operation: .search, measure: .spending, payeeName: "REWE", amountComparison: .lessThan, amountEuros: 25)
        ),
        EvalCase(
            question: "how much did I spend at Amazon",
            expected: .clarification(["Amazon", "Amazon Fresh"]),
            generated: GeneratedReportIntent(operation: .total, measure: .spending, payeeName: "Amazon")
        ),
        EvalCase(
            question: "what is my net worth?",
            expected: .unsupported(Interpreter.supportedExplanation),
            generated: GeneratedReportIntent(operation: .unsupported, measure: .spending, unsupportedReason: "Net worth is not supported.")
        ),
        EvalCase(
            question: "delete all my transactions",
            expected: .unsupported(Interpreter.supportedExplanation),
            generated: GeneratedReportIntent(operation: .unsupported, measure: .spending, unsupportedReason: "Ask is read-only.")
        ),
    ]

    // Evaluate Keyword fallback
    let keywordInterpreter = Interpreter(ledger: ledger, today: today, backend: KeywordLanguageModelBackend())
    var keywordOperationHits = 0
    var keywordFullHits = 0
    for evalCase in cases {
        let actual = try keywordInterpreter.interpretReport(evalCase.question)
        let score = keywordInterpreter.score(actual, expected: evalCase.expected)
        if score.operationMatches { keywordOperationHits += 1 }
        if score.passed { keywordFullHits += 1 }
    }
    #expect(keywordOperationHits == cases.count)
    #expect(keywordFullHits == cases.count)

    // Evaluate AppleFoundationModelBackend pipeline (guided-generation schema + validator)
    let intentByQuestion = Dictionary(uniqueKeysWithValues: cases.map { ($0.question, $0.generated) })
    let appleBackend = AppleFoundationModelBackend(
        availabilityProvider: { nil },
        reportGenerator: { question, _ in
            intentByQuestion[question] ?? GeneratedReportIntent(operation: .unsupported, measure: .spending)
        }
    )
    let appleInterpreter = Interpreter(ledger: ledger, today: today, backend: appleBackend)
    var appleOperationHits = 0
    var appleFullHits = 0
    for evalCase in cases {
        let actual = try await appleInterpreter.interpretReportAsync(evalCase.question)
        let score = appleInterpreter.score(actual, expected: evalCase.expected)
        if score.operationMatches { appleOperationHits += 1 }
        if score.passed { appleFullHits += 1 }
    }
    #expect(appleOperationHits == cases.count)
    #expect(appleFullHits == cases.count)
}

@Test func appleFoundationModelValidatesCaptureDrafts() async throws {
    let ledger = try Ledger.openInMemory()
    _ = try recordEntry(ledger, cents: 100, kind: .expense, payee: "Middle Eats", date: "2026-01-01", category: "Restaurant")
    let today = try #require(ReportingDate(iso8601: "2026-04-10"))
    let restaurant = try namedCategory(ledger, "Restaurant")

    let backend = AppleFoundationModelBackend(
        availabilityProvider: { nil },
        captureGenerator: { _, _ in
            GeneratedCaptureDraft(
                amountEuros: 20.0,
                kind: .expense,
                payee: "Middle Eats",
                reportingDate: "2026-04-09",
                categoryName: nil,
                note: "Lunch"
            )
        }
    )
    let interpreter = Interpreter(ledger: ledger, today: today, backend: backend)
    let result = try await interpreter.interpretCaptureAsync("20 at Middle Eats yesterday")
    #expect(result.modelUnavailable == nil)
    #expect(result.draft.amount == Cents(2000))
    #expect(result.draft.kind == .expense)
    #expect(result.draft.payee == "Middle Eats")
    #expect(result.draft.reportingDate?.iso8601 == "2026-04-09")
    #expect(result.draft.categoryID == restaurant.id)
    #expect(result.draft.overridesCategory == false)
    #expect(result.draft.note == "Lunch")
}

@Test func appleFoundationModelLiveSmokeAndTimingWhenAvailable() async throws {
    let backend = AppleFoundationModelBackend()
    guard backend.modelUnavailableReason == nil else {
        // System reports model unavailable on this host; live on-device timing is recorded on iPhone Air.
        return
    }
    let ledger = try Ledger.openInMemory()
    _ = try recordEntry(ledger, cents: 4000, kind: .expense, payee: "Middle Eats", date: "2026-03-05", category: "Restaurant")
    let today = try #require(ReportingDate(iso8601: "2026-04-10"))
    let interpreter = Interpreter(ledger: ledger, today: today, backend: backend)

    let coldStart = ContinuousClock.now
    let coldResult = try await interpreter.interpretReportAsync("how much did I spend this month?")
    let coldElapsed = coldStart.duration(to: .now)

    let warmStart = ContinuousClock.now
    let warmResult = try await interpreter.interpretReportAsync("monthly spending by category")
    let warmElapsed = warmStart.duration(to: .now)

    print("AppleFoundationModel live cold=\(coldElapsed) warm=\(warmElapsed)")
    if case .operation = coldResult {} else {
        Issue.record("Expected operation for cold live query, got \(coldResult)")
    }
    if case .operation = warmResult {} else {
        Issue.record("Expected operation for warm live query, got \(warmResult)")
    }
}
