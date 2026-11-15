import Foundation
import Ledger
import Testing

@Test func readOnlyAnalysisReturnsExactValuesAndSeesNewWriterCommits() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("ledger.sqlite")
    let writer = try Ledger.open(at: file)
    _ = try recordEntry(writer, cents: 1250, kind: .expense, payee: "Lidl", date: "2026-11-15", category: "Supermarket")
    let reader = try Ledger.openReadOnly(at: file)
    let first = try reader.query(sql: "SELECT amount_cents, amount, payee, NULL AS absent FROM spending")
    #expect(first.columns == ["amount_cents", "amount", "payee", "absent"])
    #expect(first.rows == [[.integer(1250), .real(12.5), .text("Lidl"), .null]])
    #expect(!first.truncated)
    _ = try recordEntry(writer, cents: 200, kind: .expense, payee: "Cafe", date: "2026-11-15", category: "Supermarket")
    #expect(try reader.query(sql: "SELECT COUNT(*) AS count FROM spending").rows == [[.integer(2)]])
}

@Test func analysisCapsRowsAndOversizedValuesAndPreservesEmptyColumns() throws {
    try withAnalysisLedger { writer, reader in
        let small = try reader.query(sql: "SELECT 1 AS n UNION ALL SELECT 2 UNION ALL SELECT 3", limit: 2)
        #expect(small.rows == [[.integer(1)], [.integer(2)]])
        #expect(small.truncated)
        #expect(try !reader.query(sql: "SELECT 1 UNION ALL SELECT 2", limit: 2).truncated)
        let empty = try reader.query(sql: "SELECT name AS payee FROM counterparty WHERE 0")
        #expect(empty.columns == ["payee"])
        #expect(empty.rows.isEmpty)
        #expect(!empty.truncated)
        #expect(throws: LedgerError.self) { _ = try reader.query(sql: "SELECT hex(zeroblob(600000))") }
        #expect(throws: LedgerError.self) { try reader.query(sql: "SELECT 1", limit: 501) }
        #expect(throws: LedgerError.self) { try reader.query(sql: "SELECT 1", limit: 0) }
        _ = writer
    }
}

private func withAnalysisLedger(_ body: (Ledger, Ledger) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("ledger.sqlite")
    let writer = try Ledger.open(at: file)
    try body(writer, Ledger.openReadOnly(at: file))
}

@Test func analysisDescribesSchemaAndAppliesSpendingRules() throws {
    try withAnalysisLedger { writer, reader in
        _ = try recordEntry(writer, cents: 1250, kind: .expense, payee: "Lidl", date: "2026-11-15", category: "Supermarket")
        _ = try recordEntry(writer, cents: 200, kind: .income, payee: "Refund", date: "2026-11-15", category: "Supermarket")
        _ = try recordEntry(writer, cents: 300, kind: .expense, payee: "Savings", date: "2026-11-15", category: "Savings")
        _ = try recordEntry(writer, cents: 400, kind: .transfer, payee: "", date: "2026-11-15", category: "Supermarket")
        let trashed = try recordEntry(writer, cents: 500, kind: .expense, payee: "Deleted", date: "2026-11-15", category: "Supermarket")
        try writer.trash(trashed.id, on: #require(ReportingDate(iso8601: "2026-11-15")))
        #expect(try reader.query(sql: "SELECT SUM(amount_cents) FROM spending").rows == [[.integer(1250)]])
        let schema = try reader.describeSchema()
        for term in ["entry", "account", "spending", "amount_cents", "minor units", "decimal", "refund", "currency"] {
            #expect(schema.lowercased().contains(term))
        }
    }
}

@Test func analysisRefusesWritesConnectionChangesAndMultipleStatements() throws {
    try withAnalysisLedger { writer, reader in
        let attempts = [
            "DELETE FROM entry", "UPDATE account SET name = 'changed'", "CREATE TABLE broken (id)",
            "CREATE TEMP TABLE broken (id)", "DROP TABLE entry", "PRAGMA query_only = OFF",
            "EXPLAIN PRAGMA query_only = OFF", "ATTACH DATABASE ':memory:' AS other", "BEGIN",
            "SELECT 1; SELECT 2", "SELECT 1; DELETE FROM entry", "SELECT 1; invalid trailing text",
            "SELECT load_extension('missing')", "SELECT 1\0; DELETE FROM entry", "-- no statement"
        ]
        for sql in attempts {
            #expect(throws: LedgerError.self) { _ = try reader.query(sql: sql) }
        }
        #expect(throws: (any Error).self) { _ = try reader.addAccount(name: "Forbidden") }
        #expect(try writer.accounts().count == 4)
        let literal = try reader.query(sql: "/* prefix */ SELECT 'a;b' AS text, 'a'||char(0)||'b' AS nul, x'0102' AS bytes; -- trailing comment")
        #expect(literal.rows == [[.text("a;b"), .text("a\0b"), .blob(Data([1, 2]))]])
        #expect(try reader.query(sql: "WITH n AS (SELECT 2 AS x) SELECT x FROM n").rows == [[.integer(2)]])
        #expect(try reader.query(sql: "PRAGMA query_only").rows == [[.integer(1)]])
    }
}

@Test func readOnlyAnalysisNeverCreatesAMissingLedger() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID()).sqlite")
    #expect(throws: (any Error).self) { _ = try Ledger.openReadOnly(at: file) }
    #expect(!FileManager.default.fileExists(atPath: file.path))
}

@Test func spendingViewExposesEachEntriesAccountCurrencyCode() throws {
    try withAnalysisLedger { writer, reader in
        let india = try #require(try writer.accounts().first { $0.name == "India" })
        try writer.setAccountCurrency(id: india.id, to: .inr)
        _ = try recordEntry(writer, cents: 1250, kind: .expense, payee: "Lidl", date: "2026-11-15", category: "Supermarket")
        _ = try writer.record(EntryDraft(
            amount: Cents(45000),
            kind: .expense,
            payee: "BigBasket",
            reportingDate: ReportingDate(iso8601: "2026-11-15")!,
            categoryID: try namedCategory(writer, "Supermarket").id,
            accountID: india.id
        ))
        let rows = try reader.query(sql: "SELECT currency, amount_cents, amount FROM spending ORDER BY currency").rows
        #expect(rows == [
            [.text("EUR"), .integer(1250), .real(12.5)],
            [.text("INR"), .integer(45000), .real(450.0)],
        ])
    }
}
