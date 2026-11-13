import Ledger
import Testing

@Test func aNewCounterpartyKeepsTheChosenCategoryAsItsDefault() throws {
    let ledger = try Ledger.openInMemory()
    let supermarket = try namedCategory(ledger, "Supermarket")
    let recorded = try recordEntry(ledger, cents: 1250, kind: .expense, counterparty: "REWE", date: "2026-03-02", category: "Supermarket")
    #expect(recorded.categoryProvenance == .inherited)
    #expect(recorded.counterparty.defaultCategory == supermarket)
    #expect(try ledger.defaultCategory(forCounterpartyName: "REWE") == supermarket)
}

@Test func anExplicitOverrideKeepsItsCategoryWhenTheDefaultChanges() throws {
    let ledger = try Ledger.openInMemory()
    let household = try namedCategory(ledger, "Household Requirements")
    let recorded = try recordEntry(ledger, cents: 1250, kind: .expense, counterparty: "REWE", date: "2026-01-04", category: "Supermarket")
    try ledger.setCategory(household.id, for: recorded.id)
    try ledger.setDefaultCategory(try namedCategory(ledger, "Restaurant").id, for: recorded.counterparty.id)
    let reread = try ledger.transactions().first { $0.id == recorded.id }
    #expect(reread?.category.name == "Household Requirements")
    #expect(reread?.categoryProvenance == .overridden)
    #expect(reread?.counterparty.defaultCategory.name == "Restaurant")
}

@Test func changingTheDefaultRecategorizesInheritedEntriesInAPastMonth() throws {
    let ledger = try Ledger.openInMemory()
    let recorded = try recordEntry(ledger, cents: 2000, kind: .expense, counterparty: "REWE", date: "2026-01-04", category: "Supermarket")
    let restaurant = try namedCategory(ledger, "Restaurant")
    try ledger.setDefaultCategory(restaurant.id, for: recorded.counterparty.id)
    let today = try #require(ReportingDate(iso8601: "2026-03-01"))
    let start = try #require(ReportingDate(iso8601: "2026-01-01"))
    let end = try #require(ReportingDate(iso8601: "2026-01-31"))
    let january = try ledger.runReport(.total(ReportQuery(measure: .spending, range: DateRange(start: start, end: end), categoryID: restaurant.id)), today: today)
    #expect(january == .total(cents: 2000, range: DateRange(start: start, end: end)))
    #expect(try ledger.transactions().first?.categoryProvenance == .inherited)
}

@Test func anOverrideToTheSameCategoryIsStillAnOverride() throws {
    let ledger = try Ledger.openInMemory()
    let supermarket = try namedCategory(ledger, "Supermarket")
    let recorded = try ledger.record(EntryDraft(amount: Cents(100), kind: .expense, counterparty: "REWE", reportingDate: ReportingDate(iso8601: "2026-03-01"), categoryID: supermarket.id, overridesCategory: true))
    #expect(recorded.categoryProvenance == .overridden)
    #expect(recorded.category.id == recorded.counterparty.defaultCategory.id)
}

@Test func setCategoryOnOneEntryLeavesTheCounterpartyDefault() throws {
    let ledger = try Ledger.openInMemory()
    let supermarket = try namedCategory(ledger, "Supermarket")
    let household = try namedCategory(ledger, "Household Requirements")
    let recorded = try recordEntry(ledger, cents: 1250, kind: .expense, counterparty: "REWE", date: "2026-03-02", category: "Supermarket")
    try ledger.setCategory(household.id, for: recorded.id)

    let reread = try ledger.transaction(id: recorded.id)
    #expect(reread.category == household)
    #expect(reread.categoryProvenance == .overridden)
    #expect(reread.counterparty.defaultCategory == supermarket)
    #expect(try ledger.defaultCategory(forCounterpartyName: "REWE") == supermarket)

    let next = try recordEntry(ledger, cents: 800, kind: .expense, counterparty: "REWE", date: "2026-03-03", category: "Supermarket")
    #expect(next.categoryProvenance == .inherited)
    #expect(next.category == supermarket)
    #expect(next.counterparty.defaultCategory == supermarket)
}

@Test func anIncomePayerOverrideBehavesLikeAVendorOverride() throws {
    let ledger = try Ledger.openInMemory()
    let salary = try namedCategory(ledger, "Salary")
    let kindergeld = try namedCategory(ledger, "Kindergeld")
    let utilities = try namedCategory(ledger, "Utilities")
    let inherited = try recordEntry(ledger, cents: 200_000, kind: .income, counterparty: "Acme", date: "2026-01-04", category: "Salary")
    let sameCategoryOverride = try ledger.record(EntryDraft(
        amount: Cents(10_000),
        kind: .income,
        counterparty: "Acme",
        reportingDate: ReportingDate(iso8601: "2026-01-10"),
        categoryID: salary.id,
        overridesCategory: true
    ))
    let overridden = try recordEntry(ledger, cents: 40_000, kind: .income, counterparty: "Acme", date: "2026-01-20", category: "Salary")
    try ledger.setCategory(kindergeld.id, for: overridden.id)

    #expect(inherited.categoryProvenance == .inherited)
    #expect(sameCategoryOverride.categoryProvenance == .overridden)
    #expect(sameCategoryOverride.category.id == salary.id)
    #expect(try ledger.transaction(id: overridden.id).category == kindergeld)
    #expect(try ledger.transaction(id: overridden.id).categoryProvenance == .overridden)
    #expect(try ledger.defaultCategory(forCounterpartyName: "Acme") == salary)

    try ledger.setDefaultCategory(utilities.id, for: inherited.counterparty.id)
    let today = try #require(ReportingDate(iso8601: "2026-03-01"))
    #expect(try ledger.transaction(id: inherited.id).category == utilities)
    #expect(try ledger.transaction(id: inherited.id).categoryProvenance == .inherited)
    #expect(try ledger.transaction(id: sameCategoryOverride.id).category == salary)
    #expect(try ledger.transaction(id: sameCategoryOverride.id).categoryProvenance == .overridden)
    #expect(try ledger.transaction(id: overridden.id).category == kindergeld)
    #expect(try ledger.transaction(id: overridden.id).categoryProvenance == .overridden)
    #expect(try ledger.defaultCategory(forCounterpartyName: "Acme") == utilities)
    #expect(try categoryTotal(ledger, measure: .income, category: utilities, from: "2026-01-01", through: "2026-01-31", today: today) == 200_000)
    #expect(try categoryTotal(ledger, measure: .income, category: kindergeld, from: "2026-01-01", through: "2026-01-31", today: today) == 40_000)
    #expect(try categoryTotal(ledger, measure: .income, category: salary, from: "2026-01-01", through: "2026-01-31", today: today) == 10_000)
    #expect(try categoryTotal(ledger, measure: .spending, category: utilities, from: "2026-01-01", through: "2026-01-31", today: today) == 0)

    let later = try recordEntry(ledger, cents: 80_000, kind: .income, counterparty: "Acme", date: "2026-02-02", category: "Utilities")
    #expect(later.categoryProvenance == .inherited)
    #expect(later.counterparty.defaultCategory == utilities)
    try ledger.setCategory(salary.id, for: later.id)
    #expect(try ledger.transaction(id: later.id).category == salary)
    #expect(try ledger.transaction(id: later.id).categoryProvenance == .overridden)
    #expect(try ledger.defaultCategory(forCounterpartyName: "Acme") == utilities)
    #expect(try ledger.transaction(id: inherited.id).category == utilities)
}

private func categoryTotal(
    _ ledger: Ledger,
    measure: Measure,
    category: Category,
    from start: String,
    through end: String,
    today: ReportingDate
) throws -> Int {
    let result = try ledger.runReport(
        .total(ReportQuery(
            measure: measure,
            range: DateRange(
                start: try #require(ReportingDate(iso8601: start)),
                end: try #require(ReportingDate(iso8601: end))
            ),
            categoryID: category.id
        )),
        today: today
    )
    guard case .total(let cents, _) = result else {
        Issue.record("Expected a total")
        return -1
    }
    return cents
}
