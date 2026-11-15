import AppIntents
import Foundation

@MainActor
final class CenttrailEntryTrigger {
    struct PendingEntry {
        let startListening: Bool
    }

    static let shared = CenttrailEntryTrigger()

    private var pendingEntry: PendingEntry?

    private init() {}

    func triggerNewEntry(startListening: Bool = false) {
        pendingEntry = PendingEntry(startListening: startListening)
        NotificationCenter.default.post(name: .centtrailNewEntry, object: nil)
    }

    @discardableResult
    func consumePendingNewEntry() -> PendingEntry? {
        defer { pendingEntry = nil }
        return pendingEntry
    }
}

public struct AddExpenseIntent: AppIntent {
    public static let title: LocalizedStringResource = "Add expense"
    public static let description = IntentDescription(
        "Opens the Centtrail capture card in listening mode. Nothing is saved until you tap Save."
    )
    public static let openAppWhenRun = true

    public init() {}

    public func perform() async throws -> some IntentResult {
        await MainActor.run {
            CenttrailEntryTrigger.shared.triggerNewEntry(startListening: true)
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
