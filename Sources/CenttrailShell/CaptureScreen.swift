import Combine
import Foundation
import Interpreter
import Ledger
import SwiftUI

public extension Notification.Name {
    static let centtrailNewEntry = Notification.Name("centtrailNewEntry")
}

@MainActor
final class CaptureModel: ObservableObject {
    let ledger: Ledger
    let today: ReportingDate

    @Published var amountText = ""
    @Published var kind: Kind?
    @Published var payee = ""
    @Published var reportingDateText = ""
    @Published var categoryID: LedgerCategoryID?
    @Published var categories: [LedgerCategory] = []
    @Published var transactions: [LedgerTransaction] = []
    @Published var spendingCents = 0
    @Published var message: String?
    @Published var sentence = ""
    @Published var modelNotice: String?
    private var applyingPrefill = false
    private var categoryChosenManually = false

    init(ledger: Ledger, today: ReportingDate) throws {
        self.ledger = ledger
        self.today = today
        try reload()
        NotificationCenter.default.addObserver(forName: .centtrailNewEntry, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.clearDraft()
            }
        }
    }

    func clearDraft() {
        amountText = ""
        kind = nil
        payee = ""
        reportingDateText = ""
        categoryID = nil
        sentence = ""
        categoryChosenManually = false
        message = nil
    }

    func prefillCategory() {
        guard !categoryChosenManually else { return }
        guard let category = try? ledger.defaultCategory(forPayeeName: payee) else { return }
        applyingPrefill = true
        categoryID = category.id
        applyingPrefill = false
    }

    func noteManualCategory() {
        if !applyingPrefill { categoryChosenManually = true }
    }

    func applySentence() {
        let interpreter = Interpreter(ledger: ledger, today: today, modelUnavailableReason: .modelNotReady)
        modelNotice = "Apple Intelligence is unavailable. The short form stays open, and Centtrail filled what it could from the sentence."
        guard let parsed = try? interpreter.interpretCapture(sentence) else { return }
        if let amount = parsed.draft.amount {
            amountText = String(format: "%d.%02d", amount.value / 100, amount.value % 100)
        }
        kind = parsed.draft.kind
        if let name = parsed.draft.payee { payee = name }
        if let date = parsed.draft.reportingDate { reportingDateText = date.iso8601 }
        applyingPrefill = true
        categoryID = parsed.draft.categoryID
        applyingPrefill = false
        categoryChosenManually = parsed.draft.overridesCategory
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
            payee: payee,
            reportingDate: ReportingDate(iso8601: reportingDateText),
            categoryID: categoryID
        )
        do {
            _ = try ledger.record(draft)
            clearDraft()
            try reload()
        } catch let error as RecordEntryError {
            message = refusalMessage(error)
        } catch {
            message = error.localizedDescription
        }
    }

    func reloadFromOutside() throws {
        try reload()
    }

    private func reload() throws {
        categories = try ledger.categories()
        transactions = try ledger.transactions()
        switch try ledger.runReport(.currentMonthSpending, today: today) {
        case .spendingTotal(let cents):
            spendingCents = cents.value
        default:
            break
        }
    }
}

struct CaptureScreen: View {
    @ObservedObject var model: CaptureModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("This month", value: signedEuro(model.spendingCents))
                } footer: {
                    Text(monthTitle(model.today))
                }

                Section("Sentence") {
                    if let modelNotice = model.modelNotice {
                        Text(modelNotice)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    TextField("20 at Middle Eats yesterday", text: $model.sentence)
                    Button("Fill draft", action: model.applySentence)
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
                        Text("Transfer").tag(Optional(Kind.transfer))
                    }
                    TextField("Payee", text: $model.payee, prompt: Text("Who was paid"))
                        .onChange(of: model.payee) { _, _ in model.prefillCategory() }
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
                    .onChange(of: model.categoryID) { _, _ in model.noteManualCategory() }
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
                            NavigationLink {
                                TransactionDetail(transaction: transaction, ledger: model.ledger)
                            } label: {
                                TransactionRow(transaction: transaction)
                            }
                            .swipeActions {
                                Button("Trash", role: .destructive) {
                                    try? model.ledger.trash(transaction.id, on: model.today)
                                    try? model.reloadFromOutside()
                                }
                            }
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
            TabView {
                CaptureScreen(model: model)
                    .tabItem { Label("Capture", systemImage: "plus") }
                ReportsScreen(model: model)
                    .tabItem { Label("Reports", systemImage: "chart.bar") }
                PeopleScreen(model: model)
                    .tabItem { Label("People", systemImage: "person.2") }
                TrashScreen(model: model)
                    .tabItem { Label("Trash", systemImage: "trash") }
                ImportScreen(model: model)
                    .tabItem { Label("Import", systemImage: "square.and.arrow.down") }
            }
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

struct TransactionRow: View {
    let transaction: LedgerTransaction

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.payee.name)
                Text("\(transaction.category.name) · \(transaction.reportingDate.iso8601)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(signedEuro(transaction.amount.value))
                Text(transaction.kind.rawValue.capitalized)
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

func signedEuro(_ cents: Int) -> String {
    let sign = cents < 0 ? "−" : ""
    let absolute = abs(cents)
    return "\(sign)€\(absolute / 100).\(String(format: "%02d", absolute % 100))"
}

func monthTitle(_ date: ReportingDate) -> String {
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
        let ordered: [EntryField] = [.amount, .kind, .payee, .reportingDate, .category]
        let missing = ordered.filter(fields.contains).map(fieldName)
        return "Enter \(missing.joined(separator: ", "))."
    case .unknownCategory:
        return "Choose one of the owner's categories."
    case .unknownEntry:
        return "That entry could not be found."
    }
}

private func fieldName(_ field: EntryField) -> String {
    switch field {
    case .amount: "an amount"
    case .kind: "a kind"
    case .payee: "a payee"
    case .reportingDate: "a reporting date"
    case .category: "a category"
    }
}
