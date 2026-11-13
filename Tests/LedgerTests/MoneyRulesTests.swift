import Ledger
import Testing

@Test func aConfirmedAliasResolvesToTheSameCounterparty() throws {
    let ledger = try Ledger.openInMemory()
    let amazon = try recordEntry(ledger, cents: 500, kind: .expense, counterparty: "Amazon", date: "2026-03-01", category: "Supermarket")
    try ledger.confirmAlias("AMZN MKTP", of: amazon.counterparty.id)
    let again = try recordEntry(ledger, cents: 700, kind: .expense, counterparty: "AMZN MKTP", date: "2026-03-02", category: "Supermarket")
    #expect(again.counterparty.id == amazon.counterparty.id)
    #expect(try ledger.counterparties().map(\.name) == ["Amazon"])
}

@Test func incomeUsesThePayerDefaultAndIsSeparateFromSpending() throws {
    let ledger = try Ledger.openInMemory()
    _ = try recordEntry(ledger, cents: 200_000, kind: .income, counterparty: "Acme", date: "2026-03-02", category: "Salary")
    _ = try recordEntry(ledger, cents: 1500, kind: .expense, counterparty: "REWE", date: "2026-03-02", category: "Supermarket")
    let today = try #require(ReportingDate(iso8601: "2026-03-15"))
    #expect(try ledger.defaultCategory(forCounterpartyName: "Acme")?.name == "Salary")
    #expect(try ledger.runReport(.currentMonthIncome, today: today) == .incomeTotal(SignedCents(200_000)))
    #expect(try ledger.runReport(.currentMonthSpending, today: today) == .spendingTotal(SignedCents(1500)))
}

@Test func aLinkedFebruaryRefundReducesFebruaryAndLeavesJanuary() throws {
    let ledger = try Ledger.openInMemory()
    let purchase = try recordEntry(ledger, cents: 10_000, kind: .expense, counterparty: "Osteria", date: "2026-01-10", category: "Restaurant")
    _ = try ledger.record(EntryDraft(amount: Cents(2000), kind: .refund, reportingDate: ReportingDate(iso8601: "2026-02-04"), originalPurchaseID: purchase.id))
    let today = try #require(ReportingDate(iso8601: "2026-03-01"))
    #expect(try spendingTotal(ledger, from: "2026-01-01", through: "2026-01-31", today: today) == 10_000)
    #expect(try spendingTotal(ledger, from: "2026-02-01", through: "2026-02-28", today: today) == -2000)
}

@Test func recategorizingOrTrashingThePurchaseLeavesTheRefundCategorized() throws {
    let ledger = try Ledger.openInMemory()
    let purchase = try recordEntry(ledger, cents: 10_000, kind: .expense, counterparty: "Osteria", date: "2026-01-10", category: "Restaurant")
    let refund = try ledger.record(EntryDraft(amount: Cents(2000), kind: .refund, reportingDate: ReportingDate(iso8601: "2026-02-04"), originalPurchaseID: purchase.id))
    try ledger.setCategory(try namedCategory(ledger, "Hotel").id, for: purchase.id)
    #expect(try ledger.transaction(id: refund.id).category.name == "Hotel")
    try ledger.trash(purchase.id, on: try #require(ReportingDate(iso8601: "2026-02-05")))
    #expect(try ledger.transaction(id: refund.id).category.name == "Hotel")
    let today = try #require(ReportingDate(iso8601: "2026-02-10"))
    #expect(try spendingTotal(ledger, from: "2026-02-01", through: "2026-02-28", today: today) == -2000)
}

@Test func anUnlinkedRefundNeedsAVendorAndCategory() throws {
    let ledger = try Ledger.openInMemory()
    #expect(throws: RecordEntryError.incomplete([.counterparty, .category])) {
        try ledger.record(EntryDraft(amount: Cents(500), kind: .refund, reportingDate: ReportingDate(iso8601: "2026-02-01")))
    }
}

@Test func savingsTransfersAndRepaymentsAreExcludedFromSpending() throws {
    let ledger = try Ledger.openInMemory()
    _ = try recordEntry(ledger, cents: 5_000, kind: .expense, counterparty: "REWE", date: "2026-03-01", category: "Supermarket")
    _ = try recordEntry(ledger, cents: 80_000, kind: .expense, counterparty: "Savings pot", date: "2026-03-02", category: "Savings")
    _ = try recordEntry(ledger, cents: 20_000, kind: .transfer, counterparty: "N26", date: "2026-03-03", category: "Salary")
    _ = try recordEntry(ledger, cents: 15_000, kind: .repayment, counterparty: "Visa", date: "2026-03-04", category: "Shopping")
    let today = try #require(ReportingDate(iso8601: "2026-03-15"))
    #expect(try ledger.runReport(.currentMonthSpending, today: today) == .spendingTotal(SignedCents(5_000)))
}

@Test func trashRestoreAndPurgeFollowTheInjectedDate() throws {
    let ledger = try Ledger.openInMemory()
    let kept = try recordEntry(ledger, cents: 1000, kind: .expense, counterparty: "REWE", date: "2026-03-01", category: "Supermarket")
    let old = try recordEntry(ledger, cents: 4000, kind: .expense, counterparty: "DB", date: "2026-03-02", category: "Train")
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
