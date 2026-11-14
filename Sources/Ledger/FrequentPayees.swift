import Foundation

public struct FrequentPayee: Hashable, Sendable, Identifiable {
    public let payee: Payee
    public let entryCount: Int
    public let lastUsedAccount: Account

    public var id: Payee.ID { payee.id }
}

extension Ledger {
    /// Active entries of the selected kind, ranked by frequency. The newest
    /// reporting date (then most recently recorded entry) for that payee, across
    /// expense and income, supplies the account.
    public func frequentPayees(kind: Kind, limit: Int = 8) throws -> [FrequentPayee] {
        guard kind != .transfer, limit > 0 else { return [] }
        var entriesByPayee: [Payee.ID: [Transaction]] = [:]
        var lastAccountByPayee: [Payee.ID: Account] = [:]
        for transaction in try transactions() {
            guard let payee = transaction.payee else { continue }
            if lastAccountByPayee[payee.id] == nil {
                lastAccountByPayee[payee.id] = transaction.account
            }
            if transaction.kind == kind {
                entriesByPayee[payee.id, default: []].append(transaction)
            }
        }
        let ranked = entriesByPayee.values.compactMap { entries -> FrequentPayee? in
            guard let latest = entries.first, let payee = latest.payee,
                  let account = lastAccountByPayee[payee.id] else { return nil }
            return FrequentPayee(payee: payee, entryCount: entries.count, lastUsedAccount: account)
        }.sorted {
            if $0.entryCount != $1.entryCount { return $0.entryCount > $1.entryCount }
            let firstName = $0.payee.name.lowercased()
            let secondName = $1.payee.name.lowercased()
            if firstName != secondName { return firstName < secondName }
            return $0.id.rawValue.uuidString < $1.id.rawValue.uuidString
        }
        return Array(ranked.prefix(limit))
    }
}
