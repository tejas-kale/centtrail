import Foundation

extension Ledger {
    /// Saves an entry whose category could not be resolved under the reserved
    /// Uncategorised category with the needs-review flag set.
    public func recordForReview(_ draft: EntryDraft) throws -> Transaction {
        let payeeName = draft.payee?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var missing: Set<EntryField> = []
        if draft.amount == nil { missing.insert(.amount) }
        if draft.kind == nil { missing.insert(.kind) }
        if draft.kind != .transfer, payeeName.isEmpty { missing.insert(.payee) }
        if draft.reportingDate == nil { missing.insert(.reportingDate) }
        if draft.accountID == nil { missing.insert(.account) }
        guard missing.isEmpty,
              let amount = draft.amount,
              let kind = draft.kind,
              let reportingDate = draft.reportingDate,
              let accountID = draft.accountID
        else {
            throw RecordEntryError.incomplete(missing)
        }
        guard kind != .transfer else {
            throw LedgerError(message: "Transfers do not need a category review.")
        }
        guard draft.destinationAccountID == nil else {
            throw LedgerError(message: "Only a transfer has a destination account.")
        }
        _ = try account(id: accountID)
        let uncategorisedID = Category.ID(rawValue: OwnerCategories.uncategorisedID)
        let entryID = UUID()
        return try connection.inTransaction {
            let payeeID = try findOrCreatePayee(named: payeeName, defaultCategory: uncategorisedID)
            try insertEntry(
                id: entryID,
                amount: amount,
                kind: kind,
                payeeID: payeeID,
                reportingDate: reportingDate,
                categoryID: uncategorisedID,
                accountID: accountID,
                destinationAccountID: nil,
                provenance: .overridden,
                note: draft.note,
                needsReview: true
            )
            return try requireTransaction(id: entryID)
        }
    }

    /// Active entries flagged for review, newest first.
    public func reviewInbox() throws -> [Transaction] {
        let rows = try connection.query(
            """
            \(entrySelectSQL)
            WHERE entry.trashed_on IS NULL AND entry.needs_review = 1
            ORDER BY entry.reporting_date DESC, entry.rowid DESC
            """
        )
        return try rows.map(decodeTransaction)
    }

    func reviewInboxCount() throws -> Int {
        let rows = try connection.query(
            "SELECT COUNT(*) FROM entry WHERE trashed_on IS NULL AND needs_review = 1"
        )
        return Int(rows.first?.first?.integer ?? 0)
    }
}
