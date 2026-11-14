import Interpreter
import Ledger
import Testing

@Test func unsafeAmountsAreRefusedAcrossManualCSVAndGeneratedInput() async throws {
    #expect(Cents(roundedEuros: 1e100) == nil)
    #expect(Cents(roundedEuros: .infinity) == nil)
    #expect(Cents(roundedEuros: .nan) == nil)
    #expect(Cents(roundedEuros: -1) == nil)
    #expect(Cents(roundedEuros: 12.345) == Cents(1235))
    #expect(Cents(euroText: "9223372036854775807") == nil)
    #expect(Cents(euroText: "92233720368547758.08") == nil)
    #expect(Cents(euroText: "92233720368547758.07")?.value == Int.max)
    let ledger = try Ledger.openInMemory()
    let csv = """
    Date,Payee,Category,Amount,Source Account,Source Currency,Target Currency,Exchange Rate
    2026-11-01,REWE,Supermarket,-9223372036854775807,N26,EUR,EUR,1.0
    """
    let rows = try ledger.previewImport(csv)
    guard case .needsCorrection = rows[0].state else { Issue.record("An overflowing CSV amount must need correction"); return }
    let backend = AppleFoundationModelBackend(availabilityProvider: { nil }, reportGenerator: { _, _ in
        GeneratedReportIntent(operation: .search, measure: .spending, amountComparison: .greaterThan, amountEuros: 1e100)
    }, captureGenerator: { _, _ in GeneratedCaptureDraft(amountEuros: 1e100) })
    let interpreter = Interpreter(ledger: ledger, today: try #require(ReportingDate(iso8601: "2026-11-14")), backend: backend)
    guard case .unsupported = try await interpreter.interpretReportAsync("find expenses over a huge amount") else { Issue.record("Unsafe report amount must be refused"); return }
    #expect(try await interpreter.interpretCaptureAsync("huge expense").draft.amount == nil)
}
