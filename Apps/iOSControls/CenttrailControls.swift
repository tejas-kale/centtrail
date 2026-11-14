import AppIntents
import CenttrailShell
import SwiftUI
import WidgetKit

@main
struct CenttrailControlWidgetBundle: WidgetBundle {
    var body: some Widget {
        AddExpenseControl()
    }
}

struct AddExpenseControl: ControlWidget {
    static let kind = "com.tejaskale.centtrail.controls.add-expense"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: AddExpenseIntent()) {
                Label("Add expense", systemImage: "plus")
            }
        }
        .displayName("Add expense")
        .description("Opens Centtrail to record a new entry.")
    }
}

struct HostAppIntentsPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [CenttrailAppIntentsPackage.self]
    }
}
