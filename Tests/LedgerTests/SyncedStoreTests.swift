import Foundation
import Ledger
import Testing

@Test func deterministicCategorySeedingProducesIdenticalIDsAcrossInstalls() throws {
    let first = try Ledger.openInMemory()
    let second = try Ledger.openInMemory()

    let firstCategories = try first.categories()
    let secondCategories = try second.categories()

    #expect(firstCategories.count == 26)
    #expect(firstCategories == secondCategories)
    #expect(Set(firstCategories.map(\.id)).count == 26)

    let savings = try #require(firstCategories.first { $0.name == "Savings" })
    #expect(savings.countsAsSpending == false)
}

@Test func reopeningFileBackedLedgerDoesNotDuplicateSeededCategories() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("centtrail-seed-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: url) }

    let initialCategories: [Category]
    do {
        let ledger = try Ledger.open(at: url, sync: .disabled)
        initialCategories = try ledger.categories()
        _ = try recordEntry(
            ledger,
            cents: 1500,
            kind: .expense,
            payee: "REWE",
            date: "2026-04-10",
            category: "Supermarket"
        )
    }

    let reopened = try Ledger.open(at: url, sync: .disabled)
    let reopenedCategories = try reopened.categories()
    #expect(reopenedCategories == initialCategories)
    #expect(try reopened.transactions().count == 1)
}

@Test func syncedStorePassesSyncEngineSchemaValidationAndSupportsAllOperations() throws {
    let ledger = try Ledger.openInMemory(sync: .enabled(containerIdentifier: "iCloud.com.tejaskale.centtrail"))
    let supermarket = try namedCategory(ledger, "Supermarket")
    let restaurant = try namedCategory(ledger, "Restaurant")

    let recorded = try recordEntry(
        ledger,
        cents: 2450,
        kind: .expense,
        payee: "REWE",
        date: "2026-05-03",
        category: "Supermarket"
    )
    #expect(recorded.category == supermarket)

    try ledger.setDefaultCategory(restaurant.id, for: recorded.payee.id)
    #expect(try ledger.transaction(id: recorded.id).category == restaurant)

    try ledger.confirmAlias("REWE CITY", of: recorded.payee.id)
    let aliased = try recordEntry(
        ledger,
        cents: 900,
        kind: .expense,
        payee: "REWE CITY",
        date: "2026-05-04",
        category: "Restaurant"
    )
    #expect(aliased.payee.id == recorded.payee.id)

    let today = try #require(ReportingDate(iso8601: "2026-05-10"))
    try ledger.trash(aliased.id, on: today)
    #expect(try ledger.transactions().map(\.id) == [recorded.id])
    #expect(try ledger.runReport(.currentMonthSpending, today: today) == .spendingTotal(SignedCents(2450)))
}

@Test func aliasUniquenessIsEnforcedInAppLogic() throws {
    let ledger = try Ledger.openInMemory()
    let rewe = try recordEntry(ledger, cents: 1000, kind: .expense, payee: "REWE", date: "2026-05-01", category: "Supermarket")
    let edeka = try recordEntry(ledger, cents: 1200, kind: .expense, payee: "Edeka", date: "2026-05-02", category: "Supermarket")

    try ledger.confirmAlias("REWE MARKT", of: rewe.payee.id)
    // Idempotent for the same payee
    try ledger.confirmAlias("REWE MARKT", of: rewe.payee.id)

    #expect(throws: LedgerError.self) {
        try ledger.confirmAlias("REWE MARKT", of: edeka.payee.id)
    }
}
