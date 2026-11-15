import Foundation
import GRDB
import Ledger
import Testing

@Test func accountsStartWithTheOwnersAccountsAndCanBeEdited() throws {
    let ledger = try Ledger.openInMemory()
    #expect(try ledger.accounts().map(\.name) == ["N26", "Revolut", "Cash", "India"])
    let account = try ledger.addAccount(name: " Savings bank ")
    #expect(account.name == "Savings bank")
    let renamed = try ledger.renameAccount(id: account.id, to: "Bank")
    #expect(renamed.id == account.id)
    #expect(try ledger.accounts().last?.name == "Bank")
    try ledger.removeAccount(id: account.id)
    #expect(try ledger.accounts().count == 4)
}

@Test func expenseRequiresAnAccountAndTransfersNeedDifferentAccounts() throws {
    let ledger = try Ledger.openInMemory()
    let accounts = try ledger.accounts()
    let date = try #require(ReportingDate(iso8601: "2026-11-14"))
    let category = try namedCategory(ledger, "Supermarket")
    #expect(throws: RecordEntryError.incomplete([.account])) {
        try ledger.record(EntryDraft(amount: Cents(100), kind: .expense, payee: "REWE", reportingDate: date, categoryID: category.id))
    }
    #expect(throws: LedgerError.self) {
        try ledger.record(EntryDraft(amount: Cents(50000), kind: .transfer, reportingDate: date, accountID: accounts[0].id, destinationAccountID: accounts[0].id))
    }
    let transfer = try ledger.record(EntryDraft(amount: Cents(50000), kind: .transfer, reportingDate: date, accountID: accounts[0].id, destinationAccountID: accounts[3].id))
    #expect(transfer.account.name == "N26")
    #expect(transfer.destinationAccount?.name == "India")
    #expect(transfer.payee == nil)
    #expect(transfer.category == nil)
    #expect(try ledger.transactions() == [transfer])
    #expect(try ledger.runReport(.currentMonthSpending, today: date) == .spendingTotal(SignedCents(0)))
    #expect(try ledger.runReport(.currentMonthIncome, today: date) == .incomeTotal(SignedCents(0)))
    #expect(throws: LedgerError.self) { try ledger.removeAccount(id: accounts[0].id) }
    #expect(throws: LedgerError.self) { try ledger.removeAccount(id: accounts[3].id) }
}

@Test func incomeRequiresAnAccountAndStoredAccountsSurviveReopening() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
    let ledger = try Ledger.open(at: url)
    let accounts = try ledger.accounts()
    let date = try #require(ReportingDate(iso8601: "2026-11-14"))
    let category = try namedCategory(ledger, "Salary")
    #expect(throws: RecordEntryError.incomplete([.account])) {
        try ledger.record(EntryDraft(amount: Cents(100), kind: .income, payee: "Employer", reportingDate: date, categoryID: category.id))
    }
    let income = try ledger.record(EntryDraft(amount: Cents(100), kind: .income, payee: "Employer", reportingDate: date, categoryID: category.id, accountID: accounts[1].id))
    _ = try ledger.renameAccount(id: accounts[1].id, to: "Everyday")
    try ledger.removeAccount(id: accounts[2].id)
    let reopened = try Ledger.open(at: url)
    #expect(try reopened.accounts().map(\.name) == ["N26", "Everyday", "India"])
    #expect(try reopened.transaction(id: income.id).account.name == "Everyday")
    #expect(throws: LedgerError.self) { try reopened.removeAccount(id: accounts[1].id) }
    #expect(throws: LedgerError.self) { try reopened.addAccount(name: " everyday ") }
    #expect(throws: LedgerError.self) { try reopened.addAccount(name: " ") }
}

@Test func accountsCarryCurrencyAndPersistAcrossReopening() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
    defer { try? FileManager.default.removeItem(at: url) }
    let ledger = try Ledger.open(at: url)
    #expect(try ledger.accounts().allSatisfy { $0.currency == .eur })

    let inrCash = try ledger.addAccount(name: "INR Cash", currency: .inr)
    #expect(inrCash.currency == .inr)

    let reopened = try Ledger.open(at: url)
    let fetched = try #require(try reopened.accounts().first { $0.id == inrCash.id })
    #expect(fetched.currency == .inr)
}

@Test func changingAccountCurrencySucceedsWhenEmptyAndIsRefusedOnceItHoldsEntries() throws {
    let ledger = try Ledger.openInMemory()
    let accounts = try ledger.accounts()
    let india = try #require(accounts.first { $0.name == "India" })
    let n26 = try #require(accounts.first { $0.name == "N26" })

    let updatedIndia = try ledger.setAccountCurrency(id: india.id, to: .inr)
    #expect(updatedIndia.currency == .inr)
    #expect(try ledger.accounts().first { $0.id == india.id }?.currency == .inr)

    let date = try #require(ReportingDate(iso8601: "2026-11-14"))
    _ = try ledger.record(EntryDraft(
        amount: Cents(50000),
        kind: .transfer,
        reportingDate: date,
        accountID: n26.id,
        destinationAccountID: india.id
    ))

    // Both source and destination accounts now hold entries, so currency changes are refused.
    #expect(throws: LedgerError.self) { try ledger.setAccountCurrency(id: n26.id, to: .inr) }
    #expect(throws: LedgerError.self) { try ledger.setAccountCurrency(id: india.id, to: .eur) }
    // Setting to the same currency is a no-op.
    #expect(try ledger.setAccountCurrency(id: india.id, to: .inr).currency == .inr)
}

@Test func preMigrationLedgerSetsAllAccountsToEURAndAllowsMarkingIndiaINROnce() throws {
    let file = try legacyCurrencyLedger()
    let ledger = try Ledger.open(at: file)
    let accounts = try ledger.accounts()
    #expect(accounts.allSatisfy { $0.currency == .eur })

    let transactions = try ledger.transactions()
    #expect(transactions.map(\.amount.value).sorted() == [1250, 50000])

    let india = try #require(accounts.first { $0.name == "India" })
    let n26 = try #require(accounts.first { $0.name == "N26" })

    // One-time post-migration allowance permits marking India as INR even though it holds entries.
    let updatedIndia = try ledger.setAccountCurrency(id: india.id, to: .inr)
    #expect(updatedIndia.currency == .inr)
    #expect(try ledger.accounts().first { $0.id == india.id }?.currency == .inr)

    // Allowance is consumed: further currency changes on accounts with entries are refused.
    #expect(throws: LedgerError.self) { try ledger.setAccountCurrency(id: india.id, to: .eur) }
    #expect(throws: LedgerError.self) { try ledger.setAccountCurrency(id: n26.id, to: .inr) }
}

private func legacyCurrencyLedger() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("ledger.sqlite")
    do {
        let ledger = try Ledger.open(at: file)
        let accounts = try ledger.accounts()
        let n26 = try #require(accounts.first { $0.name == "N26" })
        let india = try #require(accounts.first { $0.name == "India" })
        let date = try #require(ReportingDate(iso8601: "2026-11-14"))
        _ = try ledger.record(EntryDraft(
            amount: Cents(1250),
            kind: .expense,
            payee: "Lidl",
            reportingDate: date,
            categoryID: try namedCategory(ledger, "Supermarket").id,
            accountID: n26.id
        ))
        _ = try ledger.record(EntryDraft(
            amount: Cents(50000),
            kind: .transfer,
            reportingDate: date,
            accountID: n26.id,
            destinationAccountID: india.id
        ))
    }
    let database = try DatabaseQueue(path: file.path)
    try database.write { db in
        try db.execute(sql: """
            DROP VIEW IF EXISTS spending;
            DROP VIEW IF EXISTS effective_account;
            CREATE VIEW effective_account AS
                SELECT account.rowid AS rowid, account.id,
                    COALESCE(custom.name, account.name) AS name,
                    COALESCE(custom.is_removed, 0) AS is_removed
                FROM account LEFT JOIN reference_customization AS custom ON custom.id = account.id;
            CREATE VIEW spending AS
                SELECT entry.id, entry.reporting_date, entry.amount_cents,
                    entry.amount_cents / 100.0 AS amount, 'EUR' AS currency,
                    counterparty.name AS payee, category.name AS category,
                    account.name AS account, entry.account_id, entry.category_id,
                    entry.counterparty_id AS payee_id
                FROM entry
                JOIN effective_category AS category ON category.id = entry.category_id
                JOIN effective_account AS account ON account.id = entry.account_id
                LEFT JOIN counterparty ON counterparty.id = entry.counterparty_id
                WHERE entry.kind = 'expense' AND entry.trashed_on IS NULL
                    AND category.counts_as_spending = 1;
            ALTER TABLE account DROP COLUMN currency;
            ALTER TABLE account DROP COLUMN can_migrate_currency;
            DELETE FROM grdb_migrations WHERE identifier = 'v4_account_currency';
            """)
    }
    return file
}
