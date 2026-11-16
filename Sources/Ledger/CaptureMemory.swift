import Foundation

public struct DraftCompletion: Equatable, Sendable {
    public var draft: EntryDraft
    public var missingFields: Set<EntryField>

    public init(draft: EntryDraft, missingFields: Set<EntryField>) {
        self.draft = draft
        self.missingFields = missingFields
    }
}

extension Ledger {
    /// Completes an entry draft from parsed amount, payee text and date,
    /// resolving known payees and aliases to fill default category and account
    /// while preserving unmentioned fields from `defaults`.
    public func completeDraft(
        amount: Cents?,
        payeeText: String?,
        date: ReportingDate?,
        defaults: EntryDraft = EntryDraft()
    ) throws -> DraftCompletion {
        let kind = defaults.kind ?? .expense
        let resolvedAmount = amount ?? defaults.amount
        let resolvedDate = date ?? defaults.reportingDate

        let incomingPayee = trimmedNonEmpty(payeeText)
        let defaultPayee = trimmedNonEmpty(defaults.payee)

        var resolvedPayeeName: String? = defaultPayee
        var resolvedCategoryID = defaults.categoryID
        var resolvedAccountID = defaults.accountID
        var overridesCategory = defaults.overridesCategory

        if let incomingPayee {
            if let payeeID = try resolvePayeeID(named: incomingPayee) {
                let payee = try requirePayee(id: payeeID)
                resolvedPayeeName = payee.name
                // A payee default wins as before; an explicit override wins
                // over a category only inferred from history.
                if let defaultCategory = payee.defaultCategory {
                    resolvedCategoryID = defaultCategory.id
                    overridesCategory = false
                } else if overridesCategory {
                    resolvedCategoryID = defaults.categoryID
                } else {
                    resolvedCategoryID = try suggestedCategory(forPayeeName: incomingPayee)?.id
                }
                let mru = try mostRecentlyUsedAccount()?.id
                resolvedAccountID = try lastUsedAccount(forPayeeName: payee.name)?.id
                    ?? defaults.accountID
                    ?? mru
            } else {
                resolvedPayeeName = incomingPayee
                resolvedCategoryID = overridesCategory ? defaults.categoryID : nil
                resolvedAccountID = try defaults.accountID ?? mostRecentlyUsedAccount()?.id
            }
        } else {
            if resolvedAccountID == nil {
                resolvedAccountID = try mostRecentlyUsedAccount()?.id
            }
        }

        let destinationAccountID = kind == .transfer ? defaults.destinationAccountID : nil
        let draft = EntryDraft(
            amount: resolvedAmount,
            kind: kind,
            payee: resolvedPayeeName,
            reportingDate: resolvedDate,
            categoryID: kind == .transfer ? nil : resolvedCategoryID,
            accountID: resolvedAccountID,
            destinationAccountID: destinationAccountID,
            overridesCategory: overridesCategory,
            note: defaults.note
        )

        var missing: Set<EntryField> = []
        if draft.amount == nil { missing.insert(.amount) }
        if draft.kind == nil { missing.insert(.kind) }
        if draft.kind != .transfer, trimmedNonEmpty(draft.payee) == nil { missing.insert(.payee) }
        if draft.reportingDate == nil { missing.insert(.reportingDate) }
        if draft.kind != .transfer, draft.categoryID == nil { missing.insert(.category) }
        if draft.accountID == nil { missing.insert(.account) }
        if draft.kind == .transfer, draft.destinationAccountID == nil { missing.insert(.destinationAccount) }

        return DraftCompletion(draft: draft, missingFields: missing)
    }

    /// Saves a completed draft as a full entry when every field is filled, or
    /// to the review inbox when only the category is missing.
    public func record(_ completion: DraftCompletion) throws -> Transaction {
        if completion.missingFields.isEmpty {
            return try record(completion.draft)
        }
        if completion.missingFields == [.category], completion.draft.kind != .transfer {
            return try recordForReview(completion.draft)
        }
        throw RecordEntryError.incomplete(completion.missingFields)
    }

    private func trimmedNonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    /// The category to pre-select when capture names a known payee: the
    /// payee's default category, else the category of its newest active entry.
    /// Every payee with that name or alias is considered, so a duplicate payee
    /// or a default cleared by sync still yields the category already in use.
    public func suggestedCategory(forPayeeName name: String) throws -> Category? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var payeeIDs: [String] = []
        if let resolved = try resolvePayeeID(named: trimmed) {
            payeeIDs.append(stored(resolved))
        }
        let matches = try connection.query(
            """
            SELECT id FROM counterparty WHERE name = ? COLLATE NOCASE
            UNION
            SELECT counterparty_id FROM counterparty_alias WHERE name = ? COLLATE NOCASE
            """,
            bindings: [.text(trimmed), .text(trimmed)]
        )
        for id in matches.compactMap({ $0.first?.text }) where !payeeIDs.contains(id) {
            payeeIDs.append(id)
        }
        guard !payeeIDs.isEmpty else { return nil }

        let uncategorised = stored(OwnerCategories.uncategorisedID)
        for payeeID in payeeIDs {
            let rows = try connection.query(
                """
                SELECT category.id, category.name, category.counts_as_spending
                FROM counterparty
                JOIN effective_category AS category ON category.id = counterparty.default_category_id
                WHERE counterparty.id = ? AND category.is_removed = 0 AND category.id != ?
                """,
                bindings: [.text(payeeID), .text(uncategorised)]
            )
            if let row = rows.first {
                return try category(idText: row[0].text, name: row[1].text, spending: row[2].integer)
            }
        }

        let placeholders = Array(repeating: "?", count: payeeIDs.count).joined(separator: ", ")
        let lastUsed = try connection.query(
            """
            SELECT category.id, category.name, category.counts_as_spending
            FROM entry
            JOIN effective_category AS category ON category.id = entry.category_id
            WHERE entry.counterparty_id IN (\(placeholders))
              AND entry.trashed_on IS NULL
              AND entry.kind != 'transfer'
              AND category.is_removed = 0
              AND category.id != ?
            ORDER BY entry.reporting_date DESC, entry.rowid DESC
            LIMIT 1
            """,
            bindings: payeeIDs.map { .text($0) } + [.text(uncategorised)]
        )
        guard let row = lastUsed.first else { return nil }
        return try category(idText: row[0].text, name: row[1].text, spending: row[2].integer)
    }

    /// The newest active entry by reporting date, then recording order, supplies
    /// a payee's account across expenses and income. Aliases identify the payee.
    public func lastUsedAccount(forPayeeName name: String) throws -> Account? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let id = try resolvePayeeID(named: trimmed) else { return nil }
        return try transactions().first { $0.payee?.id.rawValue == id }?.account
    }

    /// The newest active entry supplies the capture default for a new payee.
    public func mostRecentlyUsedAccount() throws -> Account? {
        try transactions().first?.account
    }


    /// Suggestions use canonical names while matching names and confirmed aliases.
    public func payeeSuggestions(matching text: String, limit: Int = 5) throws -> [Payee] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, limit > 0 else { return [] }
        let aliases = try confirmedAliases()
        return Array(try payees().filter { payee in
            payee.name.localizedCaseInsensitiveContains(query)
                || aliases.contains { $0.payeeID == payee.id && $0.name.localizedCaseInsensitiveContains(query) }
        }.prefix(limit))
    }

}
