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

struct HostAppIntentsPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [CenttrailAppIntentsPackage.self]
    }
}
