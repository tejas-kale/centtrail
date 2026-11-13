import SQLite3

final class SQLiteConnection {
    private var handle: OpaquePointer?
    private let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(path: String) throws {
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let status = sqlite3_open_v2(path, &database, flags, nil)
        guard status == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open the ledger database."
            if let database {
                sqlite3_close(database)
            }
            throw LedgerError(message: message)
        }
        handle = database
    }

    deinit {
        if let handle {
            sqlite3_close(handle)
        }
    }

    func execute(_ sql: String, bindings: [SQLiteValue] = []) throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        try step(statement, expecting: SQLITE_DONE)
    }

    func query(_ sql: String, bindings: [SQLiteValue] = []) throws -> [[SQLiteValue]] {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)

        var rows: [[SQLiteValue]] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_ROW {
                rows.append(readRow(statement))
            } else if status == SQLITE_DONE {
                return rows
            } else {
                throw error(from: status)
            }
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let status = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard status == SQLITE_OK, let statement else {
            throw error(from: status)
        }
        return statement
    }

    private func bind(_ values: [SQLiteValue], to statement: OpaquePointer) throws {
        for (offset, value) in values.enumerated() {
            let position = Int32(offset + 1)
            let status: Int32
            switch value {
            case .null:
                status = sqlite3_bind_null(statement, position)
            case .integer(let number):
                status = sqlite3_bind_int64(statement, position, number)
            case .text(let text):
                status = text.withCString { pointer in
                    sqlite3_bind_text(statement, position, pointer, -1, transientDestructor)
                }
            }
            guard status == SQLITE_OK else {
                throw error(from: status)
            }
        }
    }

    private func step(_ statement: OpaquePointer, expecting expected: Int32) throws {
        let status = sqlite3_step(statement)
        guard status == expected else {
            throw error(from: status)
        }
    }

    private func readRow(_ statement: OpaquePointer) -> [SQLiteValue] {
        (0..<sqlite3_column_count(statement)).map { column in
            switch sqlite3_column_type(statement, column) {
            case SQLITE_NULL:
                return .null
            case SQLITE_INTEGER:
                return .integer(sqlite3_column_int64(statement, column))
            case SQLITE_TEXT:
                guard let pointer = sqlite3_column_text(statement, column) else {
                    return .text("")
                }
                return .text(String(cString: pointer))
            default:
                return .null
            }
        }
    }

    private func error(from status: Int32) -> LedgerError {
        let detail = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite error \(status)"
        return LedgerError(message: detail)
    }
}

enum SQLiteValue: Equatable {
    case text(String)
    case integer(Int64)
    case null

    var text: String? {
        if case .text(let value) = self { return value }
        return nil
    }

    var integer: Int64? {
        if case .integer(let value) = self { return value }
        return nil
    }
}
