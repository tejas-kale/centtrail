import Ledger
import SwiftUI

struct BudgetsScreen: View {
    @ObservedObject var model: CaptureModel
    @State private var editingCategory: LedgerCategory?
    @State private var amountText = ""
    @State private var currency: Currency = .eur
    @State private var message: String?

    private var spendingCategories: [LedgerCategory] {
        model.categories.filter(\.countsAsSpending)
    }

    private var budgetsByCategory: [LedgerCategoryID: CategoryBudget] {
        Dictionary(uniqueKeysWithValues: model.budgets.map { ($0.category.id, $0) })
    }

    var body: some View {
        List {
            if let message, editingCategory == nil {
                Section {
                    ErrorBanner(message: message) { self.message = nil }
                }
                .ayuRows()
            }
            Section {
                ForEach(spendingCategories) { category in
                    BudgetRow(
                        category: category,
                        budget: budgetsByCategory[category.id],
                        edit: { edit(category) },
                        remove: { removeBudget(for: category) }
                    )
                }
            } footer: {
                Text("Home shows a gauge for each category with a monthly budget.")
            }
            .ayuRows()
        }
        .ayuGroupedBackground()
        .navigationTitle("Budgets")
        .sheet(item: $editingCategory) { category in
            EditorSheet(title: category.name, canSave: !amountText.isBlank) {
                saveBudget(for: category)
            } content: {
                Section {
                    TextField("Monthly budget", text: $amountText, prompt: Text("0.00"))
                        .monospacedDigit()
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    Picker("Currency", selection: $currency) {
                        ForEach(Currency.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                } header: {
                    Text("Monthly budget")
                }
                .ayuRows()
                if let message {
                    Section { ErrorBanner(message: message) }
                        .ayuRows()
                }
            }
        }
    }

    private func edit(_ category: LedgerCategory) {
        if let existing = budgetsByCategory[category.id] {
            amountText = String(format: "%.2f", Double(existing.amount.value) / 100.0)
            currency = existing.currency
        } else {
            amountText = ""
            currency = .eur
        }
        message = nil
        editingCategory = category
    }

    private func saveBudget(for category: LedgerCategory) {
        guard let amount = Cents(euroText: amountText), amount.value > 0 else {
            message = "Enter a budget amount greater than zero."
            return
        }
        do {
            _ = try model.ledger.setBudget(categoryID: category.id, amount: amount, currency: currency)
            try model.reload()
            editingCategory = nil
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }

    private func removeBudget(for category: LedgerCategory) {
        do {
            try model.ledger.removeBudget(categoryID: category.id)
            try model.reload()
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }
}

private struct BudgetRow: View {
    let category: LedgerCategory
    let budget: CategoryBudget?
    let edit: () -> Void
    let remove: () -> Void

    var body: some View {
        Button(action: edit) {
            HStack {
                Text(category.name)
                Spacer()
                if let budget {
                    Text(formatAmount(budget.amount.value, currency: budget.currency))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                } else {
                    Text("Not set")
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(budget == nil ? "Sets a monthly budget" : "Edits the monthly budget")
        .swipeActions {
            if budget != nil {
                Button(action: remove) {
                    Label("Remove budget", systemImage: "trash")
                }
                .tint(AyuStyle(role: .error))
            }
        }
        .contextMenu {
            Button(budget == nil ? "Set budget" : "Edit budget", systemImage: "pencil", action: edit)
            if budget != nil {
                Button("Remove budget", systemImage: "trash", role: .destructive, action: remove)
            }
        }
    }
}
