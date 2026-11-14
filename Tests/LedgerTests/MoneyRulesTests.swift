import Ledger
import Testing

@Test func aConfirmedAliasResolvesToTheSamePayee() throws {
    let ledger = try Ledger.openInMemory()
    let amazon = try recordEntry(ledger, cents: 500, kind: .expense, payee: "Amazon", date: "2026-03-01", category: "Supermarket")
    try ledger.confirmAlias("AMZN MKTP", of: amazon.payee!.id)
    let again = try recordEntry(ledger, cents: 700, kind: .expense, payee: "AMZN MKTP", date: "2026-03-02", category: "Supermarket")
    #expect(again.payee!.id == amazon.payee!.id)
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

@Test func trashedEntriesPurgeAutomaticallyAfterThirtyDaysAndRestoreUpdatesTotals() throws {
    let ledger = try Ledger.openInMemory()
    let kept = try recordEntry(ledger, cents: 1_000, kind: .expense, payee: "REWE", date: "2026-03-01", category: "Supermarket")
    let restorable = try recordEntry(ledger, cents: 2_500, kind: .expense, payee: "Lidl", date: "2026-03-02", category: "Supermarket")
    let expired = try recordEntry(ledger, cents: 4_000, kind: .expense, payee: "DB", date: "2026-01-10", category: "Train")

    try ledger.trash(restorable.id, on: try #require(ReportingDate(iso8601: "2026-03-05")))
    try ledger.trash(expired.id, on: try #require(ReportingDate(iso8601: "2026-01-31")))

    let today = try #require(ReportingDate(iso8601: "2026-03-03"))
    // On 2026-03-03, 2026-01-31 is 31 days ago (> 30), so trashedEntries(today:) purges it automatically.
    // Wait: restorable was trashed on 2026-03-05, so let's query on 2026-03-06 (34 days after 2026-01-31, 1 day after 2026-03-05).
    let checkDate = try #require(ReportingDate(iso8601: "2026-03-06"))
    let trashed = try ledger.trashedEntries(today: checkDate)
    #expect(trashed.map(\.id) == [restorable.id])
    #expect(trashed.map(\.daysRemaining) == [29])
    #expect(throws: RecordEntryError.unknownEntry) { try ledger.transaction(id: expired.id) }

    // Before restore, only kept (1000) is in March spending total
    #expect(try ledger.runReport(.currentMonthSpending, today: checkDate) == .spendingTotal(SignedCents(1_000)))
    try ledger.restore(restorable.id)
    // After restore, kept + restorable (3500) are in March spending total
    #expect(try ledger.runReport(.currentMonthSpending, today: checkDate) == .spendingTotal(SignedCents(3_500)))
    #expect(try ledger.transactions().map(\.id).contains(kept.id))
    #expect(try ledger.transactions().map(\.id).contains(restorable.id))
    _ = today
}
