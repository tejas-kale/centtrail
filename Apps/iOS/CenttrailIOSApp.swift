import AppIntents
import CenttrailShell
import SwiftUI

/// iOS host for the shared CenttrailShell screens. Capture, this month's total,
/// and the other tabs all live in that package; this target only opens them.
@main
struct CenttrailIOSApp: App {
    var body: some Scene {
        WindowGroup {
            CaptureRoot()
        }
    }
}

struct HostAppIntentsPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [CenttrailAppIntentsPackage.self]
    }
}
