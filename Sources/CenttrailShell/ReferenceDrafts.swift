import Ledger

/// What the add/edit account sheet holds until the owner taps Save.
struct AccountDraft {
    let original: Account?
    var name: String
    var currency: Currency

    init() {
        original = nil
        name = ""
        currency = .eur
    }

    init(editing account: Account) {
        original = account
        name = account.name
        currency = account.currency
    }

    var isEditing: Bool { original != nil }

    /// Changes the currency before the name: the currency is the change the
    /// ledger refuses most often, and a refusal then leaves the account as it was.
    func save(in ledger: Ledger) throws {
        guard let original else {
            _ = try ledger.addAccount(name: name, currency: currency)
            return
        }
        if currency != original.currency {
            _ = try ledger.setAccountCurrency(id: original.id, to: currency)
        }
        if name != original.name {
            _ = try ledger.renameAccount(id: original.id, to: name)
        }
    }
}

/// What the add/edit category sheet holds until the owner taps Save.
/// The ledger fixes whether a category counts as spending when it is added.
struct CategoryDraft {
    let original: LedgerCategory?
    var name: String
    var countsAsSpending: Bool

    init() {
        original = nil
        name = ""
        countsAsSpending = true
    }

    init(editing category: LedgerCategory) {
        original = category
        name = category.name
        countsAsSpending = category.countsAsSpending
    }

    var isEditing: Bool { original != nil }

    func save(in ledger: Ledger) throws {
        guard let original else {
            _ = try ledger.addCategory(name: name, countsAsSpending: countsAsSpending)
            return
        }
        if name != original.name {
            _ = try ledger.renameCategory(id: original.id, to: name)
        }
    }
}
