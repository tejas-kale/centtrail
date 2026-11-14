import Ledger
import SwiftUI

struct HomeScreen: View {
    @ObservedObject var model: CaptureModel

    private var recentTransactions: [LedgerTransaction] {
        Array(model.transactions.prefix(5))
    }

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage = model.errorMessage {
                    Section {
                        HStack {
                            Text(errorMessage)
                                .foregroundStyle(.red)
                            Spacer()
                            Button("Dismiss") {
                                model.errorMessage = nil
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }

                if let summary = model.homeSummary {
                    Section {
                        HomeSummaryCard(summary: summary, today: model.today)
                    }
                }

                Section("Recent transactions") {
                    if recentTransactions.isEmpty {
                        Text("No transactions yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(recentTransactions) { transaction in
                            NavigationLink {
                                TransactionDetail(model: model, transaction: transaction)
                            } label: {
                                TransactionRow(transaction: transaction)
                            }
                            .swipeActions {
                                Button("Trash", role: .destructive) {
                                    model.trash(transaction)
                                }
                            }
                        }
                        NavigationLink("See all") {
                            AllTransactionsScreen(model: model)
                        }
                    }
                }
            }
            .navigationTitle("Home")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        model.openAddSheet()
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Button {
                    model.openAddSheet()
                } label: {
                    Image(systemName: "plus")
                        .font(.title2.weight(.semibold))
                        .padding(16)
                }
                .buttonStyle(.borderedProminent)
                .clipShape(Circle())
                .shadow(radius: 4, y: 2)
                .padding(20)
                .accessibilityLabel("Add transaction")
            }
        }
    }
}

private struct HomeSummaryCard: View {
    let summary: HomeSummary
    let today: ReportingDate

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(monthTitle(today))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(formatEuro(summary.currentSpendingCents))
                .font(.largeTitle.bold())
                .monospacedDigit()

            HStack(spacing: 6) {
                Text("\(shortRangeLabel(summary.currentMonthRange)) vs \(shortRangeLabel(summary.previousSameDaysRange))")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatSignedEuro(summary.changeCents))
                    .fontWeight(.medium)
                    .monospacedDigit()
                if let percentage = summary.percentageChange {
                    Text("(\(formatPercentageChange(percentage)))")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .font(.subheadline)

            Text("\(monthName(summary.previousFullMonthRange.start)) total: \(formatEuro(summary.previousFullMonthSpendingCents))")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if summary.unequalLengths {
                Text("Unequal month lengths: \(summary.currentMonthRange.end.day) days vs \(summary.previousSameDaysRange.end.day) days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct AllTransactionsScreen: View {
    @ObservedObject var model: CaptureModel
    @State private var searchText = ""

    private var filteredTransactions: [LedgerTransaction] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return model.transactions }
        return model.transactions.filter { tx in
            tx.payee.name.localizedCaseInsensitiveContains(query)
                || tx.category.name.localizedCaseInsensitiveContains(query)
                || (tx.note?.localizedCaseInsensitiveContains(query) ?? false)
                || formatEuro(tx.amount.value).localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        List {
            if let errorMessage = model.errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            if filteredTransactions.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                ForEach(filteredTransactions) { transaction in
                    NavigationLink {
                        TransactionDetail(model: model, transaction: transaction)
                    } label: {
                        TransactionRow(transaction: transaction)
                    }
                    .swipeActions {
                        Button("Trash", role: .destructive) {
                            model.trash(transaction)
                        }
                    }
                }
            }
        }
        .navigationTitle("All transactions")
        .searchable(text: $searchText, prompt: "Search payee, category, or note")
    }
}

struct AddEntrySheet: View {
    @ObservedObject var model: CaptureModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isAmountFocused: Bool

    private var payeeSuggestions: [Payee] {
        let query = model.payee.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return Array(
            model.payees
                .filter {
                    $0.name.localizedCaseInsensitiveContains(query)
                        && $0.name.caseInsensitiveCompare(query) != .orderedSame
                }
                .prefix(5)
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Kind", selection: $model.kind) {
                        Text("Expense").tag(Kind.expense)
                        Text("Income").tag(Kind.income)
                    }
                    .pickerStyle(.segmented)

                    TextField("Amount", text: $model.amountText, prompt: Text("0.00"))
                        .focused($isAmountFocused)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                }

                Section {
                    TextField("Payee", text: $model.payee, prompt: Text("Who was paid"))
                        .onChange(of: model.payee) { _, _ in
                            model.prefillCategory()
                        }

                    if !payeeSuggestions.isEmpty {
                        ForEach(payeeSuggestions) { suggestion in
                            Button {
                                model.selectSuggestedPayee(suggestion.name)
                            } label: {
                                HStack {
                                    Text(suggestion.name)
                                    Spacer()
                                    if let defaultCategory = suggestion.defaultCategory {
                                        Text(defaultCategory.name)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Picker("Category", selection: $model.categoryID) {
                        Text("Select").tag(Optional<LedgerCategoryID>.none)
                        ForEach(model.categories) { category in
                            Text(category.name).tag(Optional(category.id))
                        }
                    }
                    .onChange(of: model.categoryID) { _, _ in
                        model.noteManualCategory()
                    }

                    DatePicker("Date", selection: $model.selectedDate, displayedComponents: .date)
                }

                if let message = model.draftMessage {
                    Section {
                        Text(message)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("New transaction")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if model.save() {
                            dismiss()
                        }
                    }
                }
            }
            .onAppear {
                isAmountFocused = true
            }
        }
    }
}

struct TransactionDetail: View {
    @ObservedObject var model: CaptureModel
    let transaction: LedgerTransaction
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategoryID: LedgerCategoryID

    init(model: CaptureModel, transaction: LedgerTransaction) {
        self.model = model
        self.transaction = transaction
        self._selectedCategoryID = State(initialValue: transaction.category.id)
    }

    var body: some View {
        Form {
            if let errorMessage = model.errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            Section {
                LabeledContent("Amount") {
                    Text(formatEuro(transaction.amount.value))
                        .foregroundStyle(transaction.kind == .income ? .green : .primary)
                        .monospacedDigit()
                }
                LabeledContent("Kind", value: transaction.kind.rawValue.capitalized)
                LabeledContent("Payee", value: transaction.payee.name)
                Picker("Category", selection: $selectedCategoryID) {
                    ForEach(model.categories) { category in
                        Text(category.name).tag(category.id)
                    }
                }
                .onChange(of: selectedCategoryID) { _, newValue in
                    guard newValue != transaction.category.id else { return }
                    model.updateCategory(newValue, for: transaction.id)
                }
                LabeledContent("Reporting date", value: transaction.reportingDate.iso8601)
                if let note = transaction.note, !note.isEmpty {
                    LabeledContent("Note", value: note)
                }
            }

            Section {
                Button("Move to Trash", role: .destructive) {
                    model.trash(transaction)
                    if model.errorMessage == nil {
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle(transaction.payee.name)
    }
}

struct AskScreen: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Ask",
                systemImage: "sparkles",
                description: Text("Ask questions about your spending in plain words. Coming soon.")
            )
            .navigationTitle("Ask")
        }
    }
}

struct SettingsScreen: View {
    @ObservedObject var model: CaptureModel

    var body: some View {
        NavigationStack {
            List {
                NavigationLink("Categories") {
                    CategoriesScreen(model: model)
                }
                NavigationLink("Payees") {
                    PeopleScreen(model: model)
                }
                NavigationLink("Recently deleted") {
                    TrashScreen(model: model)
                }
                NavigationLink("Import CSV") {
                    ImportScreen(model: model)
                }
            }
            .navigationTitle("Settings")
        }
    }
}

struct CategoriesScreen: View {
    @ObservedObject var model: CaptureModel
    @State private var newName = ""
    @State private var countsAsSpending = true
    @State private var renamingCategory: LedgerCategory?
    @State private var renameText = ""
    @State private var message: String?

    var body: some View {
        Form {
            if let message {
                Section {
                    Text(message)
                        .foregroundStyle(.red)
                }
            }
            Section("Add category") {
                TextField("Category name", text: $newName)
                Toggle("Counts as spending", isOn: $countsAsSpending)
                Button("Add category", action: addCategory)
            }
            Section("Categories") {
                ForEach(model.categories) { category in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(category.name)
                            if !category.countsAsSpending {
                                Text("Excluded from spending")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button("Rename") {
                            renameText = category.name
                            renamingCategory = category
                        }
                        .buttonStyle(.borderless)
                        Button("Remove", role: .destructive) {
                            removeCategory(category)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
        .navigationTitle("Categories")
        .sheet(item: $renamingCategory) { category in
            NavigationStack {
                Form {
                    TextField("Category name", text: $renameText)
                }
                .navigationTitle("Rename \(category.name)")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            renamingCategory = nil
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            saveRename(category)
                        }
                    }
                }
            }
        }
        .onAppear(perform: reload)
    }

    private func addCategory() {
        do {
            _ = try model.ledger.addCategory(name: newName, countsAsSpending: countsAsSpending)
            newName = ""
            countsAsSpending = true
            message = nil
            try model.reloadFromOutside()
        } catch {
            message = error.localizedDescription
        }
    }

    private func saveRename(_ category: LedgerCategory) {
        do {
            _ = try model.ledger.renameCategory(id: category.id, to: renameText)
            renamingCategory = nil
            message = nil
            try model.reloadFromOutside()
        } catch {
            renamingCategory = nil
            message = error.localizedDescription
        }
    }

    private func removeCategory(_ category: LedgerCategory) {
        do {
            try model.ledger.removeCategory(id: category.id)
            message = nil
            try model.reloadFromOutside()
        } catch {
            message = error.localizedDescription
        }
    }

    private func reload() {
        do {
            try model.reloadFromOutside()
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }
}

struct PeopleScreen: View {
    @ObservedObject var model: CaptureModel
    @State private var people: [Payee] = []
    @State private var aliasName = ""
    @State private var aliasTarget: Payee.ID?
    @State private var message: String?

    var body: some View {
        Form {
            if let message {
                Section {
                    Text(message)
                        .foregroundStyle(.red)
                }
            }
            Section("Payees") {
                ForEach(people) { person in
                    Picker(person.name, selection: binding(for: person)) {
                        Text("None").tag(Optional<LedgerCategoryID>.none)
                        ForEach(model.categories) { category in
                            Text(category.name).tag(Optional(category.id))
                        }
                    }
                }
            }
            Section("Confirm alias") {
                TextField("Alias name", text: $aliasName)
                Picker("Payee", selection: $aliasTarget) {
                    Text("Select").tag(Optional<Payee.ID>.none)
                    ForEach(people) { person in
                        Text(person.name).tag(Optional(person.id))
                    }
                }
                Button("Confirm alias", action: confirm)
            }
        }
        .navigationTitle("Payees")
        .onAppear(perform: reload)
    }

    private func binding(for person: Payee) -> Binding<LedgerCategoryID?> {
        Binding(
            get: { person.defaultCategory?.id },
            set: { newValue in
                do {
                    if let newValue {
                        try model.ledger.setDefaultCategory(newValue, for: person.id)
                    }
                    message = nil
                    reload()
                } catch {
                    message = error.localizedDescription
                }
            }
        )
    }

    private func confirm() {
        guard let aliasTarget else {
            message = "Select a payee first."
            return
        }
        do {
            try model.ledger.confirmAlias(aliasName, of: aliasTarget)
            aliasName = ""
            message = nil
            reload()
        } catch {
            message = error.localizedDescription
        }
    }

    private func reload() {
        do {
            people = try model.ledger.payees()
            try model.reloadFromOutside()
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }
}

struct TrashScreen: View {
    @ObservedObject var model: CaptureModel
    @State private var entries: [TrashedEntry] = []
    @State private var message: String?

    var body: some View {
        List {
            if let message {
                Section {
                    Text(message)
                        .foregroundStyle(.red)
                }
            }
            if entries.isEmpty {
                ContentUnavailableView(
                    "Recently deleted is empty",
                    systemImage: "trash",
                    description: Text("Deleted transactions stay here for 30 days before automatic removal.")
                )
            } else {
                ForEach(entries) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.transaction.payee.name)
                            Text("\(entry.transaction.category.name) · \(entry.transaction.reportingDate.iso8601)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text("\(entry.daysRemaining) \(entry.daysRemaining == 1 ? "day" : "days") remaining")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(formatEuro(entry.transaction.amount.value))
                            .monospacedDigit()
                        Button("Restore") {
                            do {
                                try model.ledger.restore(entry.id)
                                message = nil
                                reload()
                            } catch {
                                message = error.localizedDescription
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .navigationTitle("Recently deleted")
        .onAppear(perform: reload)
    }

    private func reload() {
        do {
            entries = try model.ledger.trashedEntries(today: model.today)
            try model.reloadFromOutside()
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }
}

struct ImportScreen: View {
    @ObservedObject var model: CaptureModel
    @State private var csv = ""
    @State private var rows: [ImportRow] = []
    @State private var proposals: [ProposedPayeeDefault] = []
    @State private var acceptedPayees: Set<String> = []
    @State private var dateColumn = "Date"
    @State private var message = ""
    @State private var isError = false

    var body: some View {
        Form {
            TextField("Reporting date column", text: $dateColumn)
            TextEditor(text: $csv).frame(minHeight: 120)
            Button("Preview", action: preview)
            Button("Commit ready rows", action: commit)
            if !message.isEmpty {
                Text(message)
                    .foregroundStyle(isError ? .red : .secondary)
            }
            ForEach(rows) { row in
                VStack(alignment: .leading) {
                    Text("\(row.payee ?? "") · \(row.amountText ?? "") · \(row.categoryName ?? "") · \(row.reportingDate ?? "")")
                    Text(stateLabel(row.state)).font(.footnote).foregroundStyle(.secondary)
                    if let proposed = row.proposedDefaultCategoryName, let payee = row.payee {
                        Text("Proposed default for \(payee): \(proposed)")
                            .font(.footnote)
                        if acceptedPayees.contains(payee) {
                            Text("Default will be accepted on commit.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            Button("Accept default") { acceptedPayees.insert(payee) }
                        }
                    }
                }
                if case .uncertainMatch = row.state {
                    Button("Keep this row") { keep(row) }
                }
            }
            ForEach(proposals) { proposal in
                VStack(alignment: .leading) {
                    Text("Proposed default for \(proposal.payee): \(proposal.categoryName)")
                    Button("Accept default") { accept(proposal) }
                }
            }
        }
        .navigationTitle("Import")
    }

    private func preview() {
        do {
            rows = try model.ledger.previewImport(csv, mapping: ImportMapping(reportingDateColumn: dateColumn))
            proposals = try model.ledger.proposedPayeeDefaults()
            message = "\(rows.count) rows"
            isError = false
        } catch {
            message = error.localizedDescription
            isError = true
        }
    }

    private func commit() {
        do {
            let result = try model.ledger.commitImport(
                csv,
                mapping: ImportMapping(reportingDateColumn: dateColumn),
                acceptedPayees: acceptedPayees
            )
            message = "Imported \(result.importedCount)"
            isError = false
            acceptedPayees = []
            try model.reloadFromOutside()
            preview()
        } catch {
            message = error.localizedDescription
            isError = true
        }
    }

    private func keep(_ row: ImportRow) {
        do {
            _ = try model.ledger.commitImport(
                csv,
                mapping: ImportMapping(reportingDateColumn: dateColumn),
                uncertain: [row.index: .keep],
                acceptedPayees: acceptedPayees
            )
            acceptedPayees = []
            isError = false
            try model.reloadFromOutside()
            preview()
        } catch {
            message = error.localizedDescription
            isError = true
        }
    }

    private func accept(_ proposal: ProposedPayeeDefault) {
        do {
            try model.ledger.acceptProposedPayeeDefault(for: proposal.payeeID)
            isError = false
            try model.reloadFromOutside()
            preview()
        } catch {
            message = error.localizedDescription
            isError = true
        }
    }

    private func stateLabel(_ state: ImportRowState) -> String {
        switch state {
        case .ready: "Ready"
        case .needsCorrection(let reasons): reasons.joined(separator: " ")
        case .definiteRepeat: "Definite repeat"
        case .uncertainMatch: "Uncertain match"
        }
    }
}
