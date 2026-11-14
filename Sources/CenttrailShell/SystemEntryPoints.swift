import AppIntents
import Foundation

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
    }
}

/// Exposes package intents and shortcuts to each signed app host.
public struct CenttrailAppIntentsPackage: AppIntentsPackage {}
