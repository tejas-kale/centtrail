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

@Test func savingIsRefusedWhenTheKindIsMissing() throws {
    let ledger = try Ledger.openInMemory()
    let supermarket = try #require(try ledger.categories().first { $0.name == "Supermarket" })
    let reportingDate = try #require(ReportingDate(iso8601: "2026-11-02"))

    #expect(throws: RecordEntryError.incomplete([.kind])) {
        try ledger.record(
            EntryDraft(
                amount: Cents(1250),
                counterparty: "REWE",
                reportingDate: reportingDate,
                categoryID: supermarket.id
            )
        )
    }
    #expect(try ledger.transactions().isEmpty)
}

@Test func savingIsRefusedWhenTheCounterpartyIsMissing() throws {
    let ledger = try Ledger.openInMemory()
    let supermarket = try #require(try ledger.categories().first { $0.name == "Supermarket" })
    let reportingDate = try #require(ReportingDate(iso8601: "2026-11-02"))

    #expect(throws: RecordEntryError.incomplete([.counterparty])) {
        try ledger.record(
            EntryDraft(
                amount: Cents(1250),
                kind: .expense,
                reportingDate: reportingDate,
                categoryID: supermarket.id
            )
        )
    }
    #expect(try ledger.transactions().isEmpty)
}

@Test func savingIsRefusedWhenTheCounterpartyIsBlank() throws {
    let ledger = try Ledger.openInMemory()
    let supermarket = try #require(try ledger.categories().first { $0.name == "Supermarket" })
    let reportingDate = try #require(ReportingDate(iso8601: "2026-11-02"))

    #expect(throws: RecordEntryError.incomplete([.counterparty])) {
        try ledger.record(
            EntryDraft(
                amount: Cents(1250),
                kind: .expense,
                counterparty: " \n\t ",
                reportingDate: reportingDate,
                categoryID: supermarket.id
            )
        )
    }
    #expect(try ledger.transactions().isEmpty)
}
