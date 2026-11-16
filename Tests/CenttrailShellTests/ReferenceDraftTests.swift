@testable import CenttrailShell
import Foundation
@testable import Ledger
import Testing

@Suite(.serialized)
struct ReferenceDraftTests {
    @Test func addingAnAccountCreatesItWithTheChosenCurrency() throws {
        let ledger = try Ledger.openInMemory()
        var draft = AccountDraft()
        draft.name = "  Wise  "
        draft.currency = .inr

        try draft.save(in: ledger)

        let wise = try #require(try ledger.accounts().first { $0.name == "Wise" })
        #expect(wise.currency == .inr)
    }

    @Test func editingAnUnusedAccountRenamesItAndChangesItsCurrency() throws {
        let ledger = try Ledger.openInMemory()
        let cash = try #require(try ledger.accounts().first { $0.name == "Cash" })
        var draft = AccountDraft(editing: cash)
        #expect(draft.name == "Cash")
        #expect(draft.currency == .eur)

        draft.name = "Wallet"
        draft.currency = .inr
        try draft.save(in: ledger)

        let wallet = try #require(try ledger.accounts().first { $0.id == cash.id })
        #expect(wallet.name == "Wallet")
        #expect(wallet.currency == .inr)
    }

    @Test func aBlockedCurrencyChangeLeavesTheAccountNameUnchanged() throws {
        let ledger = try Ledger.openInMemory()
        let cash = try #require(try ledger.accounts().first { $0.name == "Cash" })
        let supermarket = try #require(try ledger.categories().first { $0.name == "Supermarket" })
        _ = try ledger.record(EntryDraft(
            amount: Cents(1_000), kind: .expense, payee: "REWE",
            reportingDate: ReportingDate(iso8601: "2026-11-02"),
            categoryID: supermarket.id, accountID: cash.id
        ))
        try ledger.connection.execute("UPDATE account SET can_migrate_currency = 0")
        var draft = AccountDraft(editing: cash)
        draft.name = "Wallet"
        draft.currency = .inr

        #expect(throws: LedgerError.self) { try draft.save(in: ledger) }

        let unchanged = try #require(try ledger.accounts().first { $0.id == cash.id })
        #expect(unchanged.name == "Cash")
        #expect(unchanged.currency == .eur)
    }

    @Test func addingACategoryCanExcludeItFromSpending() throws {
        let ledger = try Ledger.openInMemory()
        var draft = CategoryDraft()
        draft.name = "Loans"
        draft.countsAsSpending = false

        try draft.save(in: ledger)

        let loans = try #require(try ledger.categories().first { $0.name == "Loans" })
        #expect(loans.countsAsSpending == false)
    }

    @Test func editingACategoryRenamesIt() throws {
        let ledger = try Ledger.openInMemory()
        let restaurant = try #require(try ledger.categories().first { $0.name == "Restaurant" })
        var draft = CategoryDraft(editing: restaurant)
        #expect(draft.name == "Restaurant")

        draft.name = "Eating out"
        try draft.save(in: ledger)

        let renamed = try #require(try ledger.categories().first { $0.id == restaurant.id })
        #expect(renamed.name == "Eating out")
    }
}
