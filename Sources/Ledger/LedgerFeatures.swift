import Foundation

let entrySelectSQL = """
SELECT
    entry.id,
    entry.amount_cents,
    entry.kind,
    entry.reporting_date,
    entry.category_provenance,
    entry.note,
    entry.original_entry_id,
    entry.trashed_on,
    counterparty.id,
    counterparty.name,
    default_category.id,
    default_category.name,
    default_category.counts_as_spending,
    entry_category.id,
    entry_category.name,
    entry_category.counts_as_spending
FROM entry
JOIN counterparty ON counterparty.id = entry.counterparty_id
JOIN category AS entry_category ON entry_category.id = entry.category_id
LEFT JOIN category AS default_category ON default_category.id = counterparty.default_category_id
"""

extension Ledger {
    func insertEntry(
        id: UUID,
        amount: Cents,
        kind: Kind,
        counterpartyID: UUID,
        reportingDate: ReportingDate,
        categoryID: Category.ID,
        provenance: CategoryProvenance,
        note: String?,
        originalPurchaseID: UUID?
    ) throws {
        try connection.execute(
            """
            INSERT INTO entry (
                id, amount_cents, kind, counterparty_id, reporting_date, category_id,
                category_provenance, note, original_entry_id
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(stored(id)),
                .integer(Int64(amount.value)),
                .text(kind.rawValue),
                .text(stored(counterpartyID)),
                .text(reportingDate.iso8601),
                .text(stored(categoryID.rawValue)),
                .text(provenance.rawValue),
                note.map(SQLiteValue.text) ?? .null,
                originalPurchaseID.map { .text(stored($0)) } ?? .null,
            ]
        )
    }

    func requireTransaction(id: UUID) throws -> Transaction {
        try transaction(id: Transaction.ID(rawValue: id))
    }

    public func transaction(id: Transaction.ID) throws -> Transaction {
        let rows = try connection.query(
            "\(entrySelectSQL) WHERE entry.id = ?",
            bindings: [.text(stored(id.rawValue))]
        )
        guard let row = rows.first else { throw RecordEntryError.unknownEntry }
        return try decodeTransaction(row)
    }

    func decodeTransaction(_ row: [SQLiteValue]) throws -> Transaction {
        guard row.count == 16,
              let entryID = row[0].text.flatMap(UUID.init(uuidString:)),
              let cents = row[1].integer,
              let kind = row[2].text.flatMap(Kind.init(rawValue:)),
              let reportingDate = row[3].text.flatMap(ReportingDate.init(iso8601:)),
              let provenance = row[4].text.flatMap(CategoryProvenance.init(rawValue:)),
              let counterpartyID = row[8].text.flatMap(UUID.init(uuidString:)),
              let counterpartyName = row[9].text,
              let categoryID = row[13].text.flatMap(UUID.init(uuidString:)),
              let categoryName = row[14].text,
              let categorySpending = row[15].integer
        else {
            throw LedgerError(message: "The ledger returned an entry it could not read.")
        }
        let note = row[5].text
        let original = row[6].text.flatMap(UUID.init(uuidString:)).map(Transaction.ID.init(rawValue:))
        return Transaction(
            id: Transaction.ID(rawValue: entryID),
            amount: Cents(Int(cents)),
            kind: kind,
            counterparty: Counterparty(
                id: Counterparty.ID(rawValue: counterpartyID),
                name: counterpartyName,
                defaultCategory: try category(idText: row[10].text, name: row[11].text, spending: row[12].integer)
            ),
            reportingDate: reportingDate,
            category: Category(
                id: Category.ID(rawValue: categoryID),
                name: categoryName,
                countsAsSpending: categorySpending != 0
            ),
            categoryProvenance: provenance,
            note: note,
            originalPurchaseID: original
        )
    }

    public func counterparties() throws -> [Counterparty] {
        let rows = try connection.query(
            """
            SELECT counterparty.id, counterparty.name, category.id, category.name, category.counts_as_spending
            FROM counterparty
            LEFT JOIN category ON category.id = counterparty.default_category_id
            ORDER BY counterparty.name
            """
        )
        return try rows.map { row in
            guard row.count == 5,
                  let id = row[0].text.flatMap(UUID.init(uuidString:)),
                  let name = row[1].text
            else {
                throw LedgerError(message: "The ledger returned a counterparty it could not read.")
            }
            return Counterparty(
                id: Counterparty.ID(rawValue: id),
                name: name,
                defaultCategory: try category(idText: row[2].text, name: row[3].text, spending: row[4].integer)
            )
        }
    }

    public func defaultCategory(forCounterpartyName name: String) throws -> Category? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let id = try resolveCounterpartyID(named: trimmed) else { return nil }
        return try requireCounterparty(id: id).defaultCategory
    }

    func requireCounterparty(id: UUID) throws -> Counterparty {
        guard let match = try counterparties().first(where: { $0.id.rawValue == id }) else {
            throw LedgerError(message: "That counterparty is not in the ledger.")
        }
        return match
    }

    func category(idText: String?, name: String?, spending: Int64?) throws -> Category? {
        if idText == nil, name == nil, spending == nil { return nil }
        guard let idText, let id = UUID(uuidString: idText), let name, let spending else {
            throw LedgerError(message: "The ledger returned a category it could not read.")
        }
        return Category(id: Category.ID(rawValue: id), name: name, countsAsSpending: spending != 0)
    }

    public func setDefaultCategory(_ categoryID: Category.ID, for counterpartyID: Counterparty.ID) throws {
        _ = try category(id: categoryID)
        try connection.execute("BEGIN")
        do {
            try connection.execute(
                "UPDATE counterparty SET default_category_id = ? WHERE id = ?",
                bindings: [.text(stored(categoryID.rawValue)), .text(stored(counterpartyID.rawValue))]
            )
            try connection.execute(
                """
                UPDATE entry
                SET category_id = ?
                WHERE counterparty_id = ?
                  AND category_provenance = 'inherited'
                  AND original_entry_id IS NULL
                  AND kind != 'refund'
                """,
                bindings: [.text(stored(categoryID.rawValue)), .text(stored(counterpartyID.rawValue))]
            )
            try connection.execute(
                "DELETE FROM proposed_payee_default WHERE counterparty_id = ?",
                bindings: [.text(stored(counterpartyID.rawValue))]
            )
            try refreshLinkedRefundCategories()
            try connection.execute("COMMIT")
        } catch {
            try? connection.execute("ROLLBACK")
            throw error
        }
    }

    public func setCategory(_ categoryID: Category.ID, for entryID: Transaction.ID) throws {
        _ = try category(id: categoryID)
        _ = try transaction(id: entryID)
        try connection.execute("BEGIN")
        do {
            try connection.execute(
                """
                UPDATE entry
                SET category_id = ?, category_provenance = 'overridden'
                WHERE id = ?
                """,
                bindings: [.text(stored(categoryID.rawValue)), .text(stored(entryID.rawValue))]
            )
            try refreshLinkedRefundCategories()
            try connection.execute("COMMIT")
        } catch {
            try? connection.execute("ROLLBACK")
            throw error
        }
    }

    public func confirmedAliases() throws -> [(name: String, counterpartyID: Counterparty.ID)] {
        let rows = try connection.query("SELECT name, counterparty_id FROM counterparty_alias ORDER BY name")
        return rows.compactMap { row in
            guard let name = row[0].text, let id = row[1].text.flatMap(UUID.init(uuidString:)) else { return nil }
            return (name, Counterparty.ID(rawValue: id))
        }
    }

    public func confirmAlias(_ name: String, of counterpartyID: Counterparty.ID) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw LedgerError(message: "An alias needs a name.")
        }
        let target = try requireCounterparty(id: counterpartyID.rawValue)
        if trimmed == target.name {
            throw LedgerError(message: "An alias has to be a different name from the counterparty.")
        }
        if let existingAlias = try connection.query(
            "SELECT counterparty_id FROM counterparty_alias WHERE name = ?",
            bindings: [.text(trimmed)]
        ).first?.first?.text, let owner = UUID(uuidString: existingAlias) {
            if owner == counterpartyID.rawValue { return }
            throw LedgerError(message: "That alias already belongs to another counterparty.")
        }
        try connection.execute("BEGIN")
        do {
            if let other = try resolveCounterpartyID(named: trimmed), other != counterpartyID.rawValue {
                try connection.execute(
                    "UPDATE entry SET counterparty_id = ? WHERE counterparty_id = ?",
                    bindings: [.text(stored(counterpartyID.rawValue)), .text(stored(other))]
                )
                try connection.execute(
                    "UPDATE counterparty_alias SET counterparty_id = ? WHERE counterparty_id = ?",
                    bindings: [.text(stored(counterpartyID.rawValue)), .text(stored(other))]
                )
                try connection.execute(
                    "DELETE FROM counterparty WHERE id = ?",
                    bindings: [.text(stored(other))]
                )
            }
            try connection.execute(
                "INSERT INTO counterparty_alias (id, name, counterparty_id) VALUES (?, ?, ?)",
                bindings: [
                    .text(stored(UUID())),
                    .text(trimmed),
                    .text(stored(counterpartyID.rawValue)),
                ]
            )
            try connection.execute("COMMIT")
        } catch {
            try? connection.execute("ROLLBACK")
            throw error
        }
    }

    func refreshLinkedRefundCategories() throws {
        try connection.execute(
            """
            UPDATE entry
            SET category_id = (
                SELECT purchase.category_id FROM entry AS purchase
                WHERE purchase.id = entry.original_entry_id
            )
            WHERE original_entry_id IS NOT NULL
              AND EXISTS (
                SELECT 1 FROM entry AS purchase WHERE purchase.id = entry.original_entry_id
              )
            """
        )
    }

    public func trash(_ id: Transaction.ID, on date: ReportingDate) throws {
        _ = try transaction(id: id)
        try connection.execute(
            "UPDATE entry SET trashed_on = ? WHERE id = ? AND trashed_on IS NULL",
            bindings: [.text(date.iso8601), .text(stored(id.rawValue))]
        )
    }

    public func restore(_ id: Transaction.ID) throws {
        let current = try transaction(id: id)
        guard try trashedOn(id) != nil else {
            throw LedgerError(message: "That entry is not in the trash.")
        }
        try connection.execute(
            "UPDATE entry SET trashed_on = NULL WHERE id = ?",
            bindings: [.text(stored(current.id.rawValue))]
        )
    }

    public func purgeExpiredTrash(today: ReportingDate) throws {
        let rows = try connection.query("SELECT id, trashed_on FROM entry WHERE trashed_on IS NOT NULL")
        for row in rows {
            guard let id = row[0].text, let trashed = row[1].text.flatMap(ReportingDate.init(iso8601:)) else { continue }
            if trashed.wholeDays(until: today) > 30 {
                try connection.execute("DELETE FROM entry WHERE id = ?", bindings: [.text(id)])
            }
        }
    }

    public func trashedEntries(today: ReportingDate) throws -> [TrashedEntry] {
        let rows = try connection.query(
            """
            \(entrySelectSQL)
            WHERE entry.trashed_on IS NOT NULL
            ORDER BY entry.trashed_on, entry.rowid
            """
        )
        return try rows.map { row in
            let transaction = try decodeTransaction(row)
            let trashed = try trashedOn(transaction.id) ?? today
            let remaining = max(0, 30 - trashed.wholeDays(until: today))
            return TrashedEntry(transaction: transaction, daysRemaining: remaining)
        }
    }

    private func trashedOn(_ id: Transaction.ID) throws -> ReportingDate? {
        let rows = try connection.query(
            "SELECT trashed_on FROM entry WHERE id = ?",
            bindings: [.text(stored(id.rawValue))]
        )
        return rows.first?.first?.text.flatMap(ReportingDate.init(iso8601:))
    }
}

public struct TrashedEntry: Hashable, Sendable, Identifiable {
    public var id: Transaction.ID { transaction.id }
    public let transaction: Transaction
    public let daysRemaining: Int

    public init(transaction: Transaction, daysRemaining: Int) {
        self.transaction = transaction
        self.daysRemaining = daysRemaining
    }
}
