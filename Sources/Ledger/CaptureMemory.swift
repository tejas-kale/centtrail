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
                resolvedCategoryID = payee.defaultCategory?.id ?? (overridesCategory ? defaults.categoryID : nil)
                if payee.defaultCategory != nil {
                    overridesCategory = false
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

    private func trimmedNonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
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
