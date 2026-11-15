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

    @Test func recordEntryIntentNeverOpensAppAndIsRegisteredInAppShortcuts() {
        #expect(RecordEntryIntent.openAppWhenRun == false)
        #expect(CenttrailShortcuts.appShortcuts.count >= 2)
    }

    @Test func recordEntryIntentSavesKnownPayeeAndConfirmsDetails() async throws {
        let ledger = try Ledger.openInMemory()
        let accounts = try ledger.accounts()
        let supermarket = try #require(try ledger.categories().first { $0.name == "Supermarket" })
        let nov01 = try #require(ReportingDate(iso8601: "2026-11-01"))
        let today = try #require(ReportingDate(iso8601: "2026-11-15"))
        _ = try ledger.record(EntryDraft(
            amount: Cents(500),
            kind: .expense,
            payee: "Lidl",
            reportingDate: nov01,
            categoryID: supermarket.id,
            accountID: accounts[0].id
        ))

        let dialog = try await RecordEntryIntent.record("12.50 Lidl", in: ledger, today: today)

        let transactions = try ledger.transactions()
        #expect(transactions.count == 2)
        let saved = transactions[0]
        #expect(saved.needsReview == false)
        #expect(saved.amount == Cents(1250))
        #expect(saved.payee?.name == "Lidl")
        #expect(saved.category == supermarket)
        #expect(dialog.contains("€") || dialog.contains("EUR"))
        #expect(dialog.contains("12"))
        #expect(dialog.contains("Lidl"))
        #expect(dialog.contains("Supermarket"))
    }

    @Test func recordEntryIntentSavesNewPayeeToReviewAndSaysToReview() async throws {
        let ledger = try Ledger.openInMemory()
        let today = try #require(ReportingDate(iso8601: "2026-11-15"))

        let dialog = try await RecordEntryIntent.record("7.50 Bakery", in: ledger, today: today)

        let inbox = try ledger.reviewInbox()
        #expect(inbox.count == 1)
        #expect(inbox[0].amount == Cents(750))
        #expect(inbox[0].payee?.name == "Bakery")
        #expect(dialog.contains("€") || dialog.contains("EUR"))
        #expect(dialog.contains("7"))
        #expect(dialog.contains("Bakery"))
        #expect(dialog.contains("to review"))
    }

    @Test func recordEntryIntentWithUnparseableAmountSavesNothingAndSaysSo() async throws {
        let ledger = try Ledger.openInMemory()
        let today = try #require(ReportingDate(iso8601: "2026-11-15"))

        let dialog = try await RecordEntryIntent.record("coffee at Lidl", in: ledger, today: today)

        #expect(try ledger.transactions().isEmpty)
        #expect(try ledger.reviewInbox().isEmpty)
        #expect(dialog.contains("Nothing was saved"))
    }
}
