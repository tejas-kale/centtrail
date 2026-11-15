import Foundation

extension Ledger {
    public func budgets() throws -> [CategoryBudget] {
        let rows = try connection.query(
            """
            SELECT category.id, category.name, category.counts_as_spending, budget.currency, budget.amount_cents
            FROM budget
            JOIN effective_category AS category ON category.id = budget.category_id
            WHERE category.is_removed = 0 AND category.counts_as_spending = 1
            ORDER BY category.name COLLATE NOCASE, budget.rowid
            """
        )
        var seen: Set<Category.ID> = []
        var result: [CategoryBudget] = []
        for row in rows {
            guard row.count == 5,
                  let categoryID = row[0].text.flatMap(UUID.init(uuidString:)),
                  let name = row[1].text,
                  let countsAsSpending = row[2].integer,
                  let currency = row[3].text.flatMap(Currency.init(rawValue:)),
                  let amountCents = row[4].integer
            else {
                throw LedgerError(message: "The ledger returned a budget it could not read.")
            }
            let id = Category.ID(rawValue: categoryID)
            guard seen.insert(id).inserted else { continue }
            result.append(CategoryBudget(
                category: Category(id: id, name: name, countsAsSpending: countsAsSpending == 1),
                currency: currency,
                amount: Cents(Int(amountCents))
            ))
        }
        return result
    }

    @discardableResult
    public func setBudget(categoryID: Category.ID, amount: Cents, currency: Currency) throws -> CategoryBudget {
        guard amount.value > 0 else {
            throw LedgerError(message: "A budget amount must be greater than zero.")
        }
        let category = try category(id: categoryID)
        guard category.countsAsSpending else {
            throw LedgerError(message: "Only spending categories can have a monthly budget.")
        }
        try connection.inTransaction {
            let existing = try connection.query(
                "SELECT id FROM budget WHERE category_id = ? ORDER BY rowid LIMIT 1",
                bindings: [.text(stored(categoryID.rawValue))]
            )
            if let existingID = existing.first?.first?.text {
                try connection.execute(
                    "UPDATE budget SET currency = ?, amount_cents = ? WHERE id = ?",
                    bindings: [.text(currency.rawValue), .integer(Int64(amount.value)), .text(existingID)]
                )
                try connection.execute(
                    "DELETE FROM budget WHERE category_id = ? AND id != ?",
                    bindings: [.text(stored(categoryID.rawValue)), .text(existingID)]
                )
            } else {
                try connection.execute(
                    "INSERT INTO budget (id, category_id, currency, amount_cents) VALUES (?, ?, ?, ?)",
                    bindings: [
                        .text(stored(UUID())),
                        .text(stored(categoryID.rawValue)),
                        .text(currency.rawValue),
                        .integer(Int64(amount.value)),
                    ]
                )
            }
        }
        return CategoryBudget(category: category, currency: currency, amount: amount)
    }

    public func removeBudget(categoryID: Category.ID) throws {
        try connection.execute(
            "DELETE FROM budget WHERE category_id = ?",
            bindings: [.text(stored(categoryID.rawValue))]
        )
    }

    func budgetGauges(in range: DateRange) throws -> [BudgetGauge] {
        let activeBudgets = try budgets()
        guard !activeBudgets.isEmpty else { return [] }
        let rows = try connection.query(
            """
            SELECT entry.category_id, account.currency, COALESCE(SUM(entry.amount_cents), 0)
            FROM entry
            JOIN effective_category AS entry_category ON entry_category.id = entry.category_id
            JOIN effective_account AS account ON account.id = entry.account_id
            WHERE entry.trashed_on IS NULL
              AND entry.kind = 'expense'
              AND entry_category.counts_as_spending = 1
              AND entry.reporting_date >= ?
              AND entry.reporting_date <= ?
            GROUP BY entry.category_id, account.currency
            """,
            bindings: [.text(range.start.iso8601), .text(range.end.iso8601)]
        )
        struct SpendingKey: Hashable {
            let categoryID: Category.ID
            let currency: Currency
        }
        var spentByKey: [SpendingKey: Int] = [:]
        for row in rows {
            guard let id = row[0].text.flatMap(UUID.init(uuidString:)),
                  let currency = row[1].text.flatMap(Currency.init(rawValue:)),
                  let total = row[2].integer
            else { continue }
            spentByKey[SpendingKey(categoryID: Category.ID(rawValue: id), currency: currency)] = Int(total)
        }
        return activeBudgets.map { budget in
            let spent = spentByKey[SpendingKey(categoryID: budget.category.id, currency: budget.currency)] ?? 0
            return BudgetGauge(
                category: budget.category,
                currency: budget.currency,
                budget: budget.amount,
                spent: Cents(spent)
            )
        }
    }
}
