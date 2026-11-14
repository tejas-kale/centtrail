import Charts
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
                    if summary.currentSpendingCents == 0 {
                        Section {
                            ContentUnavailableView {
                                Label("No spending this month", systemImage: "eurosign.circle")
                            } description: {
                                Text("Add an expense to compare \(monthTitle(model.today)) with \(monthName(summary.previousFullMonthRange.start)).")
                            } actions: {
                                Button("Add transaction") {
                                    model.openAddSheet()
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                    } else {
                        Section {
                            HomeSummaryCard(summary: summary, today: model.today)
                        }

                        if !summary.categories.isEmpty {
                            Section("Categories") {
                                HomeCategoryComparisonChart(categories: summary.categories)
                                ForEach(summary.categories) { item in
                                    HomeCategoryComparisonRow(item: item)
                                }
                            }
                        }
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

private struct HomeCategoryComparisonChart: View {
    let categories: [CategorySummary]

    private struct BarEntry: Identifiable {
        let id: String
        let categoryName: String
        let period: String
        let euros: Double
    }

    private var bars: [BarEntry] {
        categories.flatMap { item in
            [
                BarEntry(
                    id: "\(item.id.rawValue)-current",
                    categoryName: item.category.name,
                    period: "This month",
                    euros: Double(item.currentCents) / 100.0
                ),
                BarEntry(
                    id: "\(item.id.rawValue)-previous",
                    categoryName: item.category.name,
                    period: "Last month",
                    euros: Double(item.previousSameDaysCents) / 100.0
                ),
            ]
        }
    }

    var body: some View {
        Chart(bars) { bar in
            BarMark(
                x: .value("Spending", bar.euros),
                y: .value("Category", bar.categoryName)
            )
            .position(by: .value("Period", bar.period))
            .foregroundStyle(by: .value("Period", bar.period))
            .cornerRadius(4)
        }
        .chartForegroundStyleScale([
            "This month": Color.accentColor,
            "Last month": Color.secondary.opacity(0.45),
        ])
        .chartLegend(position: .top, alignment: .leading)
        .chartXAxis {
            AxisMarks(position: .bottom) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let euros = value.as(Double.self) {
                        Text(euros.formatted(.currency(code: "EUR").precision(.fractionLength(0))))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .frame(height: CGFloat(max(categories.count, 1)) * 46 + 28)
        .padding(.vertical, 4)
    }
}

private struct HomeCategoryComparisonRow: View {
    let item: CategorySummary

    var body: some View {
        HStack {
            Text(item.category.name)
                .lineLimit(1)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatEuro(item.currentCents))
                    .fontWeight(.medium)
                    .monospacedDigit()
                Text("Last month: \(formatEuro(item.previousSameDaysCents))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}

struct AllTransactionsScreen: View {
    @ObservedObject var model: CaptureModel
    @State private var searchText = ""

    private var filteredTransactions: [LedgerTransaction] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return model.transactions }
        return model.transactions.filter { tx in
            (tx.payee?.name.localizedCaseInsensitiveContains(query) ?? false)
                || (tx.category?.name.localizedCaseInsensitiveContains(query) ?? false)
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
    @StateObject private var voice = VoiceCapture()

    private var missingFieldMessage: String? {
        guard Cents(euroText: model.amountText) != nil else { return "Enter an amount." }
        guard model.accountID != nil else { return "Choose an account." }
        if model.kind == .transfer {
            guard let destination = model.destinationAccountID else { return "Choose a destination account." }
            guard destination != model.accountID else { return "Choose two different accounts." }
        } else {
            guard !model.payee.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "Enter a payee." }
            guard model.categoryID != nil else { return "Choose a category." }
        }
        return nil
    }

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
                    Button {
                        if voice.isRecording {
                            voice.finish()
                        } else {
                            Task {
                                await voice.start(contextualStrings: Array((model.payees.map(\.name) + model.accounts.map(\.name)).prefix(100)))
                            }
                        }
                    } label: {
                        Label(voice.isRecording ? "Stop listening" : "Fill from speech", systemImage: voice.isRecording ? "stop.circle.fill" : "mic")
                    }
                    .disabled(voice.isPreparing || model.isInterpretingSpeech || model.kind == .transfer)
                    .accessibilityHint("Fills the form from on-device speech. Review the fields and tap Save to record the transaction.")
                    if voice.isPreparing {
                        ProgressView("Preparing microphone")
                    } else if voice.isRecording {
                        Text("Listening… Tap Stop when you're finished.")
                            .foregroundStyle(.secondary)
                    } else if model.isInterpretingSpeech {
                        ProgressView("Filling the form")
                    }
                    if !voice.transcript.isEmpty {
                        Text(voice.transcript)
                        Text("Review the fields, then tap Save.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    Picker("Kind", selection: $model.kind) {
                        Text("Expense").tag(Kind.expense)
                        Text("Income").tag(Kind.income)
                        Text("Transfer").tag(Kind.transfer)
                    }
                    .pickerStyle(.segmented)

                    TextField("Amount", text: $model.amountText, prompt: Text("0.00"))
                        .focused($isAmountFocused)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                }

                if model.kind != .transfer {
                    if !model.frequentPayees.isEmpty {
                        Section("Frequent payees") {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack {
                                    ForEach(model.frequentPayees) { suggestion in
                                        Button(suggestion.payee.name) {
                                            model.selectFrequentPayee(suggestion)
                                            isAmountFocused = true
                                        }
                                        .buttonStyle(.bordered)
                                        .buttonBorderShape(.capsule)
                                        .accessibilityHint("Fills payee, category and account")
                                    }
                                }
                            }
                        }
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

                        Picker("Category", selection: Binding(get: { model.categoryID }, set: { model.categoryID = $0; model.noteManualCategory() })) {
                            Text("Select").tag(Optional<LedgerCategoryID>.none)
                            ForEach(model.categories) { category in
                                Text(category.name).tag(Optional(category.id))
                            }
                        }

                    }
                }
                Section {
                    Picker(model.kind == .transfer ? "From account" : "Account", selection: $model.accountID) {
                        Text("Select").tag(Optional<Account.ID>.none)
                        ForEach(model.accounts) { account in Text(account.name).tag(Optional(account.id)) }
                    }
                    if model.kind == .transfer {
                        Picker("To account", selection: $model.destinationAccountID) {
                            Text("Select").tag(Optional<Account.ID>.none)
                            ForEach(model.accounts.filter { $0.id != model.accountID }) { account in Text(account.name).tag(Optional(account.id)) }
                        }
                    }
                    DatePicker("Date", selection: $model.selectedDate, displayedComponents: .date)
                }

                if let message = model.draftMessage ?? missingFieldMessage {
                    Section {
                        Text(message)
                            .foregroundStyle(.red)
                    }
                }
            }
            .disabled(model.isInterpretingSpeech)
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
                    .disabled(missingFieldMessage != nil || voice.isRecording || voice.isPreparing || model.isInterpretingSpeech)
                }
            }
            .onAppear {
                isAmountFocused = true
            }
            .onChange(of: voice.completedTranscript) { _, text in
                guard let text else { return }
                Task { await model.interpretSpeech(text) }
            }
            .onChange(of: voice.errorMessage) { _, message in
                if let message { model.draftMessage = message }
            }
            .onChange(of: model.kind) { _, kind in
                if kind == .transfer { voice.cancel() }
            }
            .onDisappear {
                voice.cancel()
                model.cancelSpeechInterpretation()
            }
        }
    }
}

struct TransactionDetail: View {
    @ObservedObject var model: CaptureModel
    let transaction: LedgerTransaction
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategoryID: LedgerCategoryID?

    init(model: CaptureModel, transaction: LedgerTransaction) {
        self.model = model
        self.transaction = transaction
        self._selectedCategoryID = State(initialValue: transaction.category?.id)
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
                if let payee = transaction.payee { LabeledContent("Payee", value: payee.name) }
                LabeledContent("Account", value: transaction.account.name)
                if let destination = transaction.destinationAccount { LabeledContent("To account", value: destination.name) }
                if transaction.kind != .transfer {
                    Picker("Category", selection: $selectedCategoryID) {
                        ForEach(model.categories) { category in
                            Text(category.name).tag(Optional(category.id))
                        }
                    }
                    .onChange(of: selectedCategoryID) { _, newValue in
                        guard let newValue, newValue != transaction.category?.id else { return }
                        model.updateCategory(newValue, for: transaction.id)
                    }
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
        .navigationTitle(transaction.payee?.name ?? "Transfer")
    }
}

struct SettingsScreen: View {
    @ObservedObject var model: CaptureModel

    var body: some View {
        NavigationStack {
            List {
                NavigationLink("Accounts") {
                    AccountsScreen(model: model)
                }
                NavigationLink("Categories") {
                    CategoriesScreen(model: model)
                }
                NavigationLink("Payees") {
                    PayeesScreen(model: model)
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

struct PayeesScreen: View {
    @ObservedObject var model: CaptureModel
    @State private var payees: [Payee] = []
    @State private var mergeSource: Payee.ID?
    @State private var mergeTarget: Payee.ID?
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
                if payees.isEmpty {
                    Text("No payees yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(payees) { payee in
                        Picker(payee.name, selection: binding(for: payee)) {
                            Text("None").tag(Optional<LedgerCategoryID>.none)
                            ForEach(model.categories) { category in
                                Text(category.name).tag(Optional(category.id))
                            }
                        }
                    }
                }
            }
            if payees.count >= 2 {
                Section("Merge payees") {
                    Picker("Merge", selection: $mergeSource) {
                        Text("Select").tag(Optional<Payee.ID>.none)
                        ForEach(payees) { payee in
                            Text(payee.name).tag(Optional(payee.id))
                        }
                    }
                    Picker("Into", selection: $mergeTarget) {
                        Text("Select").tag(Optional<Payee.ID>.none)
                        ForEach(payees.filter { $0.id != mergeSource }) { payee in
                            Text(payee.name).tag(Optional(payee.id))
                        }
                    }
                    Button("Merge payees", action: merge)
                        .disabled(mergeSource == nil || mergeTarget == nil || mergeSource == mergeTarget)
                }
            }
        }
        .navigationTitle("Payees")
        .onAppear(perform: reload)
    }

    private func binding(for payee: Payee) -> Binding<LedgerCategoryID?> {
        Binding(
            get: { payee.defaultCategory?.id },
            set: { newValue in
                do {
                    if let newValue {
                        try model.ledger.setDefaultCategory(newValue, for: payee.id)
                    }
                    message = nil
                    reload()
                } catch {
                    message = error.localizedDescription
                }
            }
        )
    }

    private func merge() {
        guard let mergeSource, let mergeTarget else {
            message = "Select two payees to merge."
            return
        }
        do {
            try model.ledger.mergePayees(sourceID: mergeSource, into: mergeTarget)
            self.mergeSource = nil
            self.mergeTarget = nil
            message = nil
            reload()
        } catch {
            message = error.localizedDescription
        }
    }

    private func reload() {
        do {
            payees = try model.ledger.payees()
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
                            Text(entry.transaction.payee?.name ?? "Transfer")
                            Text("\(entry.transaction.category?.name ?? "Transfer") · \(entry.transaction.reportingDate.iso8601)")
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
