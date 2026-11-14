import Combine
import Foundation
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
    @Published var kind: Kind = .expense
    @Published var payee = ""
    @Published var selectedDate: Date
    @Published var categoryID: LedgerCategoryID?
    @Published var accountID: Account.ID?
    @Published var destinationAccountID: Account.ID?
    @Published var accounts: [Account] = []
    @Published var categories: [LedgerCategory] = []
    @Published var payees: [Payee] = []
    @Published private var frequentPayeesByKind: [Kind: [FrequentPayee]] = [:]

    var frequentPayees: [FrequentPayee] {
        frequentPayeesByKind[kind] ?? []
    }
    @Published var transactions: [LedgerTransaction] = []
    @Published var homeSummary: HomeSummary?
    @Published var isPresentingAddSheet = false
    @Published var draftMessage: String?
    @Published var errorMessage: String?

    private var applyingPrefill = false
    private var categoryChosenManually = false
    nonisolated(unsafe) private var newEntryObserver: NSObjectProtocol?
    private var ledgerObservation: LedgerObservation?
    private var reloadScheduled = false

    init(ledger: Ledger, today: ReportingDate) throws {
        self.ledger = ledger
        self.today = today
        self.selectedDate = Self.date(from: today)
        try reload()
        accountID = accounts.first?.id
        newEntryObserver = NotificationCenter.default.addObserver(forName: .centtrailNewEntry, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                _ = CenttrailEntryTrigger.shared.consumePendingNewEntry()
                self.openAddSheet()
            }
        }
        if CenttrailEntryTrigger.shared.consumePendingNewEntry() {
            openAddSheet()
        }
        // Edits pulled in by iCloud sync land in the ledger without passing
        // through this model, so refresh whenever the ledger changes.
        ledgerObservation = ledger.observeChanges { [weak self] in
            Task { @MainActor in self?.scheduleReload() }
        }
    }

    deinit {
        if let newEntryObserver {
            NotificationCenter.default.removeObserver(newEntryObserver)
        }
    }

    func openAddSheet() {
        clearDraft()
        isPresentingAddSheet = true
    }

    func clearDraft() {
        amountText = ""
        kind = .expense
        payee = ""
        selectedDate = Self.date(from: today)
        categoryID = nil
        accountID = accounts.first?.id
        destinationAccountID = accounts.first(where: { $0.name == "India" })?.id
        categoryChosenManually = false
        draftMessage = nil
    }

    func prefillCategory() {
        guard !categoryChosenManually else { return }
        do {
            guard let category = try ledger.defaultCategory(forPayeeName: payee) else { return }
            applyingPrefill = true
            categoryID = category.id
            applyingPrefill = false
        } catch {
            draftMessage = error.localizedDescription
        }
    }

    func selectSuggestedPayee(_ name: String) {
        payee = name
        prefillCategory()
    }

    func selectFrequentPayee(_ suggestion: FrequentPayee) {
        categoryChosenManually = false
        payee = suggestion.payee.name
        categoryID = suggestion.payee.defaultCategory?.id
        accountID = suggestion.lastUsedAccount.id
    }

    func noteManualCategory() {
        if !applyingPrefill {
            categoryChosenManually = true
        }
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
        let ledger = try Ledger.open(
            at: directory.appendingPathComponent("ledger.sqlite"),
            sync: LedgerSyncSettings.syncMode(infoDictionary: Bundle.main.infoDictionary ?? [:])
        )
        guard let today = civilDate(Date(), calendar: .current) else {
            throw CalendarDateError()
        }
        return try CaptureModel(ledger: ledger, today: today)
    }

    @discardableResult
    func save() -> Bool {
        let draft = EntryDraft(
            amount: Cents(euroText: amountText),
            kind: kind,
            payee: payee,
            reportingDate: civilDate(selectedDate, calendar: .current),
            categoryID: kind == .transfer ? nil : categoryID,
            accountID: accountID,
            destinationAccountID: kind == .transfer ? destinationAccountID : nil,
            overridesCategory: categoryChosenManually
        )
        do {
            _ = try ledger.record(draft)
            clearDraft()
            try reload()
            return true
        } catch let error as RecordEntryError {
            draftMessage = refusalMessage(error)
            return false
        } catch {
            draftMessage = error.localizedDescription
            return false
        }
    }

    func trash(_ transaction: LedgerTransaction) {
        do {
            try ledger.trash(transaction.id, on: today)
            try reload()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateCategory(_ newCategoryID: LedgerCategoryID, for transactionID: LedgerTransaction.ID) {
        do {
            try ledger.setCategory(newCategoryID, for: transactionID)
            try reload()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func scheduleReload() {
        guard !reloadScheduled else { return }
        reloadScheduled = true
        Task { @MainActor in
            reloadScheduled = false
            do {
                try reload()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func reloadFromOutside() throws {
        try reload()
    }

    private func reload() throws {
        try ledger.purgeExpiredTrash(today: today)
        accounts = try ledger.accounts()
        categories = try ledger.categories()
        payees = try ledger.payees()
        frequentPayeesByKind = [
            .expense: try ledger.frequentPayees(kind: .expense),
            .income: try ledger.frequentPayees(kind: .income),
        ]
        transactions = try ledger.transactions()
        homeSummary = try ledger.homeSummary(on: today)
    }

    private static func date(from reportingDate: ReportingDate) -> Date {
        var components = DateComponents()
        components.year = reportingDate.year
        components.month = reportingDate.month
        components.day = reportingDate.day
        return Calendar.current.date(from: components) ?? Date()
    }
}

public struct CaptureRoot: View {
    @StateObject private var loader = LedgerLoader()

    public init() {}

    public var body: some View {
        if let model = loader.model {
            AppTabShell(model: model)
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

private struct AppTabShell: View {
    @ObservedObject var model: CaptureModel

    var body: some View {
        TabView {
            Tab("Home", systemImage: "house") {
                HomeScreen(model: model)
            }
            Tab("Ask", systemImage: "sparkles") {
                AskScreen(model: model)
            }
            Tab("Settings", systemImage: "gearshape") {
                SettingsScreen(model: model)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .sheet(isPresented: $model.isPresentingAddSheet) {
            AddEntrySheet(model: model)
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
                Text(transaction.payee?.name ?? "Transfer")
                Text("\(transaction.account.name)\(transaction.destinationAccount.map { " → \($0.name)" } ?? "") · \(transaction.reportingDate.iso8601)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(formatEuro(transaction.amount.value))
                .foregroundStyle(transaction.kind == .income ? .green : .primary)
                .monospacedDigit()
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

func formatEuro(_ cents: Int) -> String {
    (Decimal(cents) / 100).formatted(.currency(code: "EUR"))
}

func formatSignedEuro(_ cents: Int) -> String {
    let sign = cents > 0 ? "+" : (cents < 0 ? "−" : "")
    let absFormatted = (Decimal(abs(cents)) / 100).formatted(.currency(code: "EUR"))
    return "\(sign)\(absFormatted)"
}

func formatPercentageChange(_ percentage: Double) -> String {
    let sign = percentage > 0 ? "+" : ""
    return "\(sign)\(percentage.formatted(.number.precision(.fractionLength(0...1))))%"
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

func monthName(_ date: ReportingDate) -> String {
    let names = [
        "",
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December",
    ]
    guard names.indices.contains(date.month) else { return date.iso8601 }
    return names[date.month]
}

func shortRangeLabel(_ range: DateRange) -> String {
    let shortMonths = [
        "",
        "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    ]
    let month = shortMonths.indices.contains(range.end.month) ? shortMonths[range.end.month] : "\(range.end.month)"
    return "\(range.start.day)–\(range.end.day) \(month)"
}

private func refusalMessage(_ error: RecordEntryError) -> String {
    switch error {
    case .incomplete(let fields):
        let ordered: [EntryField] = [.amount, .kind, .payee, .reportingDate, .category, .account, .destinationAccount]
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
    case .account: "an account"
    case .destinationAccount: "a destination account"
    }
}
