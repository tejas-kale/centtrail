import Ledger

/// Decides whether the app's ledger syncs through iCloud. The signed apps name
/// their CloudKit container in Info.plist; anything else (`swift run`, tests)
/// keeps the ledger on this device.
enum LedgerSyncSettings {
    static let containerKey = "CenttrailCloudKitContainer"

    static func syncMode(infoDictionary: [String: Any]) -> Ledger.SyncMode {
        guard let container = infoDictionary[containerKey] as? String, !container.isEmpty else {
            return .disabled
        }
        return .enabled(containerIdentifier: container)
    }
}
