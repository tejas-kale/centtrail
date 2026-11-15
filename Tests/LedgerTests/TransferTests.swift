import Foundation
import GRDB
@testable import Ledger
import Testing

@Test func crossCurrencyTransferRequiresReceivedAmountAndStoresBothAmounts() throws {
    let ledger = try Ledger.openInMemory()
    let accounts = try ledger.accounts()
    let n26 = try #require(accounts.first { $0.name == "N26" })
    let india = try #require(accounts.first { $0.name == "India" })
    try ledger.setAccountCurrency(id: india.id, to: .inr)
    let date = try #require(ReportingDate(iso8601: "2026-11-15"))

    #expect(throws: RecordEntryError.incomplete([.receivedAmount])) {
        try ledger.record(EntryDraft(
            amount: Cents(50_000),
            kind: .transfer,
            reportingDate: date,
            accountID: n26.id,
            destinationAccountID: india.id
        ))
    }

    let saved = try ledger.record(EntryDraft(
        amount: Cents(50_000),
        receivedAmount: Cents(4_500_000),
        kind: .transfer,
        reportingDate: date,
        accountID: n26.id,
        destinationAccountID: india.id
    ))
    #expect(saved.amount == Cents(50_000))
    #expect(saved.receivedAmount == Cents(4_500_000))
    #expect(saved.account.currency == .eur)
    #expect(saved.destinationAccount?.currency == .inr)
}

@Test func sameCurrencyTransferStoresEqualReceivedAmountAndNonTransferRefusesReceivedAmount() throws {
    let ledger = try Ledger.openInMemory()
    let accounts = try ledger.accounts()
    let n26 = try #require(accounts.first { $0.name == "N26" })
    let cash = try #require(accounts.first { $0.name == "Cash" })
    let supermarket = try namedCategory(ledger, "Supermarket")
    let date = try #require(ReportingDate(iso8601: "2026-11-15"))

    let sameCurrency = try ledger.record(EntryDraft(
        amount: Cents(10_000),
        kind: .transfer,
        reportingDate: date,
        accountID: n26.id,
        destinationAccountID: cash.id
    ))
    #expect(sameCurrency.amount == Cents(10_000))
    #expect(sameCurrency.receivedAmount == Cents(10_000))

    #expect(throws: LedgerError.self) {
        try ledger.record(EntryDraft(
            amount: Cents(1250),
            receivedAmount: Cents(1250),
            kind: .expense,
            payee: "Lidl",
            reportingDate: date,
            categoryID: supermarket.id,
            accountID: n26.id
        ))
    }
}

@Test func editingCrossCurrencyTransferPreservesAndUpdatesBothAmounts() throws {
    let ledger = try Ledger.openInMemory()
    let accounts = try ledger.accounts()
    let n26 = try #require(accounts.first { $0.name == "N26" })
    let india = try #require(accounts.first { $0.name == "India" })
    try ledger.setAccountCurrency(id: india.id, to: .inr)
    let date = try #require(ReportingDate(iso8601: "2026-11-15"))

    let saved = try ledger.record(EntryDraft(
        amount: Cents(50_000),
        receivedAmount: Cents(4_500_000),
        kind: .transfer,
        reportingDate: date,
        accountID: n26.id,
        destinationAccountID: india.id,
        note: "Remittance"
    ))

    let edited = try ledger.update(saved.id, with: EntryDraft(
        amount: Cents(60_000),
        receivedAmount: Cents(5_400_000),
        kind: .transfer,
        reportingDate: date,
        accountID: n26.id,
        destinationAccountID: india.id,
        note: "Remittance updated"
    ))
    #expect(edited.id == saved.id)
    #expect(edited.amount == Cents(60_000))
    #expect(edited.receivedAmount == Cents(5_400_000))
    #expect(edited.note == "Remittance updated")
}

@Test func crossCurrencyTransferIsExcludedFromSpendingInBothCurrencies() throws {
    let ledger = try Ledger.openInMemory()
    let accounts = try ledger.accounts()
    let n26 = try #require(accounts.first { $0.name == "N26" })
    let india = try #require(accounts.first { $0.name == "India" })
    try ledger.setAccountCurrency(id: india.id, to: .inr)
    let supermarket = try namedCategory(ledger, "Supermarket")
    let date = try #require(ReportingDate(iso8601: "2026-11-15"))

    _ = try ledger.record(EntryDraft(
        amount: Cents(50_000),
        receivedAmount: Cents(4_500_000),
        kind: .transfer,
        reportingDate: date,
        accountID: n26.id,
        destinationAccountID: india.id
    ))
    _ = try ledger.record(EntryDraft(
        amount: Cents(1250),
        kind: .expense,
        payee: "Lidl",
        reportingDate: date,
        categoryID: supermarket.id,
        accountID: n26.id
    ))

    let summary = try ledger.monthSummary(on: date)
    #expect(summary.spendingByCurrency == [.eur: 1250])
}

@Test func migratedTransferKeepsSentAmountWithNilReceivedAmountAndNoReviewFlag() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("ledger.sqlite")
    let date = try #require(ReportingDate(iso8601: "2026-11-14"))
    do {
        let ledger = try Ledger.open(at: file)
        let accounts = try ledger.accounts()
        let n26 = try #require(accounts.first { $0.name == "N26" })
        let india = try #require(accounts.first { $0.name == "India" })
        _ = try ledger.record(EntryDraft(
            amount: Cents(50_000),
            kind: .transfer,
            reportingDate: date,
            accountID: n26.id,
            destinationAccountID: india.id
        ))
    }
    let database = try DatabaseQueue(path: file.path)
    try database.write { db in
        try db.execute(sql: """
            DROP VIEW IF EXISTS transfers_with_rate;
            ALTER TABLE entry DROP COLUMN received_amount_cents;
            DELETE FROM grdb_migrations WHERE identifier = 'v4_cross_currency_transfers';
            """)
    }

    let reopened = try Ledger.open(at: file)
    let transfers = try reopened.transactions().filter { $0.kind == .transfer }
    #expect(transfers.count == 1)
    #expect(transfers[0].amount == Cents(50_000))
    #expect(transfers[0].receivedAmount == nil)
    #expect(transfers[0].needsReview == false)
    #expect(try reopened.reviewInbox().isEmpty)
}
