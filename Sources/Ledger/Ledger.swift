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
    public enum SyncMode: Equatable, Sendable {
        /// Local store only; nothing leaves the device.
        case disabled
        /// Syncs through the owner's iCloud account using the given CloudKit
        /// container. The signed app needs the matching iCloud entitlement.
        case enabled(containerIdentifier: String)
    }

    let connection: SQLiteConnection

    public static func openInMemory(sync: SyncMode = .disabled) throws -> Ledger {
        try Ledger(path: nil, syncMode: sync)
    }

    public static func open(at file: URL, sync: SyncMode = .disabled) throws -> Ledger {
        try Ledger(path: file.path(percentEncoded: false), syncMode: sync)
    }

    init(path: String?, syncMode: SyncMode) throws {
        connection = try SQLiteConnection(path: path, syncMode: syncMode)
        try seedCategories()
    }

    /// Calls `onChange` after every committed change to the ledger, whether made
    /// on this device or pulled in by iCloud sync. Keep the returned observation
    /// alive for as long as you want to hear about changes.
    public func observeChanges(_ onChange: @escaping @Sendable () -> Void) -> LedgerObservation {
        connection.observeChanges(onChange)
    }

    public func record(_ draft: EntryDraft) throws -> Transaction {
        try record(draft, proposeDefaultForNewPayee: false)
    }

    func record(_ draft: EntryDraft, proposeDefaultForNewPayee: Bool) throws -> Transaction {
        let payeeName = draft.payee?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var missing: Set<EntryField> = []
        if draft.amount == nil { missing.insert(.amount) }
        if draft.kind == nil { missing.insert(.kind) }
        if payeeName.isEmpty { missing.insert(.payee) }
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
        return try connection.inTransaction {
            let payeeID = try findOrCreatePayee(
                named: payeeName,
                defaultCategory: category.id,
                proposeInsteadOfApplying: proposeDefaultForNewPayee
            )
            let storedPayee = try requirePayee(id: payeeID)
            let proposedCategoryID = try proposedCategoryID(for: payeeID)
            let provenance = categoryProvenance(
                draft: draft,
                payee: storedPayee,
                category: category,
                proposedCategoryID: proposedCategoryID
            )
            try insertEntry(
                id: entryID,
                amount: amount,
                kind: kind,
                payeeID: payeeID,
                reportingDate: reportingDate,
                categoryID: category.id,
                provenance: provenance,
                note: draft.note
            )
            return try requireTransaction(id: entryID)
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

    func findOrCreatePayee(
        named name: String,
        defaultCategory: Category.ID,
        proposeInsteadOfApplying: Bool = false
    ) throws -> UUID {
        if let resolved = try resolvePayeeID(named: name) {
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

    func proposedCategoryID(for payeeID: UUID) throws -> Category.ID? {
        let rows = try connection.query(
            "SELECT category_id FROM proposed_payee_default WHERE counterparty_id = ?",
            bindings: [.text(stored(payeeID))]
        )
        guard let text = rows.first?.first?.text, let id = UUID(uuidString: text) else { return nil }
        return Category.ID(rawValue: id)
    }

    private func categoryProvenance(
        draft: EntryDraft,
        payee: Payee,
        category: Category,
        proposedCategoryID: Category.ID?
    ) -> CategoryProvenance {
        if draft.overridesCategory { return .overridden }
        if let defaultCategory = payee.defaultCategory {
            return defaultCategory.id == category.id ? .inherited : .overridden
        }
        if proposedCategoryID == category.id { return .inherited }
        return .overridden
    }

    func resolvePayeeID(named name: String) throws -> UUID? {
        let alias = try connection.query(
            "SELECT counterparty_id FROM counterparty_alias WHERE name = ? ORDER BY id LIMIT 1",
            bindings: [.text(name)]
        )
        if let idText = alias.first?.first?.text, let id = UUID(uuidString: idText) {
            return id
        }
        let existing = try connection.query(
            "SELECT id FROM counterparty WHERE name = ? ORDER BY id LIMIT 1",
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
        try connection.inTransaction {
            for sourceName in OwnerCategories.sourceNames {
                let name = sourceName.trimmingCharacters(in: .whitespacesAndNewlines)
                let id = OwnerCategories.deterministicID(for: name)
                let countsAsSpending: Int64 = name == "Savings" ? 0 : 1
                try connection.execute(
                    "INSERT OR IGNORE INTO category (id, name, counts_as_spending) VALUES (?, ?, ?)",
                    bindings: [.text(stored(id)), .text(name), .integer(countsAsSpending)]
                )
            }
        }
    }
}
