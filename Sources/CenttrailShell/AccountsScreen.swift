import Ledger
import SwiftUI

struct AccountsScreen: View {
    @ObservedObject var model: CaptureModel
    @State private var draft: AccountDraft?
    @State private var pendingRemoval: Account?
    @State private var message: String?

    var body: some View {
        List {
            if let message {
                Section {
                    ErrorBanner(message: message) { self.message = nil }
                }
                .ayuRows()
            }
            Section {
                if model.accounts.isEmpty {
                    Text("No accounts yet")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.accounts) { account in
                    ReferenceRow(
                        title: account.name,
                        value: account.currency.rawValue,
                        edit: { draft = AccountDraft(editing: account) },
                        remove: { pendingRemoval = account }
                    )
                }
            } footer: {
                Text("A currency can change only while no transactions use the account.")
            }
            .ayuRows()
        }
        .ayuGroupedBackground()
        .navigationTitle("Accounts")
        .safeAreaInset(edge: .bottom) {
            AddItemBar(title: "Add account") { draft = AccountDraft() }
        }
        .sheet(item: $draft) { draft in
            AccountEditor(draft: draft) { saved in
                try saved.save(in: model.ledger)
                try model.reload()
                message = nil
            }
        }
        .confirmationDialog(
            "Remove \(pendingRemoval?.name ?? "account")?",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            titleVisibility: .visible,
            presenting: pendingRemoval
        ) { account in
            Button("Remove account", role: .destructive) { remove(account) }
        } message: { _ in
            Text("Only accounts without transactions can be removed.")
        }
    }

    private func remove(_ account: Account) {
        do {
            try model.ledger.removeAccount(id: account.id)
            try model.reload()
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }
}

private struct AccountEditor: View {
    @State var draft: AccountDraft
    let save: (AccountDraft) throws -> Void
    @State private var message: String?
    @FocusState private var isNameFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        EditorSheet(title: draft.isEditing ? "Edit account" : "New account", canSave: !draft.name.isBlank) {
            do {
                try save(draft)
                dismiss()
            } catch {
                message = error.localizedDescription
            }
        } content: {
            Section {
                TextField("Name", text: $draft.name, prompt: Text("e.g. N26"))
                    .focused($isNameFocused)
                Picker("Currency", selection: $draft.currency) {
                    ForEach(Currency.allCases, id: \.self) { currency in
                        Text(currency.rawValue).tag(currency)
                    }
                }
            }
            .ayuRows()
            if let message {
                Section { ErrorBanner(message: message) }
                    .ayuRows()
            }
        }
        .onAppear { isNameFocused = !draft.isEditing }
    }
}
