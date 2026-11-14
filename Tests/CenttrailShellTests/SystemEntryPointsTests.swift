import AppIntents
@testable import CenttrailShell
import Foundation
import Ledger
import Testing

@Suite(.serialized)
struct SystemEntryPointsTests {
    @MainActor
    @Test func addExpenseIntentOpensAddSheetAndNeverSavesToLedger() async throws {
        _ = CenttrailEntryTrigger.shared.consumePendingNewEntry()
        let ledger = try Ledger.openInMemory()
        let today = try #require(ReportingDate(iso8601: "2026-11-14"))
        let model = try CaptureModel(ledger: ledger, today: today)
        #expect(model.isPresentingAddSheet == false)

        _ = try await AddExpenseIntent().perform()

        #expect(model.isPresentingAddSheet == true)
        #expect(model.amountText.isEmpty)
        #expect(model.payee.isEmpty)
        #expect(model.kind == .expense)
        #expect(try ledger.transactions().isEmpty)
    }

    @MainActor
    @Test func addExpenseIntentBeforeModelInitializesStillOpensAddSheetOnLaunch() async throws {
        _ = CenttrailEntryTrigger.shared.consumePendingNewEntry()
        let ledger = try Ledger.openInMemory()
        let today = try #require(ReportingDate(iso8601: "2026-11-14"))

        _ = try await AddExpenseIntent().perform()

        let model = try CaptureModel(ledger: ledger, today: today)
        #expect(model.isPresentingAddSheet == true)
        #expect(try ledger.transactions().isEmpty)
    }

    @Test func addExpenseIntentExposesForegroundBehaviorAndAppShortcut() {
        #expect(AddExpenseIntent.openAppWhenRun == true)
        #expect(!CenttrailShortcuts.appShortcuts.isEmpty)
    }

    @MainActor
    @Test func centtrailNewEntryNotificationOpensAddSheetWithoutSaving() throws {
        _ = CenttrailEntryTrigger.shared.consumePendingNewEntry()
        let ledger = try Ledger.openInMemory()
        let today = try #require(ReportingDate(iso8601: "2026-11-14"))
        let model = try CaptureModel(ledger: ledger, today: today)
        #expect(model.isPresentingAddSheet == false)

        NotificationCenter.default.post(name: .centtrailNewEntry, object: nil)

        #expect(model.isPresentingAddSheet == true)
        #expect(try ledger.transactions().isEmpty)
    }
}
