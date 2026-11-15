import AppIntents
import Foundation
import Interpreter
import Ledger

@MainActor
final class CenttrailEntryTrigger {
    static let shared = CenttrailEntryTrigger()

    private var hasPendingNewEntry = false

    private init() {}

    func triggerNewEntry() {
        hasPendingNewEntry = true
        NotificationCenter.default.post(name: .centtrailNewEntry, object: nil)
    }

    func consumePendingNewEntry() -> Bool {
        guard hasPendingNewEntry else { return false }
        hasPendingNewEntry = false
        return true
    }
}

public struct AddExpenseIntent: AppIntent {
    public static let title: LocalizedStringResource = "Add expense"
    public static let description = IntentDescription(
        "Opens an editable Centtrail entry form. Nothing is saved until you tap Save."
    )
    public static let openAppWhenRun = true

    public init() {}

    public func perform() async throws -> some IntentResult {
        await MainActor.run {
            CenttrailEntryTrigger.shared.triggerNewEntry()
        }
        return .result()
    }
}

public struct RecordEntryIntent: AppIntent {
    public static let title: LocalizedStringResource = "Record entry"
    public static let description = IntentDescription(
        "Records a spoken Centtrail entry without opening the app."
    )
    public static let openAppWhenRun = false

    @Parameter(
        title: "Entry",
        requestValueDialog: IntentDialog("What would you like to record?")
    )
    public var text: String

    public init() {}

    public init(text: String) {
        self.text = text
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let (ledger, today) = try CaptureModel.openDefaultLedger()
        let dialog = try await Self.record(text, in: ledger, today: today)
        return .result(dialog: IntentDialog("\(dialog)"))
    }

    static func record(_ text: String, in ledger: Ledger, today: ReportingDate) async throws -> String {
        let defaultAccountID = try ledger.mostRecentlyUsedAccount()?.id ?? ledger.accounts().first?.id
        let defaults = EntryDraft(kind: .expense, reportingDate: today, accountID: defaultAccountID)
        let interpretation = try await Interpreter(ledger: ledger, today: today)
            .interpretCaptureAsync(text, defaults: defaults)
        guard interpretation.parsed.amount != nil else {
            return "Could not parse an amount from \"\(text)\". Nothing was saved."
        }
        let completion = DraftCompletion(
            draft: interpretation.draft,
            missingFields: interpretation.missingFields
        )
        do {
            let saved = try ledger.record(completion)
            let formattedAmount = formatEuro(saved.amount.value)
            let payeeName = saved.payee?.name ?? "Unknown"
            if saved.needsReview {
                return "Saved \(formattedAmount) at \(payeeName) to review."
            }
            let categoryName = saved.category?.name ?? "Uncategorised"
            return "Saved \(formattedAmount) at \(payeeName) under \(categoryName)."
        } catch RecordEntryError.incomplete(let missing) {
            if missing.contains(.payee) {
                return "Could not find a payee in \"\(text)\". Nothing was saved."
            }
            return "Could not save entry from \"\(text)\". Nothing was saved."
        }
    }
}

public struct CenttrailShortcuts: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddExpenseIntent(),
            phrases: [
                "Add expense in \(.applicationName)",
                "Record an entry in \(.applicationName)",
            ],
            shortTitle: "Add expense",
            systemImageName: "plus"
        )
        AppShortcut(
            intent: RecordEntryIntent(),
            phrases: [
                "Quick entry in \(.applicationName)",
                "Log expense in \(.applicationName)",
            ],
            shortTitle: "Record entry",
            systemImageName: "mic.fill"
        )
    }
}

/// Exposes package intents and shortcuts to each signed app host.
public struct CenttrailAppIntentsPackage: AppIntentsPackage {}
