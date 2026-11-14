import Foundation

public struct Account: Hashable, Sendable, Identifiable {
    public struct ID: Hashable, Sendable {
        public let rawValue: UUID
        public init(rawValue: UUID) { self.rawValue = rawValue }
    }
    public let id: ID
    public let name: String
    public init(id: ID, name: String) { self.id = id; self.name = name }
}

extension Ledger {
    public func accounts() throws -> [Account] {
        try connection.query("SELECT id, name FROM account ORDER BY rowid").map { row in
            guard let id = row[0].text.flatMap(UUID.init(uuidString:)), let name = row[1].text else {
                throw LedgerError(message: "The ledger returned an account it could not read.")
            }
            return Account(id: Account.ID(rawValue: id), name: name)
        }
    }

    func account(id: Account.ID) throws -> Account {
        guard let account = try accounts().first(where: { $0.id == id }) else {
            throw LedgerError(message: "That account no longer exists. Choose another account.")
        }
        return account
    }

    @discardableResult
    public func addAccount(name: String) throws -> Account {
        let name = try validatedAccountName(name)
        let account = Account(id: Account.ID(rawValue: UUID()), name: name)
        try connection.execute("INSERT INTO account (id, name) VALUES (?, ?)",
            bindings: [.text(stored(account.id.rawValue)), .text(name)])
        return account
    }

    @discardableResult
    public func renameAccount(id: Account.ID, to name: String) throws -> Account {
        _ = try account(id: id)
        let name = try validatedAccountName(name, excluding: id)
        try connection.execute("UPDATE account SET name = ? WHERE id = ?",
            bindings: [.text(name), .text(stored(id.rawValue))])
        return Account(id: id, name: name)
    }

    public func removeAccount(id: Account.ID) throws {
        let current = try account(id: id)
        let count = try connection.query("SELECT COUNT(*) FROM entry WHERE account_id = ? OR destination_account_id = ?",
            bindings: [.text(stored(id.rawValue)), .text(stored(id.rawValue))]).first?.first?.integer ?? 0
        guard count == 0 else { throw LedgerError(message: "Cannot remove \"\(current.name)\" because \(count) transactions use it. Reassign them first.") }
        try connection.execute("DELETE FROM account WHERE id = ?", bindings: [.text(stored(id.rawValue))])
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
            guard try connection.query("SELECT key FROM ledger_initialization WHERE key = 'accounts'").isEmpty else { return }
            for name in ["N26", "Revolut", "Cash", "India"] {
                let id = OwnerCategories.deterministicID(for: "account:\(name)")
                try connection.execute("INSERT OR IGNORE INTO account (id, name) VALUES (?, ?)",
                    bindings: [.text(stored(id)), .text(name)])
            }
            let fallbackID = OwnerCategories.deterministicID(for: "account:N26")
            try connection.execute("UPDATE entry SET account_id = ? WHERE account_id IS NULL", bindings: [.text(stored(fallbackID))])
            try connection.execute("INSERT INTO ledger_initialization (key) VALUES ('accounts')")
        }
    }
}
