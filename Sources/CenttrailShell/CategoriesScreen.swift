import Ledger
import SwiftUI

struct CategoriesScreen: View {
    @ObservedObject var model: CaptureModel
    @State private var draft: CategoryDraft?
    @State private var pendingRemoval: LedgerCategory?
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
                if model.categories.isEmpty {
                    Text("No categories yet")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.categories) { category in
                    ReferenceRow(
                        title: category.name,
                        detail: category.countsAsSpending ? nil : "Excluded from spending",
                        edit: { draft = CategoryDraft(editing: category) },
                        remove: { pendingRemoval = category }
                    )
                }
            }
            .ayuRows()
        }
        .ayuGroupedBackground()
        .navigationTitle("Categories")
        .safeAreaInset(edge: .bottom) {
            AddItemBar(title: "Add category") { draft = CategoryDraft() }
        }
        .sheet(item: $draft) { draft in
            CategoryEditor(draft: draft) { saved in
                try saved.save(in: model.ledger)
                try model.reload()
                message = nil
            }
        }
        .confirmationDialog(
            "Remove \(pendingRemoval?.name ?? "category")?",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            titleVisibility: .visible,
            presenting: pendingRemoval
        ) { category in
            Button("Remove category", role: .destructive) { remove(category) }
        } message: { _ in
            Text("Only categories without transactions can be removed.")
        }
        .onAppear(perform: reload)
    }

    private func remove(_ category: LedgerCategory) {
        do {
            try model.ledger.removeCategory(id: category.id)
            try model.reload()
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }

    private func reload() {
        do {
            try model.reload()
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }
}

private struct CategoryEditor: View {
    @State var draft: CategoryDraft
    let save: (CategoryDraft) throws -> Void
    @State private var message: String?
    @FocusState private var isNameFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        EditorSheet(title: draft.isEditing ? "Edit category" : "New category", canSave: !draft.name.isBlank) {
            do {
                try save(draft)
                dismiss()
            } catch {
                message = error.localizedDescription
            }
        } content: {
            Section {
                TextField("Name", text: $draft.name, prompt: Text("e.g. Groceries"))
                    .focused($isNameFocused)
                if !draft.isEditing {
                    Toggle("Counts as spending", isOn: $draft.countsAsSpending)
                }
            } footer: {
                if !draft.isEditing {
                    Text("Turn off for money you move aside, such as savings. It can't be changed later.")
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
