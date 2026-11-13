import Ledger
import Testing

@Test func recordedExpenseAppearsInTheTransactionList() throws {
    let ledger = try Ledger.openInMemory()
    let supermarket = try #require(try ledger.categories().first { $0.name == "Supermarket" })
    let reportingDate = try #require(ReportingDate(iso8601: "2026-11-02"))

    let recorded = try ledger.record(
        EntryDraft(
            amount: Cents(1250),
            kind: .expense,
            counterparty: "REWE",
            reportingDate: reportingDate,
            categoryID: supermarket.id
        )
    )

    #expect(recorded.amount == Cents(1250))
    #expect(recorded.kind == .expense)
    #expect(recorded.counterparty.name == "REWE")
    #expect(recorded.category == supermarket)
    #expect(recorded.reportingDate.iso8601 == "2026-11-02")
    #expect(try ledger.transactions() == [recorded])
}
