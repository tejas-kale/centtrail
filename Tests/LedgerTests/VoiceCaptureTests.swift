import Interpreter
import Ledger
import Testing

@Test func keywordCaptureExtractsPayeeAndAccountWithoutSaving() throws {
    let ledger = try Ledger.openInMemory()
    _ = try recordEntry(ledger, cents: 100, kind: .expense, payee: "Middle Eats", date: "2026-04-01", category: "Restaurant")
    let today = try #require(ReportingDate(iso8601: "2026-04-10"))
    let revolut = try #require(try ledger.accounts().first { $0.name == "Revolut" })
    let restaurant = try namedCategory(ledger, "Restaurant")
    let interpreter = Interpreter(ledger: ledger, today: today, backend: KeywordLanguageModelBackend(modelUnavailableReason: .appleIntelligenceOff))

    let result = try interpreter.interpretCapture("20 euros at Middle Eats with Revolut yesterday")

    #expect(result.modelUnavailable == .appleIntelligenceOff)
    #expect(result.draft.amount == Cents(2000))
    #expect(result.draft.payee == "Middle Eats")
    #expect(result.draft.accountID == revolut.id)
    #expect(result.draft.categoryID == restaurant.id)
    #expect(result.draft.reportingDate?.iso8601 == "2026-04-09")
    #expect(try ledger.transactions().count == 1)
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

@Test func guidedCaptureMapsTheSpokenAccountAndKeepsTheSelectedDate() async throws {
    let ledger = try Ledger.openInMemory()
    _ = try recordEntry(ledger, cents: 100, kind: .expense, payee: "Middle Eats", date: "2026-04-01", category: "Restaurant")
    let today = try #require(ReportingDate(iso8601: "2026-04-10"))
    let selectedDate = try #require(ReportingDate(iso8601: "2026-04-03"))
    let revolut = try #require(try ledger.accounts().first { $0.name == "Revolut" })
    let restaurant = try namedCategory(ledger, "Restaurant")
    let backend = AppleFoundationModelBackend(availabilityProvider: { nil }, captureGenerator: { text, context in
        #expect(text == "20 euros at Middle Eats with Revolut")
        #expect(context.accounts.contains(revolut))
        return GeneratedCaptureDraft(amountEuros: 20, payee: "Middle Eats", accountName: "Revolut")
    })
    let defaults = EntryDraft(kind: .expense, reportingDate: selectedDate)

    let result = try await Interpreter(ledger: ledger, today: today, backend: backend)
        .interpretCaptureAsync("20 euros at Middle Eats with Revolut", defaults: defaults)

    #expect(result.modelUnavailable == nil)
    #expect(result.draft == EntryDraft(amount: Cents(2000), kind: .expense, payee: "Middle Eats",
        reportingDate: selectedDate, categoryID: restaurant.id, accountID: revolut.id))
    #expect(try ledger.transactions().count == 1)
}
