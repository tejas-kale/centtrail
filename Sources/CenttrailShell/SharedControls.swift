import SwiftUI

/// An error line at the top of a list, with an optional dismiss button.
struct ErrorBanner: View {
    let message: String
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.ayuError)
            Spacer(minLength: 0)
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Dismiss")
            }
        }
    }
}

/// The full-width add button pinned under a list of accounts or categories.
struct AddItemBar: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "plus")
        }
        .buttonStyle(.ayuProminent)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
    }
}

/// Toolbar and presentation shared by the add/edit sheets.
struct EditorSheet<Content: View>: View {
    let title: String
    let canSave: Bool
    let save: () -> Void
    @ViewBuilder let content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form { content }
                .ayuGroupedBackground()
                .navigationTitle(title)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save", action: save)
                            .disabled(!canSave)
                    }
                }
        }
        .ayuTheme()
        .presentationDetents([.medium, .large])
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 240)
        #endif
    }
}

extension String {
    var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

/// One account or category: tap, swipe or the context menu to edit; swipe or the
/// context menu to remove.
struct ReferenceRow: View {
    let title: String
    var value: String?
    var detail: String?
    let edit: () -> Void
    let remove: () -> Void

    var body: some View {
        Button(action: edit) { label }
            .buttonStyle(.plain)
            .accessibilityHint("Edits \(title)")
            .swipeActions { swipeButtons }
            .contextMenu { menuButtons }
    }

    private var label: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let value {
                Text(value)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder private var swipeButtons: some View {
        Button(action: remove) {
            Label("Remove", systemImage: "trash")
        }
        .tint(AyuStyle(role: .error))
        Button(action: edit) {
            Label("Edit", systemImage: "pencil")
        }
    }

    @ViewBuilder private var menuButtons: some View {
        Button("Edit", systemImage: "pencil", action: edit)
        Button("Remove", systemImage: "trash", role: .destructive, action: remove)
    }
}
