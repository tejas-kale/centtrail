import Interpreter
import Ledger
import Testing

@Test func omittedPeriodIsTheCurrentMonthAndEmptyPeriodsAreZero() throws {
    let ledger = try Ledger.openInMemory()
    let today = try #require(ReportingDate(iso8601: "2026-04-10"))
    let result = try ledger.runReport(.total(ReportQuery(measure: .spending)), today: today)
    #expect(result == .total(cents: 0, range: DateRange(start: try #require(ReportingDate(iso8601: "2026-04-01")), end: try #require(ReportingDate(iso8601: "2026-04-30")))))
}

@Test func thisMonthVersusLastMonthUsesMatchingElapsedDays() throws {
    let ledger = try Ledger.openInMemory()
    _ = try recordEntry(ledger, cents: 3000, kind: .expense, payee: "REWE", date: "2026-03-05", category: "Supermarket")
    _ = try recordEntry(ledger, cents: 9000, kind: .expense, payee: "REWE", date: "2026-03-20", category: "Supermarket")
    _ = try recordEntry(ledger, cents: 4000, kind: .expense, payee: "REWE", date: "2026-04-04", category: "Supermarket")
    let today = try #require(ReportingDate(iso8601: "2026-04-10"))
    guard case .comparison(let comparison) = try ledger.runReport(.comparison(measure: .spending, categoryID: nil, payeeName: nil), today: today) else {
        Issue.record("Expected a comparison")
        return
    }
    #expect(comparison.earlier.range.end.iso8601 == "2026-03-10")
    #expect(comparison.later.range.end.iso8601 == "2026-04-10")
    #expect(comparison.earlier.cents == 3000)
    #expect(comparison.later.cents == 4000)
    #expect(comparison.absoluteChangeCents == 1000)
    #expect(comparison.unequalLengths == false)
}

@Test func aShorterPreviousMonthIsLabelledAndAZeroBaseHidesThePercentage() throws {
    let ledger = try Ledger.openInMemory()
    let today = try #require(ReportingDate(iso8601: "2026-03-30"))
    guard case .comparison(let comparison) = try ledger.runReport(.comparison(measure: .spending, categoryID: nil, payeeName: nil), today: today) else {
        Issue.record("Expected a comparison")
        return
    }
    #expect(comparison.earlier.range.end.iso8601 == "2026-02-28")
    #expect(comparison.later.range.end.iso8601 == "2026-03-30")
    #expect(comparison.unequalLengths == true)
    #expect(comparison.percentageChange == nil)
    #expect(comparison.absoluteChangeCents == 0)
}

@Test func searchFiltersByCategoryAndInclusiveDateRange() throws {
    let ledger = try Ledger.openInMemory()
    let supermarket = try namedCategory(ledger, "Supermarket")
    let before = try recordEntry(ledger, cents: 8_000, kind: .expense, payee: "REWE", date: "2025-12-31", category: "Supermarket")
    let onStart = try recordEntry(ledger, cents: 6_000, kind: .expense, payee: "REWE", date: "2026-01-01", category: "Supermarket")
    let restaurant = try recordEntry(ledger, cents: 9_000, kind: .expense, payee: "Middle Eats", date: "2026-01-15", category: "Restaurant")
    let onEnd = try recordEntry(ledger, cents: 4_000, kind: .expense, payee: "Lidl", date: "2026-01-31", category: "Supermarket")
    let after = try recordEntry(ledger, cents: 8_000, kind: .expense, payee: "REWE", date: "2026-02-01", category: "Supermarket")
    let today = try #require(ReportingDate(iso8601: "2026-04-10"))
    let range = DateRange(
        start: try #require(ReportingDate(iso8601: "2026-01-01")),
        end: try #require(ReportingDate(iso8601: "2026-01-31"))
    )

    let byCategory = try ledger.runReport(.search(ReportQuery(measure: .spending, categoryID: supermarket.id)), today: today)
    #expect(byCategory == .transactions([after, onEnd, onStart, before]))

    let byDates = try ledger.runReport(.search(ReportQuery(measure: .spending, range: range)), today: today)
    #expect(byDates == .transactions([onEnd, restaurant, onStart]))

    let byCategoryAndDates = try ledger.runReport(
        .search(ReportQuery(measure: .spending, range: range, categoryID: supermarket.id)),
        today: today
    )
    #expect(byCategoryAndDates == .transactions([onEnd, onStart]))

    let withPayeeAndAmount = try ledger.runReport(
        .search(ReportQuery(
            measure: .spending,
            range: range,
            categoryID: supermarket.id,
            payeeName: "REWE",
            amount: .greaterThan(Cents(5_000))
        )),
        today: today
    )
    #expect(withPayeeAndAmount == .transactions([onStart]))
}

@Test func searchFindsAnAliasAndAnAmountAndSkipsTrash() throws {
    let ledger = try Ledger.openInMemory()
    let amazon = try recordEntry(ledger, cents: 8_000, kind: .expense, payee: "Amazon", date: "2026-01-02", category: "Supermarket")
    try ledger.confirmAlias("AMZN MKTP", of: amazon.payee.id)
    let trashed = try recordEntry(ledger, cents: 9_000, kind: .expense, payee: "Amazon", date: "2026-01-03", category: "Supermarket")
    try ledger.trash(trashed.id, on: try #require(ReportingDate(iso8601: "2026-01-04")))
    let today = try #require(ReportingDate(iso8601: "2026-02-01"))
    let found = try ledger.runReport(.search(ReportQuery(measure: .spending, payeeName: "AMZN MKTP", amount: .greaterThan(Cents(5000)))), today: today)
    #expect(found == .transactions([amazon]))
}

@Test func trashedEntriesAreExcludedFromBreakdownsAndComparisons() throws {
    let ledger = try Ledger.openInMemory()
    _ = try recordEntry(ledger, cents: 1000, kind: .expense, payee: "REWE", date: "2026-01-15", category: "Supermarket")
    let february = try recordEntry(ledger, cents: 8000, kind: .expense, payee: "REWE", date: "2026-02-02", category: "Supermarket")
    try ledger.trash(february.id, on: try #require(ReportingDate(iso8601: "2026-02-03")))
    _ = try recordEntry(ledger, cents: 3000, kind: .expense, payee: "REWE", date: "2026-03-05", category: "Supermarket")
    let marchTrash = try recordEntry(ledger, cents: 9000, kind: .expense, payee: "Osteria", date: "2026-03-06", category: "Restaurant")
    try ledger.trash(marchTrash.id, on: try #require(ReportingDate(iso8601: "2026-03-07")))
    _ = try recordEntry(ledger, cents: 4000, kind: .expense, payee: "REWE", date: "2026-04-04", category: "Supermarket")
    let aprilTrash = try recordEntry(ledger, cents: 7000, kind: .expense, payee: "REWE", date: "2026-04-02", category: "Supermarket")
    try ledger.trash(aprilTrash.id, on: try #require(ReportingDate(iso8601: "2026-04-03")))
    let marchIncome = try recordEntry(ledger, cents: 150_000, kind: .income, payee: "Acme", date: "2026-03-08", category: "Salary")
    try ledger.trash(marchIncome.id, on: try #require(ReportingDate(iso8601: "2026-03-09")))
    _ = try recordEntry(ledger, cents: 10_000, kind: .income, payee: "Acme", date: "2026-04-03", category: "Salary")
    let aprilIncome = try recordEntry(ledger, cents: 50_000, kind: .income, payee: "Acme", date: "2026-04-05", category: "Salary")
    try ledger.trash(aprilIncome.id, on: try #require(ReportingDate(iso8601: "2026-04-06")))

    let today = try #require(ReportingDate(iso8601: "2026-04-10"))
    let range = DateRange(
        start: try #require(ReportingDate(iso8601: "2026-01-01")),
        end: try #require(ReportingDate(iso8601: "2026-04-30"))
    )
    guard case .comparison(let spending) = try ledger.runReport(.comparison(measure: .spending, categoryID: nil, payeeName: nil), today: today) else {
        Issue.record("Expected a spending comparison")
        return
    }
    #expect(spending.earlier.cents == 3000)
    #expect(spending.later.cents == 4000)
    #expect(spending.absoluteChangeCents == 1000)

    guard case .comparison(let income) = try ledger.runReport(.comparison(measure: .income, categoryID: nil, payeeName: nil), today: today) else {
        Issue.record("Expected an income comparison")
        return
    }
    #expect(income.earlier.cents == 0)
    #expect(income.later.cents == 10_000)
    #expect(income.absoluteChangeCents == 10_000)

    guard case .breakdown(let months, _) = try ledger.runReport(.breakdown(ReportQuery(measure: .spending, range: range, grouping: .month)), today: today) else {
        Issue.record("Expected a monthly breakdown")
        return
    }
    #expect(months.map(\.month) == ["2026-01", "2026-02", "2026-03", "2026-04"])
    #expect(months.map(\.cents) == [1000, 0, 3000, 4000])

    guard case .breakdown(let categories, _) = try ledger.runReport(.breakdown(ReportQuery(measure: .spending, range: range, grouping: .category)), today: today) else {
        Issue.record("Expected a category breakdown")
        return
    }
    #expect(categories.map(\.categoryName) == ["Salary", "Supermarket"])
    #expect(categories.map(\.cents) == [0, 8000])

    guard case .breakdown(let both, _) = try ledger.runReport(.breakdown(ReportQuery(measure: .spending, range: range, grouping: .monthAndCategory)), today: today) else {
        Issue.record("Expected a month and category breakdown")
        return
    }
    #expect(both.map(\.month) == ["2026-01", "2026-02", "2026-03", "2026-04", "2026-04"])
    #expect(both.map(\.categoryName) == ["Supermarket", nil, "Supermarket", "Salary", "Supermarket"] as [String?])
    #expect(both.map(\.cents) == [1000, 0, 3000, 0, 4000])

    guard case .breakdown(let incomeMonths, _) = try ledger.runReport(.breakdown(ReportQuery(measure: .income, range: range, grouping: .month)), today: today) else {
        Issue.record("Expected an income breakdown")
        return
    }
    #expect(incomeMonths.map(\.cents) == [0, 0, 0, 10_000])
}

@Test func breakdownGroupsACategoryAcrossMonths() throws {
    let ledger = try Ledger.openInMemory()
    let utilities = try namedCategory(ledger, "Utilities")
    _ = try recordEntry(ledger, cents: 1000, kind: .expense, payee: "Vattenfall", date: "2026-01-02", category: "Utilities")
    _ = try recordEntry(ledger, cents: 2500, kind: .expense, payee: "Vattenfall", date: "2026-03-02", category: "Utilities")
    let today = try #require(ReportingDate(iso8601: "2026-03-10"))
    let result = try ledger.runReport(.breakdown(ReportQuery(measure: .spending, range: DateRange(start: try #require(ReportingDate(iso8601: "2026-01-01")), end: try #require(ReportingDate(iso8601: "2026-03-31"))), categoryID: utilities.id, grouping: .month)), today: today)
    guard case .breakdown(let rows, _) = result else { Issue.record("Expected a breakdown"); return }
    #expect(rows.map(\.cents) == [1000, 0, 2500])
}

@Test func requiredReportFixturesScoreTheOperationAndArguments() throws {
    let ledger = try Ledger.openInMemory()
    _ = try recordEntry(ledger, cents: 100, kind: .expense, payee: "Amazon", date: "2026-03-01", category: "Supermarket")
    _ = try recordEntry(ledger, cents: 100, kind: .expense, payee: "Amazon Fresh", date: "2026-03-02", category: "Supermarket")
    let today = try #require(ReportingDate(iso8601: "2026-04-10"))
    let interpreter = Interpreter(ledger: ledger, today: today, modelUnavailableReason: .modelNotReady)
    let restaurant = try namedCategory(ledger, "Restaurant")
    let utilities = try namedCategory(ledger, "Utilities")
    #expect(interpreter.score(try interpreter.interpretReport("how much did I spend this month?"), expected: .operation(.total(ReportQuery(measure: .spending)))).passed)
    #expect(interpreter.score(try interpreter.interpretReport("spent on restaurants compared with last month"), expected: .operation(.comparison(measure: .spending, categoryID: restaurant.id, payeeName: nil))).passed)
    #expect(interpreter.score(try interpreter.interpretReport("utilities over months"), expected: .operation(.breakdown(ReportQuery(measure: .spending, categoryID: utilities.id, grouping: .month)))).passed)
    #expect(interpreter.score(try interpreter.interpretReport("monthly spending by category"), expected: .operation(.breakdown(ReportQuery(measure: .spending, grouping: .category)))).passed)
    #expect(interpreter.score(try interpreter.interpretReport("find purchases over 50"), expected: .operation(.search(ReportQuery(measure: .spending, amount: .greaterThan(Cents(5000)))))).passed)
    #expect(try interpreter.interpretReport("how much did I spend at Amazon") == .clarification(["Amazon", "Amazon Fresh"]))
    guard case .unsupported = try interpreter.interpretReport("what is my net worth?") else { Issue.record("unsupported"); return }
    #expect(interpreter.score(.operation(.total(ReportQuery(measure: .spending))), expected: .operation(.breakdown(ReportQuery(measure: .spending, grouping: .category)))).operationMatches == false)
}

@Test func typedAndDictatedCaptureFillTheSameDraft() throws {
    let ledger = try Ledger.openInMemory()
    _ = try recordEntry(ledger, cents: 100, kind: .expense, payee: "Middle Eats", date: "2026-01-01", category: "Restaurant")
    let today = try #require(ReportingDate(iso8601: "2026-04-10"))
    let interpreter = Interpreter(ledger: ledger, today: today, backend: KeywordLanguageModelBackend())
    let typed = try interpreter.interpretCapture("20 at Middle Eats yesterday")
    #expect(typed == (try interpreter.interpretCapture("20 at Middle Eats yesterday")))
    #expect(typed.modelUnavailable == .modelNotReady)
    #expect(typed.draft.amount == Cents(2000))
    #expect(typed.draft.kind == .expense)
    #expect(typed.draft.payee == "Middle Eats")
    #expect(typed.draft.reportingDate?.iso8601 == "2026-04-09")
    let restaurant = try namedCategory(ledger, "Restaurant")
    #expect(typed.draft.categoryID == restaurant.id)
}
