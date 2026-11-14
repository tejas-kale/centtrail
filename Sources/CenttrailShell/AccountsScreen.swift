import Ledger
import SwiftUI

struct AccountsScreen: View {
    @ObservedObject var model: CaptureModel
    @State private var newName = ""
    @State private var renaming: Account?
    @State private var renameText = ""
    @State private var message: String?

    var body: some View {
        List {
            if let message { Text(message).foregroundStyle(.red) }
            Section("Add account") {
                TextField("Name", text: $newName)
                Button("Add account") {
                    perform { _ = try model.ledger.addAccount(name: newName); newName = "" }
                }
                .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Section("Accounts") {
                ForEach(model.accounts) { account in
                    HStack {
                        Text(account.name)
                        Spacer()
                        Button("Rename") { renameText = account.name; renaming = account }
                        Button("Remove", role: .destructive) { perform { try model.ledger.removeAccount(id: account.id) } }
                    }
                }
            }
        }
        .navigationTitle("Accounts")
        .sheet(item: $renaming) { account in
            NavigationStack {
                Form {
                    if let message { Text(message).foregroundStyle(.red) }
                    TextField("Name", text: $renameText)
                }
                    .navigationTitle("Rename account")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { renaming = nil } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") { perform { _ = try model.ledger.renameAccount(id: account.id, to: renameText); renaming = nil } }
                        }
                    }
            }
        }
    }

    private func perform(_ action: () throws -> Void) {
        do { try action(); try model.reload(); message = nil }
        catch { message = error.localizedDescription }
    }
}
