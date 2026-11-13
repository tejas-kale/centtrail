import AppIntents
import CenttrailShell
import SwiftUI

@main
struct CenttrailMacApp: App {
    var body: some Scene {
        WindowGroup {
            CaptureRoot()
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("New entry") {
                    NotificationCenter.default.post(name: .centtrailNewEntry, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
        }
    }
}

struct CaptureEntryIntent: AppIntent {
    static var title: LocalizedStringResource = "Record an entry"
    static var description = IntentDescription("Opens an editable Centtrail draft. Nothing is saved until you confirm.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            NotificationCenter.default.post(name: .centtrailNewEntry, object: nil)
        }
        return .result()
    }
}

struct CenttrailShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureEntryIntent(),
            phrases: ["Record an entry in \(.applicationName)"],
            shortTitle: "Record an entry",
            systemImageName: "plus"
        )
    }
}
