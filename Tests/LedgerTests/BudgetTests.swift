import Foundation
import Ledger
import Testing

@Test func budgetsCanBeSetChangedAndRemovedWithAtMostOnePerSpendingCategory() throws {
    let ledger = try Ledger.openInMemory()
    let groceries = try namedCategory(ledger, "Supermarket")
    let dining = try namedCategory(ledger, "Restaurant")
    let savings = try namedCategory(ledger, "Savings")

    #expect(try ledger.budgets().isEmpty)

    let created = try ledger.setBudget(categoryID: groceries.id, amount: Cents(40_000), currency: .eur)
    #expect(created.category == groceries)
    #expect(created.currency == .eur)
    #expect(created.amount == Cents(40_000))
    #expect(try ledger.budgets() == [created])

    // Changing a budget updates it in place rather than creating a second budget for the category.
    let updated = try ledger.setBudget(categoryID: groceries.id, amount: Cents(150_000), currency: .inr)
    #expect(updated.currency == .inr)
    #expect(updated.amount == Cents(150_000))
    #expect(try ledger.budgets() == [updated])

    _ = try ledger.setBudget(categoryID: dining.id, amount: Cents(20_000), currency: .eur)
    #expect(try ledger.budgets().count == 2)

    try ledger.removeBudget(categoryID: groceries.id)
    #expect(try ledger.budgets().map(\.category) == [dining])

    #expect(throws: LedgerError.self) {
        try ledger.setBudget(categoryID: groceries.id, amount: Cents(0), currency: .eur)
    }
    #expect(throws: LedgerError.self) {
        try ledger.setBudget(categoryID: savings.id, amount: Cents(10_000), currency: .eur)
    }
}

@Test func monthSummaryComputesPerBudgetGaugesInBudgetCurrencyAndResetsEachMonth() throws {
    let ledger = try Ledger.openInMemory()
    let india = try #require(try ledger.accounts().first { $0.name == "India" })
    try ledger.setAccountCurrency(id: india.id, to: .inr)

    let supermarket = try namedCategory(ledger, "Supermarket")
    let restaurant = try namedCategory(ledger, "Restaurant")
    let shopping = try namedCategory(ledger, "Shopping")
    let transport = try namedCategory(ledger, "Taxi")

    // Budgets: Supermarket €400 (normal), Restaurant €100 (amber at 80%), Shopping ₹1000 (red at 100%).
    // Taxi has no budget and must not appear in gauges.
    try ledger.setBudget(categoryID: supermarket.id, amount: Cents(40_000), currency: .eur)
    try ledger.setBudget(categoryID: restaurant.id, amount: Cents(10_000), currency: .eur)
    try ledger.setBudget(categoryID: shopping.id, amount: Cents(100_000), currency: .inr)

    let nov10 = try #require(ReportingDate(iso8601: "2026-11-10"))

    // Previous month spending must not roll over or count in November.
    _ = try recordEntry(ledger, cents: 30_000, kind: .expense, payee: "Lidl", date: "2026-10-31", category: "Supermarket")
    // Current month EUR spending for Supermarket: €200 (50% -> normal).
    _ = try recordEntry(ledger, cents: 20_000, kind: .expense, payee: "Lidl", date: "2026-11-05", category: "Supermarket")
    // INR spending for Supermarket must NOT count toward its EUR budget.
    _ = try ledger.record(EntryDraft(
        amount: Cents(50_000),
        kind: .expense,
        payee: "BigBasket",
        reportingDate: nov10,
        categoryID: supermarket.id,
        accountID: india.id
    ))
    // Refund (income) and trashed entry must not reduce or add to spending.
    _ = try recordEntry(ledger, cents: 5_000, kind: .income, payee: "Lidl", date: "2026-11-06", category: "Supermarket")
    let trashed = try recordEntry(ledger, cents: 15_000, kind: .expense, payee: "Mistake", date: "2026-11-07", category: "Supermarket")
    try ledger.trash(trashed.id, on: nov10)

    // Restaurant: €80 of €100 -> 0.8 -> amber (.warning).
    _ = try recordEntry(ledger, cents: 8_000, kind: .expense, payee: "Bistro", date: "2026-11-08", category: "Restaurant")

    // Shopping: ₹1200 of ₹1000 -> 1.2 -> red (.exceeded); EUR spending for Shopping is ignored.
    _ = try recordEntry(ledger, cents: 2_000, kind: .expense, payee: "Zara", date: "2026-11-09", category: "Shopping")
    _ = try ledger.record(EntryDraft(
        amount: Cents(120_000),
        kind: .expense,
        payee: "Myntra",
        reportingDate: nov10,
        categoryID: shopping.id,
        accountID: india.id
    ))

    // Unbudgeted category spending must not create a gauge.
    _ = try recordEntry(ledger, cents: 2_500, kind: .expense, payee: "Uber", date: "2026-11-09", category: "Taxi")

    let summary = try ledger.monthSummary(on: nov10)
    #expect(summary.budgetGauges.count == 3)
    #expect(!summary.budgetGauges.contains { $0.category == transport })

    let byCategory = Dictionary(uniqueKeysWithValues: summary.budgetGauges.map { ($0.category.id, $0) })
    let supermarketGauge = try #require(byCategory[supermarket.id])
    #expect(supermarketGauge.currency == .eur)
    #expect(supermarketGauge.budget == Cents(40_000))
    #expect(supermarketGauge.spent == Cents(20_000))
    #expect(supermarketGauge.fraction == 0.5)
    #expect(supermarketGauge.status == .normal)

    let restaurantGauge = try #require(byCategory[restaurant.id])
    #expect(restaurantGauge.currency == .eur)
    #expect(restaurantGauge.spent == Cents(8_000))
    #expect(restaurantGauge.fraction == 0.8)
    #expect(restaurantGauge.status == .warning)

    let shoppingGauge = try #require(byCategory[shopping.id])
    #expect(shoppingGauge.currency == .inr)
    #expect(shoppingGauge.spent == Cents(120_000))
    #expect(shoppingGauge.fraction == 1.2)
    #expect(shoppingGauge.status == .exceeded)

    // Next month starts fresh at 0.
    let dec1 = try #require(ReportingDate(iso8601: "2026-12-01"))
    let december = try ledger.monthSummary(on: dec1)
    #expect(december.budgetGauges.allSatisfy { $0.spent == Cents(0) && $0.fraction == 0.0 && $0.status == .normal })
}

@Test func budgetSurvivesReopeningAFileBackedLedger() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("centtrail-budget-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: url) }

    let saved = try {
        let ledger = try Ledger.open(at: url, sync: .disabled)
        return try ledger.setBudget(categoryID: try namedCategory(ledger, "Supermarket").id, amount: Cents(40_000), currency: .eur)
    }()

    let reopened = try Ledger.open(at: url, sync: .disabled)
    #expect(try reopened.budgets() == [saved])
}

@Test func budgetSurvivesReopeningASyncedLedger() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("centtrail-budget-synced-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("ledger.sqlite")
    let sync = Ledger.SyncMode.enabled(containerIdentifier: "iCloud.com.tejaskale.centtrail")

    let saved = try {
        let ledger = try Ledger.open(at: url, sync: sync)
        let saved = try ledger.setBudget(categoryID: try namedCategory(ledger, "Supermarket").id, amount: Cents(40_000), currency: .eur)
        #expect(try ledger.budgets() == [saved])
        return saved
    }()

    let reopened = try Ledger.open(at: url, sync: sync)
    #expect(try reopened.budgets() == [saved])
}
