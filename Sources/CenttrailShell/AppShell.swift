import Ledger
import SwiftUI

struct HomeScreen: View {
    @ObservedObject var model: CaptureModel

    private var recentTransactions: [LedgerTransaction] {
        model.monthSummary?.recentEntries ?? []
    }

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage = model.errorMessage {
                    Section {
                        ErrorBanner(message: errorMessage) { model.errorMessage = nil }
                    }
                    .ayuRows()
                }

                if let summary = model.monthSummary {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(monthTitle(model.today))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                            let totals = Currency.allCases.compactMap { currency in
                                summary.spendingByCurrency[currency].map { (currency: currency, amount: $0) }
                            }
                            if totals.isEmpty {
                                Text("No spending this month")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(totals, id: \.currency) { item in
                                    Text(formatAmount(item.amount, currency: item.currency))
                                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                                        .monospacedDigit()
                                }
                            }
                        }
                        .padding(.vertical, 6)
                        .accessibilityElement(children: .combine)
                    }
                    .ayuRows()

                    if summary.reviewCount > 0 {
                        Section {
                            NavigationLink {
                                ReviewInboxScreen(model: model)
                            } label: {
                                Label("\(summary.reviewCount) to review", systemImage: "tray.full")
                            }
                        }
                        .ayuRows()
                    }

                    if !summary.budgetGauges.isEmpty {
                        Section("Budgets") {
                            ForEach(summary.budgetGauges) { gauge in
                                BudgetGaugeRow(gauge: gauge)
                            }
                        }
                        .ayuRows()
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
                                TransactionRow(transaction: transaction, today: model.today)
                            }
                            .transactionActions(model: model, transaction: transaction)
                        }
                        NavigationLink("See all") {
                            AllTransactionsScreen(model: model)
                        }
                    }
                }
                .ayuRows()
            }
            .ayuGroupedBackground()
            .navigationTitle("Home")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        model.openAddSheet()
                    } label: {
                        Label("Add transaction", systemImage: "plus")
                            .foregroundStyle(.ayuOnAccent)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(AyuStyle(role: .accent))
                    .keyboardShortcut("n", modifiers: .command)
                }
            }
        }
    }
}

extension View {
    /// Swipe and context-menu actions for a transaction row: edit and move to trash.
    func transactionActions(model: CaptureModel, transaction: LedgerTransaction) -> some View {
        swipeActions {
            Button(role: .destructive) {
                model.trash(transaction)
            } label: {
                Label("Move to Trash", systemImage: "trash")
            }
            .tint(AyuStyle(role: .error))
            Button {
                model.openEditSheet(transaction)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
        }
        .contextMenu {
            Button("Edit", systemImage: "pencil") { model.openEditSheet(transaction) }
            Button("Move to Trash", systemImage: "trash", role: .destructive) { model.trash(transaction) }
        }
    }
}

private struct BudgetGaugeRow: View {
    let gauge: BudgetGauge

    private var tintColor: AyuStyle {
        switch gauge.status {
        case .normal: AyuStyle(role: .tint)
        case .warning: AyuStyle(role: .warning)
        case .exceeded: AyuStyle(role: .error)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(gauge.category.name)
                Spacer()
                Text("\(formatAmount(gauge.spent.value, currency: gauge.currency)) / \(formatAmount(gauge.budget.value, currency: gauge.currency))")
                    .font(.footnote)
                    .foregroundStyle(gauge.status == .normal ? AnyShapeStyle(.secondary) : AnyShapeStyle(tintColor))
                    .monospacedDigit()
            }
            ProgressView(value: min(gauge.fraction, 1.0))
                .tint(tintColor)
        }
        .padding(.vertical, 2)
    }
}

struct ReviewInboxScreen: View {
    @ObservedObject var model: CaptureModel

    var body: some View {
        List {
            if model.reviewInbox.isEmpty {
                ContentUnavailableView(
                    "All caught up",
                    systemImage: "checkmark.circle",
                    description: Text("No entries need review.")
                )
            } else {
                ForEach(model.reviewInbox) { transaction in
                    Button {
                        model.openEditSheet(transaction)
                    } label: {
                        TransactionRow(transaction: transaction, today: model.today)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the entry to review")
                    .transactionActions(model: model, transaction: transaction)
                }
                .ayuRows()
            }
        }
        .ayuGroupedBackground()
        .navigationTitle("To review")
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
                || formatAmount(tx.amount.value, currency: tx.account.currency).localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        List {
            if let errorMessage = model.errorMessage {
                Section {
                    ErrorBanner(message: errorMessage) { model.errorMessage = nil }
                }
                .ayuRows()
            }

            if filteredTransactions.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                ForEach(transactionsByDay, id: \.date) { day in
                    Section {
                        ForEach(day.transactions) { transaction in
                            NavigationLink {
                                TransactionDetail(model: model, transaction: transaction)
                            } label: {
                                TransactionRow(transaction: transaction, today: model.today, showsDate: false)
                            }
                            .transactionActions(model: model, transaction: transaction)
                        }
                    } header: {
                        Text(dayLabel(day.date, today: model.today))
                    }
                    .ayuRows()
                }
            }
        }
        .ayuGroupedBackground()
        .navigationTitle("All transactions")
        .searchable(text: $searchText, prompt: "Search payee, category, or note")
    }

    /// Newest day first; transactions keep their order within a day.
    private var transactionsByDay: [(date: ReportingDate, transactions: [LedgerTransaction])] {
        Dictionary(grouping: filteredTransactions, by: \.reportingDate)
            .map { (date: $0.key, transactions: $0.value) }
            .sorted { $0.date.iso8601 > $1.date.iso8601 }
    }
}

/// "Today", "Yesterday", or a weekday date such as "Fri, 13 Nov 2026".
func dayLabel(_ date: ReportingDate, today: ReportingDate) -> String {
    if date == today { return "Today" }
    if date == today.addingDays(-1) { return "Yesterday" }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    guard let value = calendar.date(from: DateComponents(year: date.year, month: date.month, day: date.day)) else {
        return date.iso8601
    }
    var style = Date.FormatStyle(date: .abbreviated, time: .omitted).weekday(.abbreviated)
    style.timeZone = calendar.timeZone
    return value.formatted(style)
}

/// A compact row date such as "2 Nov", with the year only when it is not this year.
func shortDayLabel(_ date: ReportingDate, today: ReportingDate, locale: Locale = .current) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    guard let value = calendar.date(from: DateComponents(year: date.year, month: date.month, day: date.day)) else {
        return date.iso8601
    }
    var style = Date.FormatStyle(date: .omitted, time: .omitted).day().month(.abbreviated)
    if date.year != today.year { style = style.year() }
    style.timeZone = calendar.timeZone
    style.locale = locale
    return value.formatted(style)
}

struct AddEntrySheet: View {
    @ObservedObject var model: CaptureModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isAmountFocused: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var amountFontSize = 52
    @State private var isChoosingDate = false
    @StateObject private var voice = VoiceCapture()

    private var selectedAccountCurrency: Currency {
        model.accounts.first { $0.id == model.accountID }?.currency ?? .eur
    }

    private var destinationAccountCurrency: Currency? {
        model.accounts.first { $0.id == model.destinationAccountID }?.currency
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Picker("Kind", selection: $model.kind) {
                        Text("Expense").tag(Kind.expense)
                        Text("Income").tag(Kind.income)
                        Text("Transfer").tag(Kind.transfer)
                    }
                    .pickerStyle(.segmented)

                    if model.isCrossCurrencyTransfer, let destinationCurrency = destinationAccountCurrency {
                        VStack(spacing: 12) {
                            VStack(spacing: 4) {
                                Text("Sent (\(selectedAccountCurrency.rawValue))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 8) {
                                    Text(selectedAccountCurrency.symbol).foregroundStyle(.secondary)
                                    TextField("Sent (\(selectedAccountCurrency.rawValue))", text: $model.amountText, prompt: Text("0.00"))
                                        .focused($isAmountFocused)
                                        .multilineTextAlignment(.center)
                                        #if os(iOS)
                                        .keyboardType(.decimalPad)
                                        #endif
                                }
                                .font(.system(size: amountFontSize, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .textFieldStyle(.plain)
                            }
                            VStack(spacing: 4) {
                                Text("Received (\(destinationCurrency.rawValue))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 8) {
                                    Text(destinationCurrency.symbol).foregroundStyle(.secondary)
                                    TextField("Received (\(destinationCurrency.rawValue))", text: $model.receivedAmountText, prompt: Text("0.00"))
                                        .multilineTextAlignment(.center)
                                        #if os(iOS)
                                        .keyboardType(.decimalPad)
                                        #endif
                                }
                                .font(.system(size: amountFontSize * 0.75, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .textFieldStyle(.plain)
                            }
                        }
                        .accessibilityElement(children: .contain)
                    } else {
                        HStack(spacing: 8) {
                            Text(selectedAccountCurrency.symbol).foregroundStyle(.secondary)
                            TextField("Amount", text: $model.amountText, prompt: Text("0.00"))
                                .focused($isAmountFocused)
                                .multilineTextAlignment(.center)
                                #if os(iOS)
                                .keyboardType(.decimalPad)
                                #endif
                        }
                        .font(.system(size: amountFontSize, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .textFieldStyle(.plain)
                        .accessibilityElement(children: .contain)
                    }

                    if model.kind != .transfer {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                TextField("Payee", text: $model.payee, prompt: Text("Who was paid"))
                                    .font(.title3)
                                    .textFieldStyle(.plain)
                                    .onChange(of: model.payee) { _, _ in model.prefillCategory() }
                                microphoneButton
                            }
                            if !model.payeeSuggestions.isEmpty {
                                ForEach(model.payeeSuggestions) { suggestion in
                                    Button {
                                        model.selectSuggestedPayee(suggestion.name)
                                    } label: {
                                        HStack {
                                            Text(suggestion.name)
                                            Spacer()
                                            if let category = suggestion.defaultCategory {
                                                Text(category.name).font(.footnote).foregroundStyle(.secondary)
                                            }
                                        }
                                        .frame(minHeight: 36)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            if model.payee.isEmpty && !model.frequentPayees.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
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
                                .accessibilityLabel("Frequent payees")
                            }
                        }
                    }

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { metadataChips }
                        VStack(alignment: .leading, spacing: 12) { metadataChips }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if model.kind == .transfer {
                        Menu {
                            Picker("To account", selection: $model.destinationAccountID) {
                                Text("Choose account").tag(Optional<Account.ID>.none)
                                ForEach(model.accounts.filter { $0.id != model.accountID }) { account in
                                    Text(account.name).tag(Optional(account.id))
                                }
                            }
                        } label: {
                            Label(model.accounts.first { $0.id == model.destinationAccountID }?.name ?? "To account", systemImage: "arrow.right")
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .accessibilityLabel("Destination account")
                    }

                    if model.editingEntryID != nil && !model.draftNote.isEmpty {
                        TextField("Note", text: $model.draftNote, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                    }

                    if model.isInterpretingSpeech {
                        ProgressView("Filling the card")
                    }

                    if let message = model.draftMessage {
                        Text(message)
                            .foregroundStyle(.ayuError)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityLabel("Entry needs attention: \(message)")
                    }

                    Button("Save") {
                        if model.save() { dismiss() }
                    }
                    .buttonStyle(.ayuProminent)
                    .disabled(voice.isRecording || voice.isPreparing || model.isInterpretingSpeech)
                    .keyboardShortcut(.defaultAction)
                }
                .padding(24)
                .frame(maxWidth: 560)
                .background(.ayuRow, in: RoundedRectangle(cornerRadius: 28))
                .padding()
                .frame(maxWidth: .infinity)
            }
            .background(.ayuBackground)
            .disabled(model.isInterpretingSpeech)
            .navigationTitle(model.editingEntryID == nil ? "New transaction" : "Edit transaction")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if model.consumeStartListening() {
                    startListening()
                } else {
                    isAmountFocused = true
                }
            }
            .onChange(of: model.shouldStartListening) { _, shouldStart in
                if shouldStart, model.consumeStartListening() {
                    startListening()
                }
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
        .overlay {
            if voice.isPreparing || voice.isRecording {
                listeningOverlay
            }
        }
        .frame(minWidth: 300)
        #if os(macOS)
        .frame(minHeight: 480)
        #endif
    }

    @ViewBuilder private var metadataChips: some View {
        if model.kind != .transfer {
            Menu {
                Picker("Category", selection: Binding(
                    get: { model.categoryID },
                    set: { model.categoryID = $0; model.noteManualCategory() }
                )) {
                    Text("Choose category").tag(Optional<LedgerCategoryID>.none)
                    ForEach(model.categories) { category in Text(category.name).tag(Optional(category.id)) }
                }
            } label: {
                Label(model.categories.first { $0.id == model.categoryID }?.name ?? "Category", systemImage: "tag")
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .accessibilityLabel("Category")
            .accessibilityValue(model.categories.first { $0.id == model.categoryID }?.name ?? "Choose category")
        }
        Menu {
            Picker(model.kind == .transfer ? "From account" : "Account", selection: $model.accountID) {
                Text("Choose account").tag(Optional<Account.ID>.none)
                ForEach(model.accounts) { account in Text(account.name).tag(Optional(account.id)) }
            }
        } label: {
            Label(model.accounts.first { $0.id == model.accountID }?.name ?? "Account", systemImage: "creditcard")
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .accessibilityLabel(model.kind == .transfer ? "Source account" : "Account")
        .accessibilityValue(model.accounts.first { $0.id == model.accountID }?.name ?? "Choose account")

        Button { isChoosingDate = true } label: {
            Label(model.selectedDate.formatted(.dateTime.month(.abbreviated).day()), systemImage: "calendar")
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .accessibilityLabel("Date")
        .accessibilityValue(model.selectedDate.formatted(date: .complete, time: .omitted))
        .popover(isPresented: $isChoosingDate) {
            VStack {
                DatePicker("Date", selection: $model.selectedDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                Button("Done") { isChoosingDate = false }
            }
            .padding()
            .presentationCompactAdaptation(.popover)
        }
    }

    private var listeningOverlay: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { voice.cancel() }
                .accessibilityLabel("Dismiss listening overlay")

            VStack(spacing: 16) {
                Image(systemName: voice.isPreparing ? "mic" : "mic.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.tint)
                    .symbolEffect(.pulse, isActive: voice.isRecording)

                Text(voice.isPreparing ? "Preparing microphone…" : "Listening…")
                    .font(.headline)

                Text(voice.transcript.isEmpty ? "Say amount, payee and date" : voice.transcript)
                    .font(.body)
                    .foregroundStyle(voice.transcript.isEmpty ? .secondary : .primary)
                    .multilineTextAlignment(.center)
                    .frame(minHeight: 44)

                if voice.isRecording {
                    Button("Done") {
                        voice.finish()
                    }
                    .buttonStyle(.ayuProminent)
                    .buttonBorderShape(.capsule)
                }
            }
            .padding(24)
            .frame(maxWidth: 340)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
            .shadow(radius: 20)
            .padding(24)
        }
    }

    private var microphoneButton: some View {
        Button {
            if voice.isRecording {
                isAmountFocused = false
                voice.finish()
            } else {
                startListening()
            }
        } label: {
            Image(systemName: voice.isRecording ? "stop.circle.fill" : "mic")
                .font(.title3)
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .disabled(voice.isPreparing || model.isInterpretingSpeech)
        .accessibilityLabel(voice.isRecording ? "Stop listening" : "Fill from speech")
        .accessibilityHint("Fills the card from on-device speech. Review the fields and tap Save.")
    }

    private func startListening() {
        isAmountFocused = false
        let aliases = (try? model.ledger.confirmedAliases().map(\.name)) ?? []
        let contextual = Array((model.payees.map(\.name) + aliases).prefix(100))
        Task {
            await voice.start(contextualStrings: contextual)
        }
    }
}

struct TransactionDetail: View {
    @ObservedObject var model: CaptureModel
    let originalTransaction: LedgerTransaction
    @Environment(\.dismiss) private var dismiss

    init(model: CaptureModel, transaction: LedgerTransaction) {
        self.model = model
        self.originalTransaction = transaction
    }

    private var transaction: LedgerTransaction {
        model.transactions.first { $0.id == originalTransaction.id } ?? originalTransaction
    }

    var body: some View {
        Form {
            if let errorMessage = model.errorMessage {
                Section {
                    ErrorBanner(message: errorMessage) { model.errorMessage = nil }
                }
                .ayuRows()
            }

            Section {
                if transaction.kind == .transfer,
                   let destination = transaction.destinationAccount,
                   destination.currency != transaction.account.currency,
                   let received = transaction.receivedAmount {
                    LabeledContent("Sent") {
                        Text(formatAmount(transaction.amount.value, currency: transaction.account.currency))
                            .monospacedDigit()
                    }
                    LabeledContent("Received") {
                        Text(formatAmount(received.value, currency: destination.currency))
                            .monospacedDigit()
                    }
                } else {
                    LabeledContent("Amount") {
                        Text(formatAmount(transaction.amount.value, currency: transaction.account.currency))
                            .foregroundStyle(transaction.kind == .income ? AnyShapeStyle(.ayuPositive) : AnyShapeStyle(.ayuText))
                            .monospacedDigit()
                    }
                }
                LabeledContent("Kind", value: transaction.kind.rawValue.capitalized)
                if let payee = transaction.payee { LabeledContent("Payee", value: payee.name) }
                LabeledContent("Account", value: transaction.account.name)
                if let destination = transaction.destinationAccount { LabeledContent("To account", value: destination.name) }
                if let category = transaction.category { LabeledContent("Category", value: category.name) }
                LabeledContent("Date", value: dayLabel(transaction.reportingDate, today: model.today))
                if let note = transaction.note, !note.isEmpty {
                    LabeledContent("Note", value: note)
                }
            }
            .ayuRows()

            Section {
                Button(role: .destructive) {
                    model.trash(transaction)
                    if model.errorMessage == nil {
                        dismiss()
                    }
                } label: {
                    Label("Move to Trash", systemImage: "trash")
                        .foregroundStyle(.ayuError)
                }
            }
            .ayuRows()
        }
        .ayuGroupedBackground()
        .navigationTitle(transaction.payee?.name ?? "Transfer")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.openEditSheet(transaction)
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .keyboardShortcut("e", modifiers: .command)
            }
        }
    }
}

struct SettingsScreen: View {
    @ObservedObject var model: CaptureModel
    @AppStorage(AyuDarkChoice.storageKey) private var darkChoice: AyuDarkChoice = .default

    var body: some View {
        NavigationStack {
            List {
                Section("Ledger") {
                    NavigationLink {
                        AccountsScreen(model: model)
                    } label: {
                        Label("Accounts", systemImage: "creditcard")
                    }
                    NavigationLink {
                        CategoriesScreen(model: model)
                    } label: {
                        Label("Categories", systemImage: "square.grid.2x2")
                    }
                    NavigationLink {
                        BudgetsScreen(model: model)
                    } label: {
                        Label("Budgets", systemImage: "chart.bar")
                    }
                    NavigationLink {
                        PayeesScreen(model: model)
                    } label: {
                        Label("Payees", systemImage: "person.2")
                    }
                }
                .ayuRows()
                Section("Data") {
                    NavigationLink {
                        ImportScreen(model: model)
                    } label: {
                        Label("Import CSV", systemImage: "square.and.arrow.down")
                    }
                    NavigationLink {
                        TrashScreen(model: model)
                    } label: {
                        Label("Recently deleted", systemImage: "trash")
                    }
                }
                .ayuRows()
                Section {
                    Picker(selection: $darkChoice) {
                        ForEach(AyuDarkChoice.allCases) { choice in
                            Text(choice.title).tag(choice)
                        }
                    } label: {
                        Label("Dark Mode theme", systemImage: "moon")
                    }
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("Centtrail uses Ayu Light in Light Mode and your choice of Ayu Mirage or Ayu Dark in Dark Mode.")
                }
                .ayuRows()
            }
            .ayuGroupedBackground()
            .navigationTitle("Settings")
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
                    ErrorBanner(message: message) { self.message = nil }
                }
                .ayuRows()
            }
            Section {
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
            } header: {
                Text("Default category")
            } footer: {
                Text("New entries for a payee start with its default category.")
            }
            .ayuRows()
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
                    Button("Merge payees", systemImage: "arrow.triangle.merge", action: merge)
                        .disabled(mergeSource == nil || mergeTarget == nil || mergeSource == mergeTarget)
                }
                .ayuRows()
            }
        }
        .ayuGroupedBackground()
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
            try model.reload()
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
                    ErrorBanner(message: message) { self.message = nil }
                }
                .ayuRows()
            }
            if entries.isEmpty {
                ContentUnavailableView(
                    "Recently deleted is empty",
                    systemImage: "trash",
                    description: Text("Deleted transactions stay here for 30 days before automatic removal.")
                )
            } else {
                Section {
                    ForEach(entries) { entry in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.transaction.payee?.name ?? "Transfer")
                                Text("\(entry.transaction.category?.name ?? "Transfer") · \(shortDayLabel(entry.transaction.reportingDate, today: model.today))")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text("\(entry.daysRemaining) \(entry.daysRemaining == 1 ? "day" : "days") left")
                                    .font(.footnote)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer(minLength: 8)
                            Text(formatAmount(entry.transaction.amount.value, currency: entry.transaction.account.currency))
                                .monospacedDigit()
                            Button { restore(entry) } label: {
                                Image(systemName: "arrow.uturn.backward.circle")
                                    .font(.title2)
                                    .frame(minWidth: 44, minHeight: 44)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Restore \(entry.transaction.payee?.name ?? "transfer")")
                        }
                        .swipeActions(edge: .leading) {
                            Button { restore(entry) } label: {
                                Label("Restore", systemImage: "arrow.uturn.backward")
                            }
                            .tint(AyuStyle(role: .accent))
                        }
                        .contextMenu {
                            Button("Restore", systemImage: "arrow.uturn.backward") { restore(entry) }
                        }
                    }
                }
                .ayuRows()
            }
        }
        .ayuGroupedBackground()
        .navigationTitle("Recently deleted")
        .onAppear(perform: reload)
    }

    private func restore(_ entry: TrashedEntry) {
        do {
            try model.ledger.restore(entry.id)
            message = nil
            reload()
        } catch {
            message = error.localizedDescription
        }
    }

    private func reload() {
        do {
            entries = try model.ledger.trashedEntries(today: model.today)
            try model.reload()
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }
}
