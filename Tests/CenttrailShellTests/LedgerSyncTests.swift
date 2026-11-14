@testable import CenttrailShell
import Foundation
import Ledger
import Testing

@Test func appSyncsOnlyWhenItsInfoPlistNamesACloudKitContainer() {
    #expect(LedgerSyncSettings.syncMode(infoDictionary: [:]) == .disabled)
    #expect(LedgerSyncSettings.syncMode(infoDictionary: ["CenttrailCloudKitContainer": ""]) == .disabled)
    #expect(
        LedgerSyncSettings.syncMode(infoDictionary: ["CenttrailCloudKitContainer": "iCloud.com.tejaskale.centtrail"])
            == .enabled(containerIdentifier: "iCloud.com.tejaskale.centtrail")
    )
}

// Lives in SystemEntryPointsTests so it runs serialized with the other tests
// that build a CaptureModel: each one consumes the shared entry trigger.
extension SystemEntryPointsTests {
    @MainActor
    @Test func openScreensRefreshWhenTheLedgerChangesFromElsewhere() async throws {
        let ledger = try Ledger.openInMemory()
        let today = try #require(ReportingDate(iso8601: "2026-11-14"))
        let model = try CaptureModel(ledger: ledger, today: today)
        #expect(model.transactions.isEmpty)

        // Stands in for a transaction pulled in by iCloud sync from the other device.
        let supermarket = try #require(try ledger.categories().first { $0.name == "Supermarket" })
        _ = try ledger.record(EntryDraft(
            amount: Cents(euroText: "12.50"),
            kind: .expense,
            payee: "REWE",
            reportingDate: today,
            categoryID: supermarket.id,
            accountID: try ledger.accounts()[0].id
        ))

        for _ in 0..<100 where model.transactions.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.transactions.map(\.payee!.name) == ["REWE"])
        #expect(model.homeSummary?.currentSpendingCents == 1250)
    }
}
