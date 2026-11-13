import Ledger
import Testing

@Test func currentMonthSpendingIsTheHandComputedSumOfExpensesInThatMonth() throws {
    let ledger = try Ledger.openInMemory()
    try record(ledger, cents: 1250, kind: .expense, counterparty: "REWE", date: "2024-03-01", category: "Supermarket")
    try record(ledger, cents: 3400, kind: .expense, counterparty: "Osteria", date: "2024-03-15", category: "Restaurant")
    try record(ledger, cents: 500, kind: .expense, counterparty: "Bolt", date: "2024-02-29", category: "Taxi")
    try record(ledger, cents: 200_000, kind: .income, counterparty: "Acme", date: "2024-03-02", category: "Salary")
    try record(ledger, cents: 999, kind: .expense, counterparty: "DB", date: "2024-04-01", category: "Train")

    let today = try #require(ReportingDate(iso8601: "2024-03-15"))
    let result = try ledger.runReport(.currentMonthSpending, today: today)

    // 1250 + 3400. February, April, and the March salary are outside this total.
    #expect(result == .spendingTotal(SignedCents(4650)))
}

private func record(
    _ ledger: Ledger,
    cents: Int,
    kind: Kind,
    counterparty: String,
    date: String,
    category: String
) throws {
    let categoryID = try #require(try ledger.categories().first { $0.name == category }?.id)
    let reportingDate = try #require(ReportingDate(iso8601: date))
    _ = try ledger.record(
        EntryDraft(
            amount: Cents(cents),
            kind: kind,
            counterparty: counterparty,
            reportingDate: reportingDate,
            categoryID: categoryID
        )
    )
}
