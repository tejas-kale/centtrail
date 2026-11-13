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
