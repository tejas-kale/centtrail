import Foundation
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
                payee: "REWE",
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
                payee: "REWE",
                reportingDate: reportingDate,
                categoryID: supermarket.id
            )
        )
    }
    #expect(try ledger.transactions().isEmpty)
}

@Test func savingIsRefusedWhenThePayeeIsMissing() throws {
    let ledger = try Ledger.openInMemory()
    let supermarket = try #require(try ledger.categories().first { $0.name == "Supermarket" })
    let reportingDate = try #require(ReportingDate(iso8601: "2026-11-02"))

    #expect(throws: RecordEntryError.incomplete([.payee])) {
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

@Test func savingIsRefusedWhenThePayeeIsBlank() throws {
    let ledger = try Ledger.openInMemory()
    let supermarket = try #require(try ledger.categories().first { $0.name == "Supermarket" })
    let reportingDate = try #require(ReportingDate(iso8601: "2026-11-02"))

    #expect(throws: RecordEntryError.incomplete([.payee])) {
        try ledger.record(
            EntryDraft(
                amount: Cents(1250),
                kind: .expense,
                payee: " \n\t ",
                reportingDate: reportingDate,
                categoryID: supermarket.id
            )
        )
    }
    #expect(try ledger.transactions().isEmpty)
}

@Test func savingIsRefusedWhenTheReportingDateIsMissing() throws {
    let ledger = try Ledger.openInMemory()
    let supermarket = try #require(try ledger.categories().first { $0.name == "Supermarket" })

    #expect(throws: RecordEntryError.incomplete([.reportingDate])) {
        try ledger.record(
            EntryDraft(
                amount: Cents(1250),
                kind: .expense,
                payee: "REWE",
                categoryID: supermarket.id
            )
        )
    }
    #expect(try ledger.transactions().isEmpty)
}

@Test func savingIsRefusedWhenTheCategoryIsMissing() throws {
    let ledger = try Ledger.openInMemory()
    let reportingDate = try #require(ReportingDate(iso8601: "2026-11-02"))

    #expect(throws: RecordEntryError.incomplete([.category])) {
        try ledger.record(
            EntryDraft(
                amount: Cents(1250),
                kind: .expense,
                payee: "REWE",
                reportingDate: reportingDate
            )
        )
    }
    #expect(try ledger.transactions().isEmpty)
}

@Test func savingIsRefusedWhenTheCategoryIsUnknown() throws {
    let ledger = try Ledger.openInMemory()
    let reportingDate = try #require(ReportingDate(iso8601: "2026-11-02"))

    #expect(throws: RecordEntryError.unknownCategory) {
        try ledger.record(
            EntryDraft(
                amount: Cents(1250),
                kind: .expense,
                payee: "REWE",
                reportingDate: reportingDate,
                categoryID: Category.ID(rawValue: UUID())
            )
        )
    }
    #expect(try ledger.transactions().isEmpty)
}

@Test func savingIsRefusedUntilEveryRequiredFieldIsSet() throws {
    let ledger = try Ledger.openInMemory()

    #expect(throws: RecordEntryError.incomplete([
        .amount,
        .kind,
        .payee,
        .reportingDate,
        .category,
    ])) {
        try ledger.record(EntryDraft())
    }
    #expect(try ledger.transactions().isEmpty)
}
