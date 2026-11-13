import Foundation

public struct LedgerError: Error, Equatable, LocalizedError {
    public let message: String

    public var errorDescription: String? { message }
}

public struct Category: Hashable, Sendable, Identifiable {
    public let id: ID
    public let name: String
    public let countsAsSpending: Bool

    public struct ID: Hashable, Sendable {
        public let rawValue: UUID

        public init(rawValue: UUID) {
            self.rawValue = rawValue
        }
    }

    public init(id: ID, name: String, countsAsSpending: Bool = true) {
        self.id = id
        self.name = name
        self.countsAsSpending = countsAsSpending
    }
}

public final class Ledger {
    let connection: SQLiteConnection

    public static func openInMemory() throws -> Ledger {
        try Ledger(path: ":memory:")
    }

    public static func open(at file: URL) throws -> Ledger {
        try Ledger(path: file.path(percentEncoded: false))
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
        try migrate()
        try seedCategories()
    }

    func migrate() throws {
        try addColumn("category", "counts_as_spending INTEGER NOT NULL DEFAULT 1")
        try addColumn("counterparty", "default_category_id TEXT")
        try addColumn("entry", "category_provenance TEXT NOT NULL DEFAULT 'inherited'")
        try addColumn("entry", "note TEXT")
        try addColumn("entry", "original_entry_id TEXT")
        try addColumn("entry", "trashed_on TEXT")
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS counterparty_alias (
                id TEXT PRIMARY KEY NOT NULL,
                name TEXT NOT NULL UNIQUE,
                counterparty_id TEXT NOT NULL REFERENCES counterparty(id)
            )
            """
        )
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS import_row (
                id TEXT PRIMARY KEY NOT NULL,
                entry_id TEXT,
                source_timestamp TEXT NOT NULL,
                amount_cents INTEGER NOT NULL,
                payee TEXT NOT NULL,
                source_account TEXT NOT NULL
            )
            """
        )
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS proposed_payee_default (
                counterparty_id TEXT PRIMARY KEY NOT NULL REFERENCES counterparty(id),
                category_id TEXT NOT NULL REFERENCES category(id)
            )
            """
        )
        try connection.execute("UPDATE category SET counts_as_spending = 0 WHERE name = 'Savings'")
        try connection.execute(
            """
            UPDATE counterparty
            SET default_category_id = (
                SELECT category_id FROM entry
                WHERE entry.counterparty_id = counterparty.id
                ORDER BY rowid LIMIT 1
            )
            WHERE default_category_id IS NULL
              AND NOT EXISTS (
                SELECT 1 FROM proposed_payee_default AS proposal
                WHERE proposal.counterparty_id = counterparty.id
              )
            """
        )
    }

    private func addColumn(_ table: String, _ definition: String) throws {
        let column = definition.split(separator: " ").first.map(String.init) ?? definition
        let rows = try connection.query("PRAGMA table_info(\(table))")
        let names = rows.compactMap { $0.count > 1 ? $0[1].text : nil }
        if names.contains(column) { return }
        try connection.execute("ALTER TABLE \(table) ADD COLUMN \(definition)")
    }

    public func record(_ draft: EntryDraft) throws -> Transaction {
        try record(draft, proposeDefaultForNewPayee: false)
    }

    func record(_ draft: EntryDraft, proposeDefaultForNewPayee: Bool) throws -> Transaction {
        if draft.kind == .refund, draft.originalPurchaseID != nil {
            return try recordLinkedRefund(draft)
        }
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
        do {
            let counterpartyID = try findOrCreateCounterparty(
                named: counterpartyName,
                defaultCategory: category.id,
                proposeInsteadOfApplying: proposeDefaultForNewPayee
            )
            let storedCounterparty = try requireCounterparty(id: counterpartyID)
            let proposedCategoryID = try proposedCategoryID(for: counterpartyID)
            let provenance = categoryProvenance(
                draft: draft,
                counterparty: storedCounterparty,
                category: category,
                proposedCategoryID: proposedCategoryID
            )
            try insertEntry(
                id: entryID,
                amount: amount,
                kind: kind,
                counterpartyID: counterpartyID,
                reportingDate: reportingDate,
                categoryID: category.id,
                provenance: provenance,
                note: draft.note,
                originalPurchaseID: nil
            )
            try connection.execute("COMMIT")
            return try requireTransaction(id: entryID)
        } catch {
            try? connection.execute("ROLLBACK")
            throw error
        }
    }

    private func recordLinkedRefund(_ draft: EntryDraft) throws -> Transaction {
        guard let amount = draft.amount, let reportingDate = draft.reportingDate, let originalID = draft.originalPurchaseID else {
            throw RecordEntryError.linkedRefundNeedsPurchase
        }
        let original = try transaction(id: originalID)
        guard original.kind == .expense else { throw RecordEntryError.linkedRefundNeedsPurchase }
        let entryID = UUID()
        try connection.execute("BEGIN")
        do {
            try insertEntry(
                id: entryID,
                amount: amount,
                kind: .refund,
                counterpartyID: original.counterparty.id.rawValue,
                reportingDate: reportingDate,
                categoryID: original.category.id,
                provenance: .inherited,
                note: draft.note,
                originalPurchaseID: original.id.rawValue
            )
            try connection.execute("COMMIT")
            return try requireTransaction(id: entryID)
        } catch {
            try? connection.execute("ROLLBACK")
            throw error
        }
    }

    public func runReport(_ operation: ReportOperation, today: ReportingDate) throws -> ReportResult {
        try performReport(operation, today: today)
    }

    public func transactions() throws -> [Transaction] {
        let rows = try connection.query(
            """
            \(entrySelectSQL)
            WHERE entry.trashed_on IS NULL
            ORDER BY entry.reporting_date DESC, entry.rowid DESC
            """
        )
        return try rows.map(decodeTransaction)
    }

    public func linkedRefunds(for purchaseID: Transaction.ID) throws -> [Transaction] {
        let rows = try connection.query(
            """
            \(entrySelectSQL)
            WHERE entry.original_entry_id = ?
              AND entry.kind = 'refund'
              AND entry.trashed_on IS NULL
            ORDER BY entry.reporting_date DESC, entry.rowid DESC
            """,
            bindings: [.text(stored(purchaseID.rawValue))]
        )
        return try rows.map(decodeTransaction)
    }

    func monthBounds(containing today: ReportingDate) -> (start: String, end: String) {
        let start = String(format: "%04d-%02d-01", today.year, today.month)
        let end: String
        if today.month == 12 {
            end = String(format: "%04d-01-01", today.year + 1)
        } else {
            end = String(format: "%04d-%02d-01", today.year, today.month + 1)
        }
        return (start, end)
    }

    func findOrCreateCounterparty(
        named name: String,
        defaultCategory: Category.ID,
        proposeInsteadOfApplying: Bool = false
    ) throws -> UUID {
        if let resolved = try resolveCounterpartyID(named: name) {
            return resolved
        }
        let id = UUID()
        if proposeInsteadOfApplying {
            try connection.execute(
                "INSERT INTO counterparty (id, name, default_category_id) VALUES (?, ?, NULL)",
                bindings: [.text(stored(id)), .text(name)]
            )
            try connection.execute(
                "INSERT INTO proposed_payee_default (counterparty_id, category_id) VALUES (?, ?)",
                bindings: [.text(stored(id)), .text(stored(defaultCategory.rawValue))]
            )
        } else {
            try connection.execute(
                "INSERT INTO counterparty (id, name, default_category_id) VALUES (?, ?, ?)",
                bindings: [.text(stored(id)), .text(name), .text(stored(defaultCategory.rawValue))]
            )
        }
        return id
    }

    func proposedCategoryID(for counterpartyID: UUID) throws -> Category.ID? {
        let rows = try connection.query(
            "SELECT category_id FROM proposed_payee_default WHERE counterparty_id = ?",
            bindings: [.text(stored(counterpartyID))]
        )
        guard let text = rows.first?.first?.text, let id = UUID(uuidString: text) else { return nil }
        return Category.ID(rawValue: id)
    }

    private func categoryProvenance(
        draft: EntryDraft,
        counterparty: Counterparty,
        category: Category,
        proposedCategoryID: Category.ID?
    ) -> CategoryProvenance {
        if draft.overridesCategory { return .overridden }
        if let defaultCategory = counterparty.defaultCategory {
            return defaultCategory.id == category.id ? .inherited : .overridden
        }
        if proposedCategoryID == category.id { return .inherited }
        return .overridden
    }

    func resolveCounterpartyID(named name: String) throws -> UUID? {
        let alias = try connection.query(
            "SELECT counterparty_id FROM counterparty_alias WHERE name = ?",
            bindings: [.text(name)]
        )
        if let idText = alias.first?.first?.text, let id = UUID(uuidString: idText) {
            return id
        }
        let existing = try connection.query(
            "SELECT id FROM counterparty WHERE name = ?",
            bindings: [.text(name)]
        )
        if let idText = existing.first?.first?.text, let id = UUID(uuidString: idText) {
            return id
        }
        return nil
    }

    func category(id: Category.ID) throws -> Category {
        let rows = try connection.query(
            "SELECT name, counts_as_spending FROM category WHERE id = ?",
            bindings: [.text(stored(id.rawValue))]
        )
        guard let name = rows.first?.first?.text, let spending = rows.first?.dropFirst().first?.integer else {
            throw RecordEntryError.unknownCategory
        }
        return Category(id: id, name: name, countsAsSpending: spending != 0)
    }

    func stored(_ id: UUID) -> String {
        id.uuidString.lowercased()
    }

    public func categories() throws -> [Category] {
        let rows = try connection.query("SELECT id, name, counts_as_spending FROM category ORDER BY rowid")
        return try rows.map { row in
            guard row.count == 3,
                  let idText = row[0].text,
                  let name = row[1].text,
                  let id = UUID(uuidString: idText),
                  let spending = row[2].integer
            else {
                throw LedgerError(message: "The ledger returned a category it could not read.")
            }
            return Category(id: Category.ID(rawValue: id), name: name, countsAsSpending: spending != 0)
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
        try connection.execute("UPDATE category SET counts_as_spending = 0 WHERE name = 'Savings'")
    }
}
