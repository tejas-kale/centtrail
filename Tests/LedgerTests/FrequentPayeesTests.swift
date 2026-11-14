import Ledger
import Testing

@Test func frequentPayeesRankActiveEntriesForTheSelectedKind() throws {
    let ledger = try Ledger.openInMemory()
    _ = try recordEntry(ledger, cents: 100, kind: .expense, payee: "Bakery", date: "2026-11-01", category: "Restaurant")
    _ = try recordEntry(ledger, cents: 200, kind: .expense, payee: "REWE", date: "2026-11-02", category: "Supermarket")
    _ = try recordEntry(ledger, cents: 300, kind: .expense, payee: "REWE", date: "2026-11-03", category: "Supermarket")
    _ = try recordEntry(ledger, cents: 400, kind: .income, payee: "Employer", date: "2026-11-04", category: "Salary")
    let removed = try recordEntry(ledger, cents: 100, kind: .expense, payee: "Bakery", date: "2026-11-05", category: "Restaurant")
    try ledger.trash(removed.id, on: try #require(ReportingDate(iso8601: "2026-11-06")))
    let expenses = try ledger.frequentPayees(kind: .expense)
    #expect(expenses.map { $0.payee.name } == ["REWE", "Bakery"])
    #expect(expenses.map(\.entryCount) == [2, 1])
    #expect(expenses.first?.payee.defaultCategory?.name == "Supermarket")
    #expect(try ledger.frequentPayees(kind: .income).map { $0.payee.name } == ["Employer"])
    #expect(try ledger.frequentPayees(kind: .transfer).isEmpty)
}

@Test func frequentPayeesLimitToEightWithStableAlphabeticalTies() throws {
    let ledger = try Ledger.openInMemory()
    for name in ["J", "I", "H", "G", "F", "E", "D", "C", "B", "A"] {
        _ = try recordEntry(ledger, cents: 100, kind: .expense, payee: name, date: "2026-11-01", category: "Shopping")
    }
    #expect(try ledger.frequentPayees(kind: .expense).map { $0.payee.name } == ["A", "B", "C", "D", "E", "F", "G", "H"])
}

@Test func frequentPayeeUsesLatestActiveAccountAndCurrentDefault() throws {
    let ledger = try Ledger.openInMemory()
    let accounts = try ledger.accounts()
    let supermarket = try namedCategory(ledger, "Supermarket")
    let shopping = try namedCategory(ledger, "Shopping")
    let first = try ledger.record(EntryDraft(amount: Cents(100), kind: .expense, payee: "REWE", reportingDate: ReportingDate(iso8601: "2026-11-01"), categoryID: supermarket.id, accountID: accounts[0].id))
    _ = try ledger.record(EntryDraft(amount: Cents(200), kind: .expense, payee: "REWE", reportingDate: ReportingDate(iso8601: "2026-11-02"), categoryID: supermarket.id, accountID: accounts[1].id))
    _ = try ledger.record(EntryDraft(amount: Cents(100), kind: .income, payee: "REWE", reportingDate: ReportingDate(iso8601: "2026-11-03"), categoryID: supermarket.id, accountID: accounts[2].id))
    let trashed = try ledger.record(EntryDraft(amount: Cents(100), kind: .expense, payee: "REWE", reportingDate: ReportingDate(iso8601: "2026-11-04"), categoryID: supermarket.id, accountID: accounts[3].id))
    try ledger.trash(trashed.id, on: try #require(ReportingDate(iso8601: "2026-11-05")))
    try ledger.setDefaultCategory(shopping.id, for: try #require(first.payee).id)

    let suggestion = try #require(try ledger.frequentPayees(kind: .expense).first)
    #expect(suggestion.lastUsedAccount.name == "Cash")
    #expect(suggestion.entryCount == 2)
    #expect(suggestion.payee.defaultCategory?.id == shopping.id)
    #expect(try ledger.frequentPayees(kind: .expense, limit: 0).isEmpty)
}
