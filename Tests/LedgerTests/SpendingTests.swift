import Ledger
import Testing

@Test func currentMonthSpendingIsTheHandComputedSumOfExpensesInThatMonth() throws {
    let ledger = try Ledger.openInMemory()
    try record(ledger, cents: 1250, kind: .expense, payee: "REWE", date: "2024-03-01", category: "Supermarket")
    try record(ledger, cents: 3400, kind: .expense, payee: "Osteria", date: "2024-03-15", category: "Restaurant")
    try record(ledger, cents: 500, kind: .expense, payee: "Bolt", date: "2024-02-29", category: "Taxi")
    try record(ledger, cents: 200_000, kind: .income, payee: "Acme", date: "2024-03-02", category: "Salary")
    try record(ledger, cents: 999, kind: .expense, payee: "DB", date: "2024-04-01", category: "Train")

    let today = try #require(ReportingDate(iso8601: "2024-03-15"))
    let result = try ledger.runReport(.currentMonthSpending, today: today)

    // 1250 + 3400. February, April, and the March salary are outside this total.
    #expect(result == .spendingTotal(SignedCents(4650)))
}

private func record(
    _ ledger: Ledger,
    cents: Int,
    kind: Kind,
    payee: String,
    date: String,
    category: String
) throws {
    let categoryID = try #require(try ledger.categories().first { $0.name == category }?.id)
    let reportingDate = try #require(ReportingDate(iso8601: date))
    _ = try ledger.record(
        EntryDraft(
            amount: Cents(cents),
            kind: kind,
            payee: payee,
            reportingDate: reportingDate,
            categoryID: categoryID,
            accountID: try ledger.accounts()[0].id
        )
    )
}
