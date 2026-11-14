import Foundation

let entrySelectSQL = """
SELECT
    entry.id,
    entry.amount_cents,
    entry.kind,
    entry.reporting_date,
    entry.category_provenance,
    entry.note,
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
        payeeID: UUID,
        reportingDate: ReportingDate,
        categoryID: Category.ID,
        provenance: CategoryProvenance,
        note: String?
    ) throws {
        try connection.execute(
            """
            INSERT INTO entry (
                id, amount_cents, kind, counterparty_id, reporting_date, category_id,
                category_provenance, note
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(stored(id)),
                .integer(Int64(amount.value)),
                .text(kind.rawValue),
                .text(stored(payeeID)),
                .text(reportingDate.iso8601),
                .text(stored(categoryID.rawValue)),
                .text(provenance.rawValue),
                note.map(SQLiteValue.text) ?? .null,
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
        guard row.count == 15,
              let entryID = row[0].text.flatMap(UUID.init(uuidString:)),
              let cents = row[1].integer,
              let kind = row[2].text.flatMap(Kind.init(rawValue:)),
              let reportingDate = row[3].text.flatMap(ReportingDate.init(iso8601:)),
              let provenance = row[4].text.flatMap(CategoryProvenance.init(rawValue:)),
              let payeeID = row[7].text.flatMap(UUID.init(uuidString:)),
              let payeeName = row[8].text,
              let categoryID = row[12].text.flatMap(UUID.init(uuidString:)),
              let categoryName = row[13].text,
              let categorySpending = row[14].integer
        else {
            throw LedgerError(message: "The ledger returned an entry it could not read.")
        }
        let note = row[5].text
        return Transaction(
            id: Transaction.ID(rawValue: entryID),
            amount: Cents(Int(cents)),
            kind: kind,
            payee: Payee(
                id: Payee.ID(rawValue: payeeID),
                name: payeeName,
                defaultCategory: try category(idText: row[9].text, name: row[10].text, spending: row[11].integer)
            ),
            reportingDate: reportingDate,
            category: Category(
                id: Category.ID(rawValue: categoryID),
                name: categoryName,
                countsAsSpending: categorySpending != 0
            ),
            categoryProvenance: provenance,
            note: note
        )
    }

    public func payees() throws -> [Payee] {
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
                throw LedgerError(message: "The ledger returned a payee it could not read.")
            }
            return Payee(
                id: Payee.ID(rawValue: id),
                name: name,
                defaultCategory: try category(idText: row[2].text, name: row[3].text, spending: row[4].integer)
            )
        }
    }

    public func defaultCategory(forPayeeName name: String) throws -> Category? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let id = try resolvePayeeID(named: trimmed) else { return nil }
        return try requirePayee(id: id).defaultCategory
    }

    func requirePayee(id: UUID) throws -> Payee {
        guard let match = try payees().first(where: { $0.id.rawValue == id }) else {
            throw LedgerError(message: "That payee is not in the ledger.")
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

    public func setDefaultCategory(_ categoryID: Category.ID, for payeeID: Payee.ID) throws {
        _ = try category(id: categoryID)
        try connection.inTransaction {
            try connection.execute(
                "UPDATE counterparty SET default_category_id = ? WHERE id = ?",
                bindings: [.text(stored(categoryID.rawValue)), .text(stored(payeeID.rawValue))]
            )
            try connection.execute(
                """
                UPDATE entry
                SET category_id = ?
                WHERE counterparty_id = ?
                  AND category_provenance = 'inherited'
                """,
                bindings: [.text(stored(categoryID.rawValue)), .text(stored(payeeID.rawValue))]
            )
            try connection.execute(
                "DELETE FROM proposed_payee_default WHERE counterparty_id = ?",
                bindings: [.text(stored(payeeID.rawValue))]
            )
        }
    }

    public func setCategory(_ categoryID: Category.ID, for entryID: Transaction.ID) throws {
        _ = try category(id: categoryID)
        _ = try transaction(id: entryID)
        try connection.inTransaction {
            try connection.execute(
                """
                UPDATE entry
                SET category_id = ?, category_provenance = 'overridden'
                WHERE id = ?
                """,
                bindings: [.text(stored(categoryID.rawValue)), .text(stored(entryID.rawValue))]
            )
        }
    }

    public func confirmedAliases() throws -> [(name: String, payeeID: Payee.ID)] {
        let rows = try connection.query("SELECT name, counterparty_id FROM counterparty_alias ORDER BY name")
        return rows.compactMap { row in
            guard let name = row[0].text, let id = row[1].text.flatMap(UUID.init(uuidString:)) else { return nil }
            return (name, Payee.ID(rawValue: id))
        }
    }

    public func confirmAlias(_ name: String, of payeeID: Payee.ID) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw LedgerError(message: "An alias needs a name.")
        }
        let target = try requirePayee(id: payeeID.rawValue)
        if trimmed == target.name {
            throw LedgerError(message: "An alias has to be a different name from the payee.")
        }
        if let existingAlias = try connection.query(
            "SELECT counterparty_id FROM counterparty_alias WHERE name = ?",
            bindings: [.text(trimmed)]
        ).first?.first?.text, let owner = UUID(uuidString: existingAlias) {
            if owner == payeeID.rawValue { return }
            throw LedgerError(message: "That alias already belongs to another payee.")
        }
        try connection.inTransaction {
            if let other = try resolvePayeeID(named: trimmed), other != payeeID.rawValue {
                try connection.execute(
                    "UPDATE entry SET counterparty_id = ? WHERE counterparty_id = ?",
                    bindings: [.text(stored(payeeID.rawValue)), .text(stored(other))]
                )
                try connection.execute(
                    "UPDATE counterparty_alias SET counterparty_id = ? WHERE counterparty_id = ?",
                    bindings: [.text(stored(payeeID.rawValue)), .text(stored(other))]
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
                    .text(stored(payeeID.rawValue)),
                ]
            )
        }
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
