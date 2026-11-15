import Foundation
import GRDB
import Ledger
import Testing

@Test func firstSavedEntryTeachesAnExistingUnclassifiedPayee() throws {
    for kind in [Kind.expense, .income] {
        let file = try legacyPayeeLedger()
        let ledger = try Ledger.open(at: file)
        let first = try recordEntry(ledger, cents: 1250, kind: kind, payee: "Unclassified", date: "2026-11-02", category: "Supermarket")
        #expect(first.categoryProvenance == .inherited)
        #expect(try ledger.defaultCategory(forPayeeName: "Unclassified")?.name == "Supermarket")
        let override = try recordEntry(ledger, cents: 500, kind: kind, payee: "Unclassified", date: "2026-11-03", category: "Restaurant")
        #expect(override.categoryProvenance == .overridden)
        #expect(try ledger.defaultCategory(forPayeeName: "Unclassified")?.name == "Supermarket")
    }
}


@Test func openingAnOlderLedgerAppliesPendingDefaultsAndPreservesOverrides() throws {
    let file = try legacyPayeeLedger()
    let ledger = try Ledger.open(at: file)
    #expect(try ledger.defaultCategory(forPayeeName: "Pending")?.name == "Restaurant")
    #expect(try ledger.defaultCategory(forPayeeName: "PENDING ALIAS")?.name == "Restaurant")
    #expect(try ledger.proposedPayeeDefaults().isEmpty)
    let entries = try ledger.transactions().filter { $0.payee?.name == "Pending" }
    #expect(entries.first { $0.categoryProvenance == .inherited }?.category?.name == "Restaurant")
    #expect(entries.first { $0.categoryProvenance == .overridden }?.category?.name == "Shopping")
    let pending = try #require(try ledger.payees().first { $0.name == "Pending" })
    try ledger.setDefaultCategory(try namedCategory(ledger, "Hotel").id, for: pending.id)
    #expect(try ledger.transactions().first { $0.payee?.name == "Pending" && $0.categoryProvenance == .inherited }?.category?.name == "Hotel")
    #expect(try ledger.transactions().first { $0.payee?.name == "Pending" && $0.categoryProvenance == .overridden }?.category?.name == "Shopping")
    #expect(try Ledger.open(at: file).defaultCategory(forPayeeName: "Pending")?.name == "Hotel")
}

/// Construct the historical shape using public API data, then prepare the old
/// unclassified payee state directly. Assertions only use Ledger's public API.
private func legacyPayeeLedger() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("ledger.sqlite")
    do {
        let ledger = try Ledger.open(at: file)
        _ = try recordEntry(ledger, cents: 100, kind: .expense, payee: "Unclassified", date: "2026-11-01", category: "Supermarket")
        let pending = try recordEntry(ledger, cents: 200, kind: .expense, payee: "Pending", date: "2026-11-01", category: "Supermarket")
        try ledger.confirmAlias("PENDING ALIAS", of: pending.payee!.id)
        _ = try recordEntry(ledger, cents: 300, kind: .expense, payee: "Pending", date: "2026-11-02", category: "Shopping")
    }
    let database = try DatabaseQueue(path: file.path)
    try database.write { db in
        // Restore the pre-migration proposal table and marker. This is fixture
        // preparation only: no production assertions inspect SQL state.
        try db.execute(sql: "CREATE TABLE IF NOT EXISTS proposed_payee_default (counterparty_id TEXT PRIMARY KEY NOT NULL REFERENCES counterparty(id), category_id TEXT NOT NULL REFERENCES category(id))")
        try db.execute(sql: "UPDATE counterparty SET default_category_id = NULL WHERE name IN ('Unclassified', 'Pending')")
        try db.execute(sql: "INSERT INTO proposed_payee_default SELECT counterparty.id, category.id FROM counterparty, category WHERE counterparty.name = 'Pending' AND category.name = 'Restaurant'")
        try db.execute(sql: "DELETE FROM grdb_migrations WHERE identifier = 'v3_apply_payee_defaults'")
    }
    return file
}
