import Foundation

public struct LedgerError: Error, Equatable {
    public let message: String
}

public struct Category: Hashable, Sendable, Identifiable {
    public let id: ID
    public let name: String

    public struct ID: Hashable, Sendable {
        public let rawValue: UUID

        public init(rawValue: UUID) {
            self.rawValue = rawValue
        }
    }

    public init(id: ID, name: String) {
        self.id = id
        self.name = name
    }
}

public final class Ledger {
    private let connection: SQLiteConnection

    public static func openInMemory() throws -> Ledger {
        try Ledger(path: ":memory:")
    }

    init(path: String) throws {
        connection = try SQLiteConnection(path: path)
        try connection.execute("PRAGMA foreign_keys = ON")
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS category (
                id TEXT PRIMARY KEY NOT NULL,
                name TEXT NOT NULL UNIQUE
            )
            """
        )
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS counterparty (
                id TEXT PRIMARY KEY NOT NULL,
                name TEXT NOT NULL
            )
            """
        )
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS entry (
                id TEXT PRIMARY KEY NOT NULL,
                amount_cents INTEGER NOT NULL,
                kind TEXT NOT NULL,
                counterparty_id TEXT NOT NULL REFERENCES counterparty(id),
                reporting_date TEXT NOT NULL,
                category_id TEXT NOT NULL REFERENCES category(id)
            )
            """
        )
        try seedCategories()
    }

    public func record(_ draft: EntryDraft) throws -> Transaction {
        guard let amount = draft.amount else {
            throw RecordEntryError.incomplete([.amount])
        }
        guard let kind = draft.kind else {
            throw RecordEntryError.incomplete([.kind])
        }
        guard let counterpartyName = draft.counterparty else {
            throw RecordEntryError.incomplete([.counterparty])
        }
        guard let reportingDate = draft.reportingDate,
              let categoryID = draft.categoryID
        else {
            throw LedgerError(message: "The entry is incomplete.")
        }

        let category = try category(id: categoryID)
        let counterpartyID = UUID()
        let entryID = UUID()
        try connection.execute("BEGIN")
        do {
            try connection.execute(
                "INSERT INTO counterparty (id, name) VALUES (?, ?)",
                bindings: [.text(stored(counterpartyID)), .text(counterpartyName)]
            )
            try connection.execute(
                """
                INSERT INTO entry (
                    id, amount_cents, kind, counterparty_id, reporting_date, category_id
                ) VALUES (?, ?, ?, ?, ?, ?)
                """,
                bindings: [
                    .text(stored(entryID)),
                    .integer(Int64(amount.value)),
                    .text(kind.rawValue),
                    .text(stored(counterpartyID)),
                    .text(reportingDate.iso8601),
                    .text(stored(category.id.rawValue)),
                ]
            )
            try connection.execute("COMMIT")
        } catch {
            try? connection.execute("ROLLBACK")
            throw error
        }

        return Transaction(
            id: Transaction.ID(rawValue: entryID),
            amount: amount,
            kind: kind,
            counterparty: Counterparty(id: Counterparty.ID(rawValue: counterpartyID), name: counterpartyName),
            reportingDate: reportingDate,
            category: category
        )
    }

    public func transactions() throws -> [Transaction] {
        let rows = try connection.query(
            """
            SELECT
                entry.id,
                entry.amount_cents,
                entry.kind,
                entry.reporting_date,
                counterparty.id,
                counterparty.name,
                category.id,
                category.name
            FROM entry
            JOIN counterparty ON counterparty.id = entry.counterparty_id
            JOIN category ON category.id = entry.category_id
            ORDER BY entry.reporting_date, entry.rowid
            """
        )
        return try rows.map { row in
            guard row.count == 8,
                  let entryID = row[0].text.flatMap(UUID.init(uuidString:)),
                  let cents = row[1].integer,
                  let kind = row[2].text.flatMap(Kind.init(rawValue:)),
                  let reportingDate = row[3].text.flatMap(ReportingDate.init(iso8601:)),
                  let counterpartyID = row[4].text.flatMap(UUID.init(uuidString:)),
                  let counterpartyName = row[5].text,
                  let categoryID = row[6].text.flatMap(UUID.init(uuidString:)),
                  let categoryName = row[7].text
            else {
                throw LedgerError(message: "The ledger returned an entry it could not read.")
            }
            return Transaction(
                id: Transaction.ID(rawValue: entryID),
                amount: Cents(Int(cents)),
                kind: kind,
                counterparty: Counterparty(id: Counterparty.ID(rawValue: counterpartyID), name: counterpartyName),
                reportingDate: reportingDate,
                category: Category(id: Category.ID(rawValue: categoryID), name: categoryName)
            )
        }
    }

    private func category(id: Category.ID) throws -> Category {
        let rows = try connection.query(
            "SELECT name FROM category WHERE id = ?",
            bindings: [.text(stored(id.rawValue))]
        )
        guard let name = rows.first?.first?.text else {
            throw LedgerError(message: "Unknown category.")
        }
        return Category(id: id, name: name)
    }

    private func stored(_ id: UUID) -> String {
        id.uuidString.lowercased()
    }

    public func categories() throws -> [Category] {
        let rows = try connection.query("SELECT id, name FROM category ORDER BY rowid")
        return try rows.map { row in
            guard row.count == 2, let idText = row[0].text, let name = row[1].text, let id = UUID(uuidString: idText) else {
                throw LedgerError(message: "The ledger returned a category it could not read.")
            }
            return Category(id: Category.ID(rawValue: id), name: name)
        }
    }

    private func seedCategories() throws {
        for sourceName in OwnerCategories.sourceNames {
            let name = sourceName.trimmingCharacters(in: .whitespacesAndNewlines)
            try connection.execute(
                "INSERT INTO category (id, name) VALUES (?, ?) ON CONFLICT(name) DO NOTHING",
                bindings: [.text(UUID().uuidString.lowercased()), .text(name)]
            )
        }
    }
}
