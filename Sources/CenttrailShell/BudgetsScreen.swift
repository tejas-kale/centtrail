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
            if let message {
                Text(message)
                    .foregroundStyle(.red)
            }
            ForEach(spendingCategories) { category in
                let existing = budgetsByCategory[category.id]
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.name)
                        if let existing {
                            Text(formatAmount(existing.amount.value, currency: existing.currency))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button(existing == nil ? "Set" : "Edit") {
                        editingCategory = category
                        if let existing {
                            amountText = String(format: "%.2f", Double(existing.amount.value) / 100.0)
                            currency = existing.currency
                        } else {
                            amountText = ""
                            currency = .eur
                        }
                        message = nil
                    }
                    .buttonStyle(.borderless)
                    if existing != nil {
                        Button("Remove", role: .destructive) {
                            removeBudget(for: category)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
        .navigationTitle("Budgets")
        .sheet(item: $editingCategory) { category in
            NavigationStack {
                Form {
                    if let message {
                        Text(message)
                            .foregroundStyle(.red)
                    }
                    TextField("Monthly budget", text: $amountText)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    Picker("Currency", selection: $currency) {
                        ForEach(Currency.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                }
                .navigationTitle(category.name)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { editingCategory = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { saveBudget(for: category) }
                    }
                }
            }
        }
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
