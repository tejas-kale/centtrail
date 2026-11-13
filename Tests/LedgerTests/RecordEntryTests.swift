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
            payee: "REWE",
            reportingDate: reportingDate,
            categoryID: supermarket.id
        )
    )

    #expect(recorded.amount == Cents(1250))
    #expect(recorded.kind == .expense)
    #expect(recorded.payee.name == "REWE")
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
    #expect(recorded.payee.id != otherRecorded.payee.id)
    #expect(try ledger.transactions().map(\.id) == [recorded.id])
    #expect(try ledger.transactions().map(\.payee.id) == [recorded.payee.id])

    let categoryIDs = try ledger.categories().map(\.id)
    let rereadCategoryIDs = try ledger.categories().map(\.id)
    let otherCategoryIDs = try other.categories().map(\.id)
    #expect(categoryIDs == rereadCategoryIDs)
    #expect(Set(categoryIDs).count == categoryIDs.count)
    #expect(Set(categoryIDs).isDisjoint(with: otherCategoryIDs))
}

@Test func theSamePayeeNameIsOnePayee() throws {
    let ledger = try Ledger.openInMemory()
    let first = try recordExpense(ledger, payee: " REWE ")
    let second = try recordExpense(ledger, payee: "REWE")

    #expect(first.payee.id == second.payee.id)
    #expect(first.payee.name == "REWE")
    #expect(second.payee.name == "REWE")
    #expect(first.id != second.id)
}

private func recordExpense(_ ledger: Ledger, payee: String = "REWE") throws -> Transaction {
    let supermarket = try #require(try ledger.categories().first { $0.name == "Supermarket" })
    let reportingDate = try #require(ReportingDate(iso8601: "2026-11-02"))
    return try ledger.record(
        EntryDraft(
            amount: Cents(1250),
            kind: .expense,
            payee: payee,
            reportingDate: reportingDate,
            categoryID: supermarket.id
        )
    )
}
