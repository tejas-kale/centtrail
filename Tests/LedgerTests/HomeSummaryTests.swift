import Ledger
import Testing

@Test func monthSummaryCountsOnlyThisMonthsSpendingThroughTodayAndIncludesRecentEntries() throws {
    let ledger = try Ledger.openInMemory()
    _ = try recordEntry(ledger, cents: 3000, kind: .expense, payee: "REWE", date: "2026-10-31", category: "Supermarket")
    _ = try recordEntry(ledger, cents: 4500, kind: .expense, payee: "Lidl", date: "2026-11-01", category: "Supermarket")
    _ = try recordEntry(ledger, cents: 3000, kind: .expense, payee: "Middle Eats", date: "2026-11-13", category: "Restaurant")
    _ = try recordEntry(ledger, cents: 2000, kind: .expense, payee: "Tomorrow", date: "2026-11-14", category: "Restaurant")
    _ = try recordEntry(ledger, cents: 50000, kind: .income, payee: "Acme", date: "2026-11-10", category: "Salary")
    _ = try recordEntry(ledger, cents: 20000, kind: .expense, payee: "Trade Republic", date: "2026-11-11", category: "Savings")
    let transfer = try recordEntry(ledger, cents: 10000, kind: .transfer, payee: "India", date: "2026-11-12", category: "Savings")
    _ = try recordEntry(ledger, cents: 1250, kind: .income, payee: "Lidl", date: "2026-11-09", category: "Supermarket")
    let trashed = try recordEntry(ledger, cents: 9000, kind: .expense, payee: "Mistake", date: "2026-11-13", category: "Supermarket")
    let today = try #require(ReportingDate(iso8601: "2026-11-13"))
    try ledger.trash(trashed.id, on: today)

    let summary = try ledger.monthSummary(on: today)

    #expect(summary.currentMonthRange == DateRange(start: try #require(ReportingDate(iso8601: "2026-11-01")), end: today))
    #expect(summary.spendingCents == 7500)
    #expect(summary.recentEntries.map(\.reportingDate.iso8601) == ["2026-11-14", "2026-11-13", "2026-11-12", "2026-11-11", "2026-11-10"])
    #expect(summary.recentEntries.contains { $0.id == transfer.id })
    #expect(!summary.recentEntries.contains { $0.id == trashed.id })
}

@Test func monthSummaryStartsFreshAtTheCalendarMonthAndKeepsRecentHistory() throws {
    let ledger = try Ledger.openInMemory()
    let previousMonth = try recordEntry(ledger, cents: 4200, kind: .expense, payee: "REWE", date: "2026-12-31", category: "Supermarket")
    let today = try #require(ReportingDate(iso8601: "2027-01-01"))

    let summary = try ledger.monthSummary(on: today)

    #expect(summary.currentMonthRange == DateRange(start: today, end: today))
    #expect(summary.spendingCents == 0)
    #expect(summary.recentEntries.map(\.id) == [previousMonth.id])
}
