import Foundation
import SQLite3

/// SQLite values retain their type; blobs are represented as base64 in JSON.
public enum AnalysisValue: Equatable, Sendable, Encodable {
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)
    case null

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .integer(let value): try container.encode(value)
        case .real(let value): try container.encode(value)
        case .text(let value): try container.encode(value)
        case .blob(let value): try container.encode(value.base64EncodedString())
        case .null: try container.encodeNil()
        }
    }
}

public struct AnalysisResult: Equatable, Sendable, Encodable {
    public let columns: [String]
    public let rows: [[AnalysisValue]]
    public let truncated: Bool
}

extension Ledger {
    /// Describes live tables/views together with the ledger's financial rules.
    public func describeSchema() throws -> String {
        var lines = ["""
            Centtrail is a local SQLite ledger. Entry reporting_date is the owner's YYYY-MM-DD date.
            Accounts determine currency (EUR or INR); never combine currencies or convert amounts.
            amount_cents and other integer monetary columns are exact minor units (cents or paise).
            Decimal amount columns divide minor units by 100.0. Blob results are base64 strings.
            Spending means expenses in spending categories, excluding transfers and trashed entries.
            A refund is income and does not reduce spending. Use the spending view for these rules.
            effective_account and effective_category apply renamed/removed reference customizations.
            counterparty means payee; counterparty_alias resolves alternate names to the same payee.
            entry.category_provenance distinguishes inherited defaults from explicit overrides.
            import_row tracks import identities. reference_customization stores names/removal state.
            Queries accept one read-only statement; writes, schema and connection changes are refused.
            Limits: 1–500 rows (default 100), 1 MiB response/value size, 100 columns and 2 seconds.
            Columns below are read from this ledger; internal sync tables are omitted.
            """]
        let objects = try query(sql: "SELECT name, type FROM sqlite_schema WHERE type IN ('table','view') AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'grdb_%' ORDER BY type, name", limit: 500)
        for row in objects.rows {
            guard case .text(let name) = row[0], case .text(let type) = row[1] else { continue }
            let escaped = name.replacingOccurrences(of: "'", with: "''")
            let columns = try query(sql: "SELECT name, type FROM pragma_table_info('\(escaped)')", limit: 100)
            let labels = columns.rows.compactMap { column -> String? in
                guard case .text(let name) = column[0], case .text(let type) = column[1] else { return nil }
                return type.isEmpty ? name : "\(name) (\(type))"
            }
            lines.append("\(type) \(name): \(labels.joined(separator: ", "))")
        }
        return lines.joined(separator: "\n")
    }

    /// Runs one read-only statement. Every query opens a fresh snapshot of the
    /// live file, so subsequent queries see newly committed WAL transactions.
    public func query(sql: String, limit: Int = 100) throws -> AnalysisResult {
        guard let path = connection.path else {
            throw LedgerError(message: "Analysis requires an on-disk ledger.")
        }
        return try AnalysisDatabase(path: path).query(sql: sql, limit: limit)
    }
}

private final class AnalysisDatabase {
    private var handle: OpaquePointer?

    init(path: String) throws {
        let status = sqlite3_open_v2(path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
        guard status == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Cannot open ledger."
            sqlite3_close(handle)
            handle = nil
            throw LedgerError(message: "Cannot open ledger read-only: \(message)")
        }
        guard sqlite3_exec(handle, "PRAGMA query_only = ON", nil, nil, nil) == SQLITE_OK else {
            let failure = error()
            sqlite3_close(handle)
            handle = nil
            throw failure
        }
        sqlite3_busy_timeout(handle, 2_000)
        sqlite3_limit(handle, SQLITE_LIMIT_LENGTH, 1_048_576)
        sqlite3_limit(handle, SQLITE_LIMIT_SQL_LENGTH, 100_000)
        sqlite3_limit(handle, SQLITE_LIMIT_COLUMN, 100)
        // Deny connection changes too: stmt_readonly alone permits ATTACH and
        // transaction control, and some pragmas act at prepare time.
        sqlite3_set_authorizer(handle, { _, action, first, second, _, _ in
            switch action {
            case SQLITE_SELECT, SQLITE_READ, SQLITE_RECURSIVE: return SQLITE_OK
            case SQLITE_FUNCTION:
                return second.map { String(cString: $0).lowercased() } == "load_extension" ? SQLITE_DENY : SQLITE_OK
            case SQLITE_PRAGMA:
                let name = first.map { String(cString: $0).lowercased() } ?? ""
                let metadata = ["table_info", "table_xinfo", "index_list", "index_info", "foreign_key_list"]
                return metadata.contains(name) || (name == "query_only" && second == nil) ? SQLITE_OK : SQLITE_DENY
            default: return SQLITE_DENY
            }
        }, nil)
    }

    deinit { sqlite3_close(handle) }

    func query(sql: String, limit: Int) throws -> AnalysisResult {
        guard (1...500).contains(limit) else { throw LedgerError(message: "Choose a row limit from 1 to 500.") }
        guard !sql.contains("\0"), sql.utf8.count <= 100_000 else {
            throw LedgerError(message: "SQL must contain no NUL characters and be at most 100,000 bytes.")
        }
        let deadline = UnsafeMutablePointer<Double>.allocate(capacity: 1)
        deadline.initialize(to: Date.timeIntervalSinceReferenceDate + 2)
        sqlite3_progress_handler(handle, 1_000, { context in
            guard let deadline = context?.assumingMemoryBound(to: Double.self) else { return 1 }
            return Date.timeIntervalSinceReferenceDate >= deadline.pointee ? 1 : 0
        }, deadline)
        defer {
            sqlite3_progress_handler(handle, 0, nil, nil)
            deadline.deinitialize(count: 1)
            deadline.deallocate()
        }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        try sql.withCString { start in
            var tail: UnsafePointer<CChar>?
            guard sqlite3_prepare_v2(handle, start, -1, &statement, &tail) == SQLITE_OK else { throw error() }
            guard statement != nil else { throw LedgerError(message: "Supply exactly one read-only SQL statement.") }
            while let remaining = tail, remaining.pointee != 0 {
                var extra: OpaquePointer?
                let status = sqlite3_prepare_v2(handle, remaining, -1, &extra, &tail)
                defer { sqlite3_finalize(extra) }
                guard status == SQLITE_OK, extra == nil else {
                    throw LedgerError(message: "Only one read-only SQL statement is allowed.")
                }
            }
        }
        guard sqlite3_stmt_readonly(statement) != 0, sqlite3_column_count(statement) > 0 else {
            throw LedgerError(message: "Only a read-only query returning columns is allowed.")
        }
        let count = sqlite3_column_count(statement)
        let columns = (0..<count).map { String(cString: sqlite3_column_name(statement, $0)) }
        var rows: [[AnalysisValue]] = []
        var responseBytes = try JSONEncoder().encode(columns).count
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return AnalysisResult(columns: columns, rows: rows, truncated: false) }
            guard status == SQLITE_ROW else { throw error() }
            if rows.count == limit { return AnalysisResult(columns: columns, rows: rows, truncated: true) }
            let row: [AnalysisValue] = (0..<count).map { column in
                switch sqlite3_column_type(statement, column) {
                case SQLITE_INTEGER: return .integer(sqlite3_column_int64(statement, column))
                case SQLITE_FLOAT: return .real(sqlite3_column_double(statement, column))
                case SQLITE_TEXT:
                    let length = Int(sqlite3_column_bytes(statement, column))
                    guard let bytes = sqlite3_column_text(statement, column) else { return .text("") }
                    return .text(String(decoding: UnsafeBufferPointer(start: bytes, count: length), as: UTF8.self))
                case SQLITE_BLOB:
                    let length = Int(sqlite3_column_bytes(statement, column))
                    guard let bytes = sqlite3_column_blob(statement, column), length > 0 else { return .blob(Data()) }
                    return .blob(Data(bytes: bytes, count: length))
                default: return .null
                }
            }
            let rowBytes = try JSONEncoder().encode(row).count
            guard rowBytes <= 1_048_576 else {
                throw LedgerError(message: "A result row exceeds the 1 MiB response limit.")
            }
            if responseBytes + rowBytes > 1_048_576 {
                return AnalysisResult(columns: columns, rows: rows, truncated: true)
            }
            responseBytes += rowBytes
            rows.append(row)
        }
    }

    private func error() -> LedgerError {
        LedgerError(message: "Only one read-only query is allowed: \(String(cString: sqlite3_errmsg(handle)))")
    }
}
