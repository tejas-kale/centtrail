import Interpreter
import Ledger
import Testing

@Test func keywordCaptureExtractsOnlyAmountPayeeAndDateAndCompletesFromMemory() throws {
    let ledger = try Ledger.openInMemory()
    let accounts = try ledger.accounts()
    let restaurant = try namedCategory(ledger, "Restaurant")
    _ = try ledger.record(EntryDraft(
        amount: Cents(100),
        kind: .expense,
        payee: "Middle Eats",
        reportingDate: ReportingDate(iso8601: "2026-04-01"),
        categoryID: restaurant.id,
        accountID: accounts[1].id
    ))
    let today = try #require(ReportingDate(iso8601: "2026-04-10"))
    let interpreter = Interpreter(ledger: ledger, today: today, backend: KeywordLanguageModelBackend(modelUnavailableReason: .appleIntelligenceOff))

    let result = try interpreter.interpretCapture("20 euros at Middle Eats yesterday")

    #expect(result.modelUnavailable == .appleIntelligenceOff)
    #expect(result.parsed == ParsedCapture(
        amount: Cents(2000),
        payeeText: "Middle Eats",
        reportingDate: ReportingDate(iso8601: "2026-04-09")
    ))
    #expect(result.missingFields.isEmpty)
    #expect(result.draft.amount == Cents(2000))
    #expect(result.draft.payee == "Middle Eats")
    #expect(result.draft.accountID == accounts[1].id)
    #expect(result.draft.categoryID == restaurant.id)
    #expect(result.draft.reportingDate?.iso8601 == "2026-04-09")
    #expect(try ledger.transactions().count == 1)
}

@Test func keywordCaptureParsesAmountAndPayeeWithoutPreposition() throws {
    let ledger = try Ledger.openInMemory()
    let accounts = try ledger.accounts()
    let supermarket = try namedCategory(ledger, "Supermarket")
    _ = try ledger.record(EntryDraft(
        amount: Cents(900),
        kind: .expense,
        payee: "Lidl",
        reportingDate: ReportingDate(iso8601: "2026-04-01"),
        categoryID: supermarket.id,
        accountID: accounts[2].id
    ))
    let today = try #require(ReportingDate(iso8601: "2026-04-10"))
    let interpreter = Interpreter(ledger: ledger, today: today, backend: KeywordLanguageModelBackend())

    let result = try interpreter.interpretCapture("12.50 Lidl")

    #expect(result.parsed == ParsedCapture(amount: Cents(1250), payeeText: "Lidl", reportingDate: nil))
    #expect(result.missingFields.isEmpty)
    #expect(result.draft.amount == Cents(1250))
    #expect(result.draft.payee == "Lidl")
    #expect(result.draft.categoryID == supermarket.id)
    #expect(result.draft.accountID == accounts[2].id)
    #expect(result.draft.reportingDate == today)
}

@Test func captureKeepsUnmentionedFieldsFromTheCurrentForm() throws {
    let ledger = try Ledger.openInMemory()
    let today = try #require(ReportingDate(iso8601: "2026-04-10"))
    let selectedDate = try #require(ReportingDate(iso8601: "2026-04-02"))
    let cash = try #require(try ledger.accounts().first { $0.name == "Cash" })
    let salary = try namedCategory(ledger, "Salary")
    let defaults = EntryDraft(amount: Cents(500), kind: .income, payee: "Employer", reportingDate: selectedDate,
        categoryID: salary.id, accountID: cash.id, overridesCategory: true)
    let interpreter = Interpreter(ledger: ledger, today: today, backend: KeywordLanguageModelBackend())

    let result = try interpreter.interpretCapture("25", defaults: defaults)

    #expect(result.draft == EntryDraft(amount: Cents(2500), kind: .income, payee: "Employer", reportingDate: selectedDate,
        categoryID: salary.id, accountID: cash.id, overridesCategory: true))
    #expect(try ledger.transactions().isEmpty)
}

@Test func guidedCaptureExtractsAmountPayeeAndDateAndCompletesFromMemory() async throws {
    let ledger = try Ledger.openInMemory()
    let accounts = try ledger.accounts()
    let restaurant = try namedCategory(ledger, "Restaurant")
    _ = try ledger.record(EntryDraft(
        amount: Cents(100),
        kind: .expense,
        payee: "Middle Eats",
        reportingDate: ReportingDate(iso8601: "2026-04-01"),
        categoryID: restaurant.id,
        accountID: accounts[1].id
    ))
    let today = try #require(ReportingDate(iso8601: "2026-04-10"))
    let selectedDate = try #require(ReportingDate(iso8601: "2026-04-03"))
    let backend = AppleFoundationModelBackend(availabilityProvider: { nil }, captureGenerator: { text, context in
        #expect(text == "20 euros at Middle Eats")
        #expect(context.payees.contains { $0.name == "Middle Eats" })
        return GeneratedCaptureDraft(amountEuros: 20, payee: "Middle Eats")
    })
    let defaults = EntryDraft(kind: .expense, reportingDate: selectedDate)

    let result = try await Interpreter(ledger: ledger, today: today, backend: backend)
        .interpretCaptureAsync("20 euros at Middle Eats", defaults: defaults)

    #expect(result.modelUnavailable == nil)
    #expect(result.missingFields.isEmpty)
    #expect(result.draft == EntryDraft(amount: Cents(2000), kind: .expense, payee: "Middle Eats",
        reportingDate: selectedDate, categoryID: restaurant.id, accountID: accounts[1].id))
    #expect(try ledger.transactions().count == 1)
}
