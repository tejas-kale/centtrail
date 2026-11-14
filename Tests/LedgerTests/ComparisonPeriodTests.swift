import Interpreter
import Ledger
import Testing

@Test func explicitComparisonPeriodsAreNeverSilentlyReplaced() async throws {
    let ledger = try Ledger.openInMemory()
    let today = try #require(ReportingDate(iso8601: "2026-11-14"))
    let keyword = Interpreter(ledger: ledger, today: today, backend: KeywordLanguageModelBackend())
    for question in ["spending 2026-01 vs 2026-02", "January spending compared with February", "this year vs last year", "today vs yesterday"] {
        guard case .unsupported(let explanation) = try keyword.interpretReport(question) else { Issue.record("Explicit dates must be refused: \(question)"); continue }
        #expect(explanation.contains("this month"))
    }
    #expect(try keyword.interpretReport("this month vs last month") == .operation(.comparison(measure: .spending, categoryID: nil, payeeName: nil)))
    let generated = AppleFoundationModelBackend(availabilityProvider: { nil }, reportGenerator: { _, _ in
        GeneratedReportIntent(operation: .comparison, measure: .spending, startDate: "2026-01-01", endDate: "2026-02-28")
    })
    let model = Interpreter(ledger: ledger, today: today, backend: generated)
    guard case .unsupported = try await model.interpretReportAsync("compare spending") else { Issue.record("A generated explicit range must not be dropped"); return }
    let omitted = AppleFoundationModelBackend(availabilityProvider: { nil }, reportGenerator: { _, _ in
        GeneratedReportIntent(operation: .comparison, measure: .spending)
    })
    let missingDates = Interpreter(ledger: ledger, today: today, backend: omitted)
    guard case .unsupported = try await missingDates.interpretReportAsync("2026-01 vs 2026-02") else { Issue.record("The model must not erase an explicit period"); return }
}
