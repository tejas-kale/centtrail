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
    _ = try recordEntry(ledger, cents: 3000, kind: .expense, counterparty: "REWE", date: "2026-03-05", category: "Supermarket")
    _ = try recordEntry(ledger, cents: 9000, kind: .expense, counterparty: "REWE", date: "2026-03-20", category: "Supermarket")
    _ = try recordEntry(ledger, cents: 4000, kind: .expense, counterparty: "REWE", date: "2026-04-04", category: "Supermarket")
    let today = try #require(ReportingDate(iso8601: "2026-04-10"))
    guard case .comparison(let comparison) = try ledger.runReport(.comparison(measure: .spending, categoryID: nil, counterpartyName: nil), today: today) else {
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
    guard case .comparison(let comparison) = try ledger.runReport(.comparison(measure: .spending, categoryID: nil, counterpartyName: nil), today: today) else {
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
    let before = try recordEntry(ledger, cents: 8_000, kind: .expense, counterparty: "REWE", date: "2025-12-31", category: "Supermarket")
    let onStart = try recordEntry(ledger, cents: 6_000, kind: .expense, counterparty: "REWE", date: "2026-01-01", category: "Supermarket")
    let restaurant = try recordEntry(ledger, cents: 9_000, kind: .expense, counterparty: "Middle Eats", date: "2026-01-15", category: "Restaurant")
    let onEnd = try recordEntry(ledger, cents: 4_000, kind: .expense, counterparty: "Lidl", date: "2026-01-31", category: "Supermarket")
    let after = try recordEntry(ledger, cents: 8_000, kind: .expense, counterparty: "REWE", date: "2026-02-01", category: "Supermarket")
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

    let withVendorAndAmount = try ledger.runReport(
        .search(ReportQuery(
            measure: .spending,
            range: range,
            categoryID: supermarket.id,
            counterpartyName: "REWE",
            amount: .greaterThan(Cents(5_000))
        )),
        today: today
    )
    #expect(withVendorAndAmount == .transactions([onStart]))
}

@Test func searchFindsAnAliasAndAnAmountAndSkipsTrash() throws {
    let ledger = try Ledger.openInMemory()
    let amazon = try recordEntry(ledger, cents: 8_000, kind: .expense, counterparty: "Amazon", date: "2026-01-02", category: "Supermarket")
    try ledger.confirmAlias("AMZN MKTP", of: amazon.counterparty.id)
    let trashed = try recordEntry(ledger, cents: 9_000, kind: .expense, counterparty: "Amazon", date: "2026-01-03", category: "Supermarket")
    try ledger.trash(trashed.id, on: try #require(ReportingDate(iso8601: "2026-01-04")))
    let today = try #require(ReportingDate(iso8601: "2026-02-01"))
    let found = try ledger.runReport(.search(ReportQuery(measure: .spending, counterpartyName: "AMZN MKTP", amount: .greaterThan(Cents(5000)))), today: today)
    #expect(found == .transactions([amazon]))
}

@Test func breakdownGroupsACategoryAcrossMonths() throws {
    let ledger = try Ledger.openInMemory()
    let utilities = try namedCategory(ledger, "Utilities")
    _ = try recordEntry(ledger, cents: 1000, kind: .expense, counterparty: "Vattenfall", date: "2026-01-02", category: "Utilities")
    _ = try recordEntry(ledger, cents: 2500, kind: .expense, counterparty: "Vattenfall", date: "2026-03-02", category: "Utilities")
    let today = try #require(ReportingDate(iso8601: "2026-03-10"))
    let result = try ledger.runReport(.breakdown(ReportQuery(measure: .spending, range: DateRange(start: try #require(ReportingDate(iso8601: "2026-01-01")), end: try #require(ReportingDate(iso8601: "2026-03-31"))), categoryID: utilities.id, grouping: .month)), today: today)
    guard case .breakdown(let rows, _) = result else { Issue.record("Expected a breakdown"); return }
    #expect(rows.map(\.cents) == [1000, 0, 2500])
}

@Test func requiredReportFixturesScoreTheOperationAndArguments() throws {
    let ledger = try Ledger.openInMemory()
    _ = try recordEntry(ledger, cents: 100, kind: .expense, counterparty: "Amazon", date: "2026-03-01", category: "Supermarket")
    _ = try recordEntry(ledger, cents: 100, kind: .expense, counterparty: "Amazon Fresh", date: "2026-03-02", category: "Supermarket")
    let today = try #require(ReportingDate(iso8601: "2026-04-10"))
    let interpreter = Interpreter(ledger: ledger, today: today, modelUnavailableReason: .modelNotReady)
    let restaurant = try namedCategory(ledger, "Restaurant")
    let utilities = try namedCategory(ledger, "Utilities")
    #expect(interpreter.score(try interpreter.interpretReport("how much did I spend this month?"), expected: .operation(.total(ReportQuery(measure: .spending)))).passed)
    #expect(interpreter.score(try interpreter.interpretReport("spent on restaurants compared with last month"), expected: .operation(.comparison(measure: .spending, categoryID: restaurant.id, counterpartyName: nil))).passed)
    #expect(interpreter.score(try interpreter.interpretReport("utilities over months"), expected: .operation(.breakdown(ReportQuery(measure: .spending, categoryID: utilities.id, grouping: .month)))).passed)
    #expect(interpreter.score(try interpreter.interpretReport("monthly spending by category"), expected: .operation(.breakdown(ReportQuery(measure: .spending, grouping: .category)))).passed)
    #expect(interpreter.score(try interpreter.interpretReport("find purchases over 50"), expected: .operation(.search(ReportQuery(measure: .spending, amount: .greaterThan(Cents(5000)))))).passed)
    #expect(try interpreter.interpretReport("how much did I spend at Amazon") == .clarification(["Amazon", "Amazon Fresh"]))
    guard case .unsupported = try interpreter.interpretReport("what is my net worth?") else { Issue.record("unsupported"); return }
    #expect(interpreter.score(.operation(.total(ReportQuery(measure: .spending))), expected: .operation(.breakdown(ReportQuery(measure: .spending, grouping: .category)))).operationMatches == false)
}

@Test func typedAndDictatedCaptureFillTheSameDraft() throws {
    let ledger = try Ledger.openInMemory()
    _ = try recordEntry(ledger, cents: 100, kind: .expense, counterparty: "Middle Eats", date: "2026-01-01", category: "Restaurant")
    let today = try #require(ReportingDate(iso8601: "2026-04-10"))
    let interpreter = Interpreter(ledger: ledger, today: today)
    let typed = try interpreter.interpretCapture("20 at Middle Eats yesterday")
    #expect(typed == (try interpreter.interpretCapture("20 at Middle Eats yesterday")))
    #expect(typed.modelUnavailable == .modelNotReady)
    #expect(typed.draft.amount == Cents(2000))
    #expect(typed.draft.kind == .expense)
    #expect(typed.draft.counterparty == "Middle Eats")
    #expect(typed.draft.reportingDate?.iso8601 == "2026-04-09")
    let restaurant = try namedCategory(ledger, "Restaurant")
    #expect(typed.draft.categoryID == restaurant.id)
}
