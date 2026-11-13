import Ledger
import Testing

@Test func savingIsRefusedWhenTheAmountIsMissing() throws {
    let ledger = try Ledger.openInMemory()
    let supermarket = try #require(try ledger.categories().first { $0.name == "Supermarket" })
    let reportingDate = try #require(ReportingDate(iso8601: "2026-11-02"))

    #expect(throws: RecordEntryError.incomplete([.amount])) {
        try ledger.record(
            EntryDraft(
                kind: .expense,
                counterparty: "REWE",
                reportingDate: reportingDate,
                categoryID: supermarket.id
            )
        )
    }
    #expect(try ledger.transactions().isEmpty)
}
