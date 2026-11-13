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

@Test func everyRecordHasAGloballyUniqueStableIdentity() throws {
    let ledger = try Ledger.openInMemory()
    let other = try Ledger.openInMemory()
    let recorded = try recordExpense(ledger)
    let otherRecorded = try recordExpense(other)

    #expect(recorded.id != otherRecorded.id)
    #expect(recorded.counterparty.id != otherRecorded.counterparty.id)
    #expect(try ledger.transactions().map(\.id) == [recorded.id])
    #expect(try ledger.transactions().map(\.counterparty.id) == [recorded.counterparty.id])

    let categoryIDs = try ledger.categories().map(\.id)
    let rereadCategoryIDs = try ledger.categories().map(\.id)
    let otherCategoryIDs = try other.categories().map(\.id)
    #expect(categoryIDs == rereadCategoryIDs)
    #expect(Set(categoryIDs).count == categoryIDs.count)
    #expect(Set(categoryIDs).isDisjoint(with: otherCategoryIDs))
}

@Test func theSameCounterpartyNameIsOneCounterparty() throws {
    let ledger = try Ledger.openInMemory()
    let first = try recordExpense(ledger, counterparty: " REWE ")
    let second = try recordExpense(ledger, counterparty: "REWE")

    #expect(first.counterparty.id == second.counterparty.id)
    #expect(first.counterparty.name == "REWE")
    #expect(second.counterparty.name == "REWE")
    #expect(first.id != second.id)
}

private func recordExpense(_ ledger: Ledger, counterparty: String = "REWE") throws -> Transaction {
    let supermarket = try #require(try ledger.categories().first { $0.name == "Supermarket" })
    let reportingDate = try #require(ReportingDate(iso8601: "2026-11-02"))
    return try ledger.record(
        EntryDraft(
            amount: Cents(1250),
            kind: .expense,
            counterparty: counterparty,
            reportingDate: reportingDate,
            categoryID: supermarket.id
        )
    )
}
