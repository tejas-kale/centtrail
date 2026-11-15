import Foundation

extension Ledger {
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
