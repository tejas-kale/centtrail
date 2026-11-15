import Ledger
import Testing

@Test func captureRemembersThePayeesLastActiveAccountIncludingAliasesAndIncome() throws {
    let ledger = try Ledger.openInMemory()
    let accounts = try ledger.accounts()
    let category = try namedCategory(ledger, "Supermarket")
    let first = try ledger.record(EntryDraft(amount: Cents(1250), kind: .expense, payee: "Lidl", reportingDate: ReportingDate(iso8601: "2026-11-01"), categoryID: category.id, accountID: accounts[0].id))
    try ledger.confirmAlias("LIDL BERLIN", of: first.payee!.id)
    _ = try ledger.record(EntryDraft(amount: Cents(100), kind: .income, payee: "Lidl", reportingDate: ReportingDate(iso8601: "2026-11-02"), categoryID: category.id, accountID: accounts[1].id))
    let trashed = try ledger.record(EntryDraft(amount: Cents(100), kind: .expense, payee: "Lidl", reportingDate: ReportingDate(iso8601: "2026-11-03"), categoryID: category.id, accountID: accounts[2].id))
    try ledger.trash(trashed.id, on: try #require(ReportingDate(iso8601: "2026-11-04")))
    #expect(try ledger.lastUsedAccount(forPayeeName: "lidl berlin") == accounts[1])
    #expect(try ledger.lastUsedAccount(forPayeeName: "New payee") == nil)
}

@Test func captureUsesTheMostRecentlyUsedAccountAndIgnoresTrashedEntries() throws {
    let ledger = try Ledger.openInMemory()
    #expect(try ledger.mostRecentlyUsedAccount() == nil)
    let accounts = try ledger.accounts()
    let category = try namedCategory(ledger, "Restaurant")
    _ = try ledger.record(EntryDraft(amount: Cents(300), kind: .expense, payee: "Cafe", reportingDate: ReportingDate(iso8601: "2026-11-01"), categoryID: category.id, accountID: accounts[1].id))
    let newest = try ledger.record(EntryDraft(amount: Cents(500), kind: .expense, payee: "Bakery", reportingDate: ReportingDate(iso8601: "2026-11-02"), categoryID: category.id, accountID: accounts[2].id))
    #expect(try ledger.mostRecentlyUsedAccount() == accounts[2])
    try ledger.trash(newest.id, on: try #require(ReportingDate(iso8601: "2026-11-03")))
    #expect(try ledger.mostRecentlyUsedAccount() == accounts[1])
}

@Test func captureSuggestionsMatchAliasesAndReturnEachCanonicalPayeeOnce() throws {
    let ledger = try Ledger.openInMemory()
    let amazon = try recordEntry(ledger, cents: 100, kind: .expense, payee: "Amazon", date: "2026-11-01", category: "Shopping")
    try ledger.confirmAlias("AMZN MKTP", of: amazon.payee!.id)
    try ledger.confirmAlias("AMZN BERLIN", of: amazon.payee!.id)
    #expect(try ledger.payeeSuggestions(matching: "amzn").map(\.name) == ["Amazon"])
    #expect(try ledger.payeeSuggestions(matching: "Ama").map(\.name) == ["Amazon"])
    #expect(try ledger.payeeSuggestions(matching: " ").isEmpty)
}
