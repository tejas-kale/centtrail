import Foundation
@testable import Ledger
import Testing

/// Newest sync-metadata modification time per record type. SQLiteData bumps it
/// whenever it queues a row for upload.
private func lastQueued(_ ledger: Ledger, _ recordType: String) throws -> Int64 {
    // The metadatabase is attached to the writer connection only.
    let rows = try ledger.connection.inTransaction { try ledger.connection.query(
        "SELECT MIN(userModificationTime) FROM sqlitedata_icloud.sqlitedata_icloud_metadata WHERE recordType = ?",
        bindings: [.text(recordType)]
    ) }
    return try #require(rows.first?.first?.integer)
}

private func syncedLedgerFile() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("centtrail-repair-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("ledger.sqlite")
}

private let sync = Ledger.SyncMode.enabled(containerIdentifier: "iCloud.com.tejaskale.centtrail")

@Test func openingASyncedLedgerRequeuesEverySyncedRowOnce() throws {
    let file = try syncedLedgerFile()
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

    // A ledger from before the repair: rows exist and were queued once.
    let before: [String: Int64] = try {
        let ledger = try Ledger(path: file.path(percentEncoded: false), syncMode: sync, runsSyncRepairs: false)
        _ = try recordEntry(ledger, cents: 1_200, kind: .expense, payee: "REWE", date: "2026-11-02", category: "Supermarket")
        try ledger.setBudget(categoryID: try namedCategory(ledger, "Restaurant").id, amount: Cents(10_000), currency: .eur)
        return try Dictionary(uniqueKeysWithValues: ["category", "account", "counterparty", "entry", "budget"].map {
            ($0, try lastQueued(ledger, $0))
        })
    }()

    let afterRepair: [String: Int64] = try {
        let repaired = try Ledger.open(at: file, sync: sync)
        var times: [String: Int64] = [:]
        for (recordType, time) in before {
            times[recordType] = try lastQueued(repaired, recordType)
            #expect(times[recordType]! > time, "\(recordType) rows were not queued again")
        }
        return times
    }()

    // The repair runs once per ledger file, not on every launch.
    let reopened = try Ledger.open(at: file, sync: sync)
    for (recordType, time) in afterRepair {
        #expect(try lastQueued(reopened, recordType) == time, "\(recordType) rows were queued on every launch")
    }
    #expect(try reopened.budgets().count == 1)
    #expect(try reopened.transactions().count == 1)
}

@Test func ledgerCreatedWithSyncOffIsQueuedWhenSyncIsTurnedOn() throws {
    let file = try syncedLedgerFile()
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    // With sync off the repair is skipped and not recorded as done.
    _ = try Ledger.open(at: file, sync: .disabled)

    let repaired = try Ledger.open(at: file, sync: sync)
    let tracked = try repaired.connection.inTransaction {
        try repaired.connection.query(
            "SELECT COUNT(*) FROM sqlitedata_icloud.sqlitedata_icloud_metadata WHERE recordType = 'category'"
        )
    }
    let categories = try repaired.connection.query("SELECT COUNT(*) FROM category")
    #expect(tracked.first?.first?.integer == categories.first?.first?.integer)
    #expect((categories.first?.first?.integer ?? 0) > 0)
}
