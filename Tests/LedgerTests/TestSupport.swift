import Ledger
import Testing

func namedCategory(_ ledger: Ledger, _ name: String) throws -> Category {
    try #require(try ledger.categories().first { $0.name == name })
}

func recordEntry(_ ledger: Ledger, cents: Int, kind: Kind, payee: String, date: String, category name: String) throws -> Transaction {
    try ledger.record(EntryDraft(
        amount: Cents(cents),
        kind: kind,
        payee: payee,
        reportingDate: ReportingDate(iso8601: date),
        categoryID: try namedCategory(ledger, name).id
    ))
}

func spendingTotal(_ ledger: Ledger, from start: String, through end: String, today: ReportingDate) throws -> Int {
    let result = try ledger.runReport(
        .total(ReportQuery(
            measure: .spending,
            range: DateRange(
                start: try #require(ReportingDate(iso8601: start)),
                end: try #require(ReportingDate(iso8601: end))
            )
        )),
        today: today
    )
    guard case .total(let cents, _) = result else {
        Issue.record("Expected a total")
        return -1
    }
    return cents
}
