import Ledger
import Testing

@Test func homeSummaryMidMonthComparesSameElapsedDaysAndFullPreviousMonth() throws {
    let ledger = try Ledger.openInMemory()
    _ = try recordEntry(ledger, cents: 3000, kind: .expense, payee: "REWE", date: "2026-10-05", category: "Supermarket")
    _ = try recordEntry(ledger, cents: 2000, kind: .expense, payee: "Middle Eats", date: "2026-10-13", category: "Restaurant")
    _ = try recordEntry(ledger, cents: 10000, kind: .expense, payee: "REWE", date: "2026-10-25", category: "Supermarket")
    _ = try recordEntry(ledger, cents: 4500, kind: .expense, payee: "Lidl", date: "2026-11-03", category: "Supermarket")
    _ = try recordEntry(ledger, cents: 3000, kind: .expense, payee: "Middle Eats", date: "2026-11-13", category: "Restaurant")
    _ = try recordEntry(ledger, cents: 50000, kind: .income, payee: "Acme", date: "2026-11-10", category: "Salary")
    _ = try recordEntry(ledger, cents: 20000, kind: .expense, payee: "Trade Republic", date: "2026-11-11", category: "Savings")
    _ = try recordEntry(ledger, cents: 10000, kind: .transfer, payee: "India", date: "2026-11-12", category: "Savings")

    let today = try #require(ReportingDate(iso8601: "2026-11-13"))
    let summary = try ledger.homeSummary(on: today)

    #expect(summary.currentMonthRange == DateRange(
        start: try #require(ReportingDate(iso8601: "2026-11-01")),
        end: today
    ))
    #expect(summary.previousSameDaysRange == DateRange(
        start: try #require(ReportingDate(iso8601: "2026-10-01")),
        end: try #require(ReportingDate(iso8601: "2026-10-13"))
    ))
    #expect(summary.previousFullMonthRange == DateRange(
        start: try #require(ReportingDate(iso8601: "2026-10-01")),
        end: try #require(ReportingDate(iso8601: "2026-10-31"))
    ))
    #expect(summary.currentSpendingCents == 7500)
    #expect(summary.previousSameDaysSpendingCents == 5000)
    #expect(summary.previousFullMonthSpendingCents == 15000)
    #expect(summary.changeCents == 2500)
    let percentage = try #require(summary.percentageChange)
    #expect(abs(percentage - 50.0) < 0.001)
    #expect(summary.unequalLengths == false)

    #expect(summary.categories.count == 2)
    #expect(summary.categories[0].category.name == "Supermarket")
    #expect(summary.categories[0].currentCents == 4500)
    #expect(summary.categories[0].previousSameDaysCents == 3000)
    #expect(summary.categories[0].previousFullMonthCents == 13000)
    #expect(summary.categories[1].category.name == "Restaurant")
    #expect(summary.categories[1].currentCents == 3000)
    #expect(summary.categories[1].previousSameDaysCents == 2000)
    #expect(summary.categories[1].previousFullMonthCents == 2000)
}

@Test func homeSummaryOnThirtyFirstAfterShorterMonthIsLabelledUnequal() throws {
    let ledger = try Ledger.openInMemory()
    _ = try recordEntry(ledger, cents: 2000, kind: .expense, payee: "REWE", date: "2026-02-28", category: "Supermarket")
    _ = try recordEntry(ledger, cents: 1000, kind: .expense, payee: "REWE", date: "2026-03-31", category: "Supermarket")

    let today = try #require(ReportingDate(iso8601: "2026-03-31"))
    let summary = try ledger.homeSummary(on: today)

    #expect(summary.unequalLengths == true)
    #expect(summary.previousSameDaysRange == DateRange(
        start: try #require(ReportingDate(iso8601: "2026-02-01")),
        end: try #require(ReportingDate(iso8601: "2026-02-28"))
    ))
    #expect(summary.previousFullMonthRange == DateRange(
        start: try #require(ReportingDate(iso8601: "2026-02-01")),
        end: try #require(ReportingDate(iso8601: "2026-02-28"))
    ))
    #expect(summary.currentSpendingCents == 1000)
    #expect(summary.previousSameDaysSpendingCents == 2000)
    #expect(summary.changeCents == -1000)
    let percentage = try #require(summary.percentageChange)
    #expect(abs(percentage - (-50.0)) < 0.001)
}

@Test func homeSummaryWithEmptyPreviousMonthOmitsPercentage() throws {
    let ledger = try Ledger.openInMemory()
    _ = try recordEntry(ledger, cents: 4200, kind: .expense, payee: "REWE", date: "2026-05-08", category: "Supermarket")

    let today = try #require(ReportingDate(iso8601: "2026-05-13"))
    let summary = try ledger.homeSummary(on: today)

    #expect(summary.currentSpendingCents == 4200)
    #expect(summary.previousSameDaysSpendingCents == 0)
    #expect(summary.previousFullMonthSpendingCents == 0)
    #expect(summary.changeCents == 4200)
    #expect(summary.percentageChange == nil)
    #expect(summary.unequalLengths == false)
}
