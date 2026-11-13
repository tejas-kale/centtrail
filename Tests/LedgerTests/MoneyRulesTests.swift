import Ledger
import Testing

@Test func aConfirmedAliasResolvesToTheSamePayee() throws {
    let ledger = try Ledger.openInMemory()
    let amazon = try recordEntry(ledger, cents: 500, kind: .expense, payee: "Amazon", date: "2026-03-01", category: "Supermarket")
    try ledger.confirmAlias("AMZN MKTP", of: amazon.payee.id)
    let again = try recordEntry(ledger, cents: 700, kind: .expense, payee: "AMZN MKTP", date: "2026-03-02", category: "Supermarket")
    #expect(again.payee.id == amazon.payee.id)
    #expect(try ledger.payees().map(\.name) == ["Amazon"])
}

@Test func incomeUsesThePayeeDefaultAndIsSeparateFromSpending() throws {
    let ledger = try Ledger.openInMemory()
    _ = try recordEntry(ledger, cents: 200_000, kind: .income, payee: "Acme", date: "2026-03-02", category: "Salary")
    _ = try recordEntry(ledger, cents: 1500, kind: .expense, payee: "REWE", date: "2026-03-02", category: "Supermarket")
    let today = try #require(ReportingDate(iso8601: "2026-03-15"))
    #expect(try ledger.defaultCategory(forPayeeName: "Acme")?.name == "Salary")
    #expect(try ledger.runReport(.currentMonthIncome, today: today) == .incomeTotal(SignedCents(200_000)))
    #expect(try ledger.runReport(.currentMonthSpending, today: today) == .spendingTotal(SignedCents(1500)))
}

@Test func transactionKindsAreExpenseIncomeAndTransferOnly() {
    #expect(Kind(rawValue: "expense") == .expense)
    #expect(Kind(rawValue: "income") == .income)
    #expect(Kind(rawValue: "transfer") == .transfer)
    #expect(Kind(rawValue: "refund") == nil)
    #expect(Kind(rawValue: "repayment") == nil)
}

@Test func novemberPurchaseAndRefundReportGrossSpendingAndIncome() throws {
    let ledger = try Ledger.openInMemory()
    _ = try recordEntry(ledger, cents: 10_000, kind: .expense, payee: "Zara", date: "2026-11-05", category: "Shopping")
    _ = try recordEntry(ledger, cents: 10_000, kind: .income, payee: "Zara", date: "2026-11-12", category: "Shopping")
    let today = try #require(ReportingDate(iso8601: "2026-11-20"))
    #expect(try ledger.runReport(.currentMonthSpending, today: today) == .spendingTotal(SignedCents(10_000)))
    #expect(try ledger.runReport(.currentMonthIncome, today: today) == .incomeTotal(SignedCents(10_000)))
}

@Test func savingsAndTransfersAreExcludedFromSpending() throws {
    let ledger = try Ledger.openInMemory()
    _ = try recordEntry(ledger, cents: 5_000, kind: .expense, payee: "REWE", date: "2026-03-01", category: "Supermarket")
    _ = try recordEntry(ledger, cents: 80_000, kind: .expense, payee: "Savings pot", date: "2026-03-02", category: "Savings")
    _ = try recordEntry(ledger, cents: 20_000, kind: .transfer, payee: "N26", date: "2026-03-03", category: "Salary")
    let today = try #require(ReportingDate(iso8601: "2026-03-15"))
    #expect(try ledger.runReport(.currentMonthSpending, today: today) == .spendingTotal(SignedCents(5_000)))
}

@Test func trashRestoreAndPurgeFollowTheInjectedDate() throws {
    let ledger = try Ledger.openInMemory()
    let kept = try recordEntry(ledger, cents: 1000, kind: .expense, payee: "REWE", date: "2026-03-01", category: "Supermarket")
    let old = try recordEntry(ledger, cents: 4000, kind: .expense, payee: "DB", date: "2026-03-02", category: "Train")
    try ledger.trash(old.id, on: try #require(ReportingDate(iso8601: "2026-03-01")))
    let today = try #require(ReportingDate(iso8601: "2026-03-20"))
    #expect(try ledger.transactions().map(\.id) == [kept.id])
    #expect(try ledger.runReport(.currentMonthSpending, today: today) == .spendingTotal(SignedCents(1000)))
    #expect(try ledger.trashedEntries(today: today).map(\.daysRemaining) == [11])
    try ledger.restore(old.id)
    #expect(try ledger.runReport(.currentMonthSpending, today: today) == .spendingTotal(SignedCents(5000)))
    try ledger.trash(old.id, on: try #require(ReportingDate(iso8601: "2026-01-01")))
    try ledger.purgeExpiredTrash(today: try #require(ReportingDate(iso8601: "2026-02-01")))
    #expect(try ledger.trashedEntries(today: today).isEmpty)
    #expect(throws: RecordEntryError.unknownEntry) { try ledger.transaction(id: old.id) }
}
