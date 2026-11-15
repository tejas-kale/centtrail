import Ledger
import Testing

@Test func completeDraftWithAmountAndKnownPayeeYieldsCompleteCard() throws {
    let ledger = try Ledger.openInMemory()
    let accounts = try ledger.accounts()
    let supermarket = try namedCategory(ledger, "Supermarket")
    _ = try ledger.record(EntryDraft(
        amount: Cents(900),
        kind: .expense,
        payee: "Lidl",
        reportingDate: ReportingDate(iso8601: "2026-11-01"),
        categoryID: supermarket.id,
        accountID: accounts[1].id
    ))
    let today = try #require(ReportingDate(iso8601: "2026-11-15"))

    let completion = try ledger.completeDraft(
        amount: Cents(1250),
        payeeText: "lidl",
        date: nil,
        defaults: EntryDraft(kind: .expense, reportingDate: today)
    )

    #expect(completion.missingFields.isEmpty)
    #expect(completion.draft == EntryDraft(
        amount: Cents(1250),
        kind: .expense,
        payee: "Lidl",
        reportingDate: today,
        categoryID: supermarket.id,
        accountID: accounts[1].id,
        overridesCategory: false
    ))
}

@Test func completeDraftResolvesConfirmedAliasToCanonicalPayeeAndMemory() throws {
    let ledger = try Ledger.openInMemory()
    let accounts = try ledger.accounts()
    let supermarket = try namedCategory(ledger, "Supermarket")
    let lidl = try ledger.record(EntryDraft(
        amount: Cents(900),
        kind: .expense,
        payee: "Lidl",
        reportingDate: ReportingDate(iso8601: "2026-11-01"),
        categoryID: supermarket.id,
        accountID: accounts[2].id
    ))
    try ledger.confirmAlias("LIDL BERLIN", of: lidl.payee!.id)
    let yesterday = try #require(ReportingDate(iso8601: "2026-11-14"))

    let completion = try ledger.completeDraft(
        amount: Cents(1500),
        payeeText: "lidl berlin",
        date: yesterday,
        defaults: EntryDraft(kind: .expense, reportingDate: ReportingDate(iso8601: "2026-11-15"))
    )

    #expect(completion.missingFields.isEmpty)
    #expect(completion.draft.payee == "Lidl")
    #expect(completion.draft.categoryID == supermarket.id)
    #expect(completion.draft.accountID == accounts[2].id)
    #expect(completion.draft.reportingDate == yesterday)
}

@Test func completeDraftForNewPayeeUsesMostRecentAccountAndReportsMissingCategory() throws {
    let ledger = try Ledger.openInMemory()
    let accounts = try ledger.accounts()
    let restaurant = try namedCategory(ledger, "Restaurant")
    _ = try ledger.record(EntryDraft(
        amount: Cents(400),
        kind: .expense,
        payee: "Cafe",
        reportingDate: ReportingDate(iso8601: "2026-11-10"),
        categoryID: restaurant.id,
        accountID: accounts[1].id
    ))
    let today = try #require(ReportingDate(iso8601: "2026-11-15"))

    let completion = try ledger.completeDraft(
        amount: Cents(750),
        payeeText: "Bakery",
        date: nil,
        defaults: EntryDraft(kind: .expense, reportingDate: today)
    )

    #expect(completion.missingFields == [.category])
    #expect(completion.draft.payee == "Bakery")
    #expect(completion.draft.categoryID == nil)
    #expect(completion.draft.accountID == accounts[1].id)
}

@Test func completeDraftKeepsUnmentionedFieldsFromDefaults() throws {
    let ledger = try Ledger.openInMemory()
    let accounts = try ledger.accounts()
    let salary = try namedCategory(ledger, "Salary")
    let selectedDate = try #require(ReportingDate(iso8601: "2026-11-02"))
    let defaults = EntryDraft(
        amount: Cents(500),
        kind: .income,
        payee: "Employer",
        reportingDate: selectedDate,
        categoryID: salary.id,
        accountID: accounts[0].id,
        overridesCategory: true
    )

    let completion = try ledger.completeDraft(
        amount: Cents(2500),
        payeeText: nil,
        date: nil,
        defaults: defaults
    )

    #expect(completion.missingFields.isEmpty)
    #expect(completion.draft == EntryDraft(
        amount: Cents(2500),
        kind: .income,
        payee: "Employer",
        reportingDate: selectedDate,
        categoryID: salary.id,
        accountID: accounts[0].id,
        overridesCategory: true
    ))
}

@Test func completeDraftReportsAllMissingRequiredFields() throws {
    let ledger = try Ledger.openInMemory()

    let completion = try ledger.completeDraft(
        amount: nil,
        payeeText: nil,
        date: nil
    )

    #expect(completion.missingFields == [.amount, .payee, .reportingDate, .category, .account])
}
