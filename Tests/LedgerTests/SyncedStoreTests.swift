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

    let initialCategories = try {
        let ledger = try Ledger.open(at: url, sync: .disabled)
        _ = try recordEntry(
            ledger,
            cents: 1500,
            kind: .expense,
            payee: "REWE",
            date: "2026-04-10",
            category: "Supermarket"
        )
        return try ledger.categories()
    }()

    let reopened = try Ledger.open(at: url, sync: .disabled)
    let reopenedCategories = try reopened.categories()
    #expect(reopenedCategories == initialCategories)
    #expect(try reopened.transactions().count == 1)
}

@Test func syncedStorePassesSyncEngineSchemaValidationAndSupportsAllOperations() throws {
    let ledger = try openSyncedLedger()
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

@Test func observersHearAboutEveryLedgerChangeUntilTheyStop() throws {
    let ledger = try openSyncedLedger()
    let counter = ChangeCounter()
    var observation: LedgerObservation? = ledger.observeChanges { counter.increment() }

    let entry = try recordEntry(ledger, cents: 1200, kind: .expense, payee: "REWE", date: "2026-05-01", category: "Supermarket")
    #expect(counter.value == 1)

    try ledger.trash(entry.id, on: try #require(ReportingDate(iso8601: "2026-05-02")))
    #expect(counter.value == 2)

    _ = try ledger.transactions()
    #expect(counter.value == 2)

    observation?.cancel()
    observation = nil
    _ = try recordEntry(ledger, cents: 300, kind: .expense, payee: "Bakery", date: "2026-05-03", category: "Supermarket")
    #expect(counter.value == 2)
}

@Test func syncedStoreSupportsPayeeMergeCategoryEditsAndTrashPurge() throws {
    let ledger = try openSyncedLedger()
    let rewe = try recordEntry(ledger, cents: 1000, kind: .expense, payee: "REWE", date: "2026-05-01", category: "Supermarket")
    let reweCity = try recordEntry(ledger, cents: 500, kind: .expense, payee: "REWE City", date: "2026-05-02", category: "Supermarket")

    try ledger.mergePayees(sourceID: reweCity.payee.id, into: rewe.payee.id)
    #expect(try ledger.transactions().allSatisfy { $0.payee.id == rewe.payee.id })
    #expect(try recordEntry(ledger, cents: 200, kind: .expense, payee: "REWE City", date: "2026-05-03", category: "Supermarket").payee.id == rewe.payee.id)

    let pets = try ledger.addCategory(name: "Pets")
    let renamed = try ledger.renameCategory(id: pets.id, to: "Pet care")
    #expect(try ledger.categories().contains(renamed))
    try ledger.removeCategory(id: pets.id)
    #expect(try !ledger.categories().contains { $0.id == pets.id })

    try ledger.trash(rewe.id, on: try #require(ReportingDate(iso8601: "2026-05-04")))
    #expect(try ledger.trashedEntries(today: try #require(ReportingDate(iso8601: "2026-05-10"))).count == 1)
    #expect(try ledger.trashedEntries(today: try #require(ReportingDate(iso8601: "2026-06-10"))).isEmpty)
    #expect(try ledger.transactions().count == 2)
}

private final class ChangeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}

/// A file-backed ledger with the sync engine attached (SQLiteData swaps in its
/// test CloudKit stand-in). In-memory ledgers would share one in-memory sync
/// metadatabase and lock each other when tests run in parallel.
private func openSyncedLedger() throws -> Ledger {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("centtrail-synced-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return try Ledger.open(
        at: directory.appendingPathComponent("ledger.sqlite"),
        sync: .enabled(containerIdentifier: "iCloud.com.tejaskale.centtrail")
    )
}
