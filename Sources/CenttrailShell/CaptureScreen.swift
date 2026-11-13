import Combine
import Foundation
import Ledger
import SwiftUI

@MainActor
final class CaptureModel: ObservableObject {
    private let ledger: Ledger
    let today: ReportingDate

    @Published var amountText = ""
    @Published var kind: Kind?
    @Published var counterparty = ""
    @Published var reportingDateText = ""
    @Published var categoryID: LedgerCategoryID?
    @Published var categories: [LedgerCategory] = []
    @Published var transactions: [LedgerTransaction] = []
    @Published var spending = Cents(0)
    @Published var message: String?

    init(ledger: Ledger, today: ReportingDate) throws {
        self.ledger = ledger
        self.today = today
        try reload()
    }

    static func openDefault() throws -> CaptureModel {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = support.appendingPathComponent("Centtrail", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let ledger = try Ledger.open(at: directory.appendingPathComponent("ledger.sqlite"))
        guard let today = civilDate(Date(), calendar: .current) else {
            throw CalendarDateError()
        }
        return try CaptureModel(ledger: ledger, today: today)
    }

    func useToday() {
        reportingDateText = today.iso8601
    }

    func save() {
        let draft = EntryDraft(
            amount: Cents(euroText: amountText),
            kind: kind,
            counterparty: counterparty,
            reportingDate: ReportingDate(iso8601: reportingDateText),
            categoryID: categoryID
        )
        do {
            _ = try ledger.record(draft)
            amountText = ""
            kind = nil
            counterparty = ""
            reportingDateText = ""
            categoryID = nil
            message = nil
            try reload()
        } catch let error as RecordEntryError {
            message = refusalMessage(error)
        } catch {
            message = error.localizedDescription
        }
    }

    private func reload() throws {
        categories = try ledger.categories()
        transactions = try ledger.transactions()
        switch try ledger.runReport(.currentMonthSpending, today: today) {
        case .spendingTotal(let cents):
            spending = cents
        }
    }
}

struct CaptureScreen: View {
    @ObservedObject var model: CaptureModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("This month", value: euroLabel(model.spending))
                } footer: {
                    Text(monthTitle(model.today))
                }

                Section("New entry") {
                    TextField("Amount", text: $model.amountText, prompt: Text("0.00"))
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    Picker("Kind", selection: $model.kind) {
                        Text("Select").tag(Optional<Kind>.none)
                        Text("Expense").tag(Optional(Kind.expense))
                        Text("Income").tag(Optional(Kind.income))
                    }
                    TextField("Counterparty", text: $model.counterparty, prompt: Text("Who was paid"))
                    HStack {
                        TextField("Reporting date", text: $model.reportingDateText, prompt: Text("YYYY-MM-DD"))
                        Button("Today", action: model.useToday)
                    }
                    Picker("Category", selection: $model.categoryID) {
                        Text("Select").tag(Optional<LedgerCategoryID>.none)
                        ForEach(model.categories) { category in
                            Text(category.name).tag(Optional(category.id))
                        }
                    }
                    if let message = model.message {
                        Text(message)
                            .foregroundStyle(.red)
                    }
                    Button("Save", action: model.save)
                }

                Section("Transactions") {
                    if model.transactions.isEmpty {
                        Text("No transactions yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.transactions) { transaction in
                            TransactionRow(transaction: transaction)
                        }
                    }
                }
            }
            .navigationTitle("Centtrail")
        }
    }
}

public struct CaptureRoot: View {
    @StateObject private var loader = LedgerLoader()

    public init() {}

    public var body: some View {
        if let model = loader.model {
            CaptureScreen(model: model)
        } else if let failure = loader.failure {
            ContentUnavailableView(
                "The ledger could not be opened",
                systemImage: "exclamationmark.triangle",
                description: Text(failure)
            )
        } else {
            ProgressView("Opening the ledger")
        }
    }
}

@MainActor
private final class LedgerLoader: ObservableObject {
    @Published var model: CaptureModel?
    @Published var failure: String?

    init() {
        do {
            model = try CaptureModel.openDefault()
        } catch {
            failure = error.localizedDescription
        }
    }
}

private struct TransactionRow: View {
    let transaction: LedgerTransaction

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.counterparty.name)
                Text("\(transaction.category.name) · \(transaction.reportingDate.iso8601)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(euroLabel(transaction.amount))
                Text(transaction.kind == .expense ? "Expense" : "Income")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct CalendarDateError: Error, LocalizedError {
    var errorDescription: String? { "Today's calendar date could not be read." }
}

private func civilDate(_ date: Date, calendar: Calendar) -> ReportingDate? {
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
    return ReportingDate(year: year, month: month, day: day)
}

private func euroLabel(_ cents: Cents) -> String {
    let euros = cents.value / 100
    let remainder = abs(cents.value % 100)
    return "€\(euros).\(String(format: "%02d", remainder))"
}

private func monthTitle(_ date: ReportingDate) -> String {
    let names = [
        "",
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December",
    ]
    guard names.indices.contains(date.month) else { return date.iso8601 }
    return "\(names[date.month]) \(date.year)"
}

private func refusalMessage(_ error: RecordEntryError) -> String {
    switch error {
    case .incomplete(let fields):
        let ordered: [EntryField] = [.amount, .kind, .counterparty, .reportingDate, .category]
        let missing = ordered.filter(fields.contains).map(fieldName)
        return "Enter \(missing.joined(separator: ", "))."
    case .unknownCategory:
        return "Choose one of the owner's categories."
    }
}

private func fieldName(_ field: EntryField) -> String {
    switch field {
    case .amount: "an amount"
    case .kind: "a kind"
    case .counterparty: "a counterparty"
    case .reportingDate: "a reporting date"
    case .category: "a category"
    }
}
