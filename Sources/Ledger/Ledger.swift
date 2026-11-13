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
                name TEXT NOT NULL UNIQUE
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
        let counterpartyName = draft.counterparty?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var missing: Set<EntryField> = []
        if draft.amount == nil { missing.insert(.amount) }
        if draft.kind == nil { missing.insert(.kind) }
        if counterpartyName.isEmpty { missing.insert(.counterparty) }
        if draft.reportingDate == nil { missing.insert(.reportingDate) }
        if draft.categoryID == nil { missing.insert(.category) }
        guard missing.isEmpty,
              let amount = draft.amount,
              let kind = draft.kind,
              let reportingDate = draft.reportingDate,
              let categoryID = draft.categoryID
        else {
            throw RecordEntryError.incomplete(missing)
        }

        let category = try category(id: categoryID)
        let entryID = UUID()
        try connection.execute("BEGIN")
        let counterpartyID: UUID
        do {
            counterpartyID = try findOrCreateCounterparty(named: counterpartyName)
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

    public func runReport(_ operation: ReportOperation, today: ReportingDate) throws -> ReportResult {
        switch operation {
        case .currentMonthSpending:
            let bounds = monthBounds(containing: today)
            let rows = try connection.query(
                """
                SELECT COALESCE(SUM(amount_cents), 0)
                FROM entry
                WHERE kind = ?
                  AND reporting_date >= ?
                  AND reporting_date < ?
                """,
                bindings: [
                    .text(Kind.expense.rawValue),
                    .text(bounds.start),
                    .text(bounds.end),
                ]
            )
            let total = rows.first?.first?.integer ?? 0
            return .spendingTotal(Cents(Int(total)))
        }
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

    private func monthBounds(containing today: ReportingDate) -> (start: String, end: String) {
        let start = String(format: "%04d-%02d-01", today.year, today.month)
        let end: String
        if today.month == 12 {
            end = String(format: "%04d-01-01", today.year + 1)
        } else {
            end = String(format: "%04d-%02d-01", today.year, today.month + 1)
        }
        return (start, end)
    }

    private func findOrCreateCounterparty(named name: String) throws -> UUID {
        let existing = try connection.query(
            "SELECT id FROM counterparty WHERE name = ?",
            bindings: [.text(name)]
        )
        if let idText = existing.first?.first?.text, let id = UUID(uuidString: idText) {
            return id
        }
        let id = UUID()
        try connection.execute(
            "INSERT INTO counterparty (id, name) VALUES (?, ?)",
            bindings: [.text(stored(id)), .text(name)]
        )
        return id
    }

    private func category(id: Category.ID) throws -> Category {
        let rows = try connection.query(
            "SELECT name FROM category WHERE id = ?",
            bindings: [.text(stored(id.rawValue))]
        )
        guard let name = rows.first?.first?.text else {
            throw RecordEntryError.unknownCategory
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
