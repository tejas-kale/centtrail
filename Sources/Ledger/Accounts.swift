import Foundation

public enum Currency: String, Hashable, Sendable, CaseIterable {
    case eur = "EUR"
    case inr = "INR"

    public var symbol: String {
        switch self {
        case .eur: "€"
        case .inr: "₹"
        }
    }
}

public struct Account: Hashable, Sendable, Identifiable {
    public struct ID: Hashable, Sendable {
        public let rawValue: UUID
        public init(rawValue: UUID) { self.rawValue = rawValue }
    }
    public let id: ID
    public let name: String
    public let currency: Currency
    public init(id: ID, name: String, currency: Currency = .eur) {
        self.id = id
        self.name = name
        self.currency = currency
    }
}

extension Ledger {
    public func accounts() throws -> [Account] {
        try connection.query("SELECT id, name, currency FROM effective_account WHERE is_removed = 0 ORDER BY rowid").map { row in
            guard let id = row[0].text.flatMap(UUID.init(uuidString:)),
                  let name = row[1].text,
                  let currency = row[2].text.flatMap(Currency.init(rawValue:))
            else {
                throw LedgerError(message: "The ledger returned an account it could not read.")
            }
            return Account(id: Account.ID(rawValue: id), name: name, currency: currency)
        }
    }

    func account(id: Account.ID) throws -> Account {
        guard let account = try accounts().first(where: { $0.id == id }) else {
            throw LedgerError(message: "That account no longer exists. Choose another account.")
        }
        return account
    }

    @discardableResult
    public func addAccount(name: String, currency: Currency = .eur) throws -> Account {
        let name = try validatedAccountName(name)
        let account = Account(id: Account.ID(rawValue: UUID()), name: name, currency: currency)
        try connection.execute("INSERT INTO account (id, name, currency) VALUES (?, ?, ?)",
            bindings: [.text(stored(account.id.rawValue)), .text(name), .text(currency.rawValue)])
        return account
    }

    @discardableResult
    public func renameAccount(id: Account.ID, to name: String) throws -> Account {
        let current = try account(id: id)
        let name = try validatedAccountName(name, excluding: id)
        try renameReference(id.rawValue, to: name)
        return Account(id: id, name: name, currency: current.currency)
    }

    @discardableResult
    public func setAccountCurrency(id: Account.ID, to currency: Currency) throws -> Account {
        let current = try account(id: id)
        if current.currency == currency { return current }
        let count = try connection.query(
            "SELECT COUNT(*) FROM entry WHERE account_id = ? OR destination_account_id = ?",
            bindings: [.text(stored(id.rawValue)), .text(stored(id.rawValue))]
        ).first?.first?.integer ?? 0
        if count > 0 {
            let allowed = try connection.query(
                "SELECT can_migrate_currency FROM account WHERE id = ?",
                bindings: [.text(stored(id.rawValue))]
            ).first?.first?.integer ?? 0
            guard allowed == 1 else {
                throw LedgerError(message: "Cannot change \"\(current.name)\"'s currency because \(count) transactions use it.")
            }
            try connection.inTransaction {
                try connection.execute(
                    "UPDATE account SET currency = ? WHERE id = ?",
                    bindings: [.text(currency.rawValue), .text(stored(id.rawValue))]
                )
                try connection.execute("UPDATE account SET can_migrate_currency = 0")
            }
            return Account(id: id, name: current.name, currency: currency)
        }
        try connection.execute(
            "UPDATE account SET currency = ? WHERE id = ?",
            bindings: [.text(currency.rawValue), .text(stored(id.rawValue))]
        )
        return Account(id: id, name: current.name, currency: currency)
    }

    public func removeAccount(id: Account.ID) throws {
        let current = try account(id: id)
        let count = try connection.query("SELECT COUNT(*) FROM entry WHERE account_id = ? OR destination_account_id = ?",
            bindings: [.text(stored(id.rawValue)), .text(stored(id.rawValue))]).first?.first?.integer ?? 0
        guard count == 0 else { throw LedgerError(message: "Cannot remove \"\(current.name)\" because \(count) transactions use it. Reassign them first.") }
        try removeReference(id.rawValue)
    }

    private func validatedAccountName(_ name: String, excluding id: Account.ID? = nil) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LedgerError(message: "An account needs a name.") }
        guard try !accounts().contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            throw LedgerError(message: "An account with that name already exists.")
        }
        return trimmed
    }

    func seedAccounts() throws {
        try connection.inTransaction {
            for name in ["N26", "Revolut", "Cash", "India"] {
                let id = OwnerCategories.deterministicID(for: "account:\(name)")
                try connection.execute("INSERT OR IGNORE INTO account (id, name) VALUES (?, ?)",
                    bindings: [.text(stored(id)), .text(name)])
            }
        }
    }
}
