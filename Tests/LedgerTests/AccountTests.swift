import Foundation
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
