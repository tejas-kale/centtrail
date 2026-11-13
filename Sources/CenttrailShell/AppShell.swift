import Interpreter
import Ledger
import SwiftUI

struct TransactionDetail: View {
    let transaction: LedgerTransaction
    let ledger: Ledger

    var body: some View {
        Form {
            LabeledContent("Amount", value: signedEuro(transaction.amount.value))
            LabeledContent("Kind", value: transaction.kind.rawValue.capitalized)
            LabeledContent("Counterparty", value: transaction.counterparty.name)
            LabeledContent("Category", value: transaction.category.name)
            LabeledContent("Provenance", value: transaction.categoryProvenance.rawValue.capitalized)
            LabeledContent("Reporting date", value: transaction.reportingDate.iso8601)
            if let note = transaction.note, !note.isEmpty {
                LabeledContent("Note", value: note)
            }
            if let purchase = originalPurchase {
                Section("Original purchase") {
                    NavigationLink {
                        TransactionDetail(transaction: purchase, ledger: ledger)
                    } label: {
                        Text("\(purchase.counterparty.name) · \(signedEuro(purchase.amount.value)) · \(purchase.reportingDate.iso8601)")
                    }
                }
            }
            if !linkedRefunds.isEmpty {
                Section("Refunds") {
                    ForEach(linkedRefunds) { refund in
                        NavigationLink {
                            TransactionDetail(transaction: refund, ledger: ledger)
                        } label: {
                            Text("\(signedEuro(refund.amount.value)) · \(refund.reportingDate.iso8601)")
                        }
                    }
                }
            }
        }
        .navigationTitle(transaction.counterparty.name)
    }

    private var originalPurchase: LedgerTransaction? {
        guard let id = transaction.originalPurchaseID else { return nil }
        return try? ledger.transaction(id: id)
    }

    private var linkedRefunds: [LedgerTransaction] {
        (try? ledger.linkedRefunds(for: transaction.id)) ?? []
    }
}

struct ReportsScreen: View {
    @ObservedObject var model: CaptureModel
    @State private var rows: [BreakdownRow] = []
    @State private var rangeLabel = ""
    @State private var comparison: LedgerComparison?
    @State private var showsTable = false
    @State private var question = ""
    @State private var answer = ""
    @State private var searchName = ""
    @State private var searchAmount = ""
    @State private var searchCategoryID: LedgerCategoryID?
    @State private var searchFrom = ""
    @State private var searchTo = ""
    @State private var searchNotice = ""
    @State private var matches: [LedgerTransaction] = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Ask") {
                    Text("Apple Intelligence is unavailable. Preset reports below still work.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    TextField("restaurants this month vs last month", text: $question)
                    Button("Ask", action: ask)
                    if !answer.isEmpty {
                        Text(answer)
                    }
                }
                Section("Presets") {
                    Button("This month") { showMonth() }
                    Button("By category") { showBreakdown(grouping: .category, categoryID: nil) }
                    Button("Utilities over months") { showUtilities() }
                    Button("This month versus last month") { showComparison() }
                    Toggle("Table", isOn: $showsTable)
                }
                if let comparison {
                    Section("Comparison") {
                        Text(rangeLabel)
                        LabeledContent("Change", value: signedEuro(comparison.absoluteChangeCents))
                        if comparison.unequalLengths {
                            Text("The months have different lengths.")
                        }
                        if let percentage = comparison.percentageChange {
                            LabeledContent("Percentage", value: String(format: "%.1f%%", percentage))
                        }
                    }
                }
                Section("Result") {
                    Text(rangeLabel).font(.footnote)
                    if showsTable {
                        ForEach(rows) { row in
                            LabeledContent(rowLabel(row), value: signedEuro(row.cents))
                        }
                    } else {
                        ForEach(rows) { row in
                            let width = barWidth(row)
                            HStack {
                                Text(rowLabel(row)).frame(width: 120, alignment: .leading)
                                RoundedRectangle(cornerRadius: 3)
                                    .frame(width: width, height: 14)
                                Text(signedEuro(row.cents)).font(.caption)
                            }
                        }
                    }
                }
                Section("Search") {
                    TextField("Vendor", text: $searchName)
                    TextField("Over euros", text: $searchAmount)
                    Picker("Category", selection: $searchCategoryID) {
                        Text("Any").tag(Optional<LedgerCategoryID>.none)
                        ForEach(model.categories) { category in
                            Text(category.name).tag(Optional(category.id))
                        }
                    }
                    TextField("From", text: $searchFrom, prompt: Text("YYYY-MM-DD"))
                    TextField("To", text: $searchTo, prompt: Text("YYYY-MM-DD"))
                    Button("Search", action: search)
                    if !searchNotice.isEmpty {
                        Text(searchNotice)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(matches) { transaction in
                        NavigationLink {
                            TransactionDetail(transaction: transaction, ledger: model.ledger)
                        } label: {
                            TransactionRow(transaction: transaction)
                        }
                    }
                }
            }
            .navigationTitle("Reports")
        }
    }

    private func ask() {
        let interpreter = Interpreter(ledger: model.ledger, today: model.today, modelUnavailableReason: .modelNotReady)
        guard let interpretation = try? interpreter.interpretReport(question) else { return }
        switch interpretation {
        case .clarification(let names):
            answer = "Which one: \(names.joined(separator: ", "))?"
        case .unsupported(let explanation):
            answer = explanation
        case .operation(let operation):
            guard let result = try? model.ledger.runReport(operation, today: model.today) else { return }
            present(result)
        }
    }

    private func showMonth() {
        comparison = nil
        guard let result = try? model.ledger.runReport(.total(ReportQuery(measure: .spending)), today: model.today) else { return }
        present(result)
    }

    private func showUtilities() {
        comparison = nil
        let utilities = model.categories.first { $0.name == "Utilities" }
        showBreakdown(grouping: .month, categoryID: utilities?.id)
    }

    private func showBreakdown(grouping: Grouping, categoryID: LedgerCategoryID?) {
        comparison = nil
        let query = ReportQuery(measure: .spending, categoryID: categoryID, grouping: grouping)
        guard let result = try? model.ledger.runReport(.breakdown(query), today: model.today) else { return }
        present(result)
    }

    private func showComparison() {
        guard let result = try? model.ledger.runReport(.comparison(measure: .spending, categoryID: nil, counterpartyName: nil), today: model.today) else { return }
        present(result)
    }

    private func search() {
        var amount: AmountCondition?
        if let euros = Int(searchAmount) { amount = .greaterThan(Cents(euros * 100)) }
        let range: DateRange?
        switch dateRange() {
        case .absent:
            range = nil
        case .ready(let value):
            range = value
        case .invalid:
            searchNotice = "Enter both dates as YYYY-MM-DD."
            matches = []
            return
        }
        searchNotice = ""
        let query = ReportQuery(
            measure: .spending,
            range: range,
            categoryID: searchCategoryID,
            counterpartyName: searchName.isEmpty ? nil : searchName,
            amount: amount
        )
        guard case .transactions(let found)? = try? model.ledger.runReport(.search(query), today: model.today) else { return }
        matches = found
    }

    private enum DateRangeInput {
        case absent
        case ready(DateRange)
        case invalid
    }

    private func dateRange() -> DateRangeInput {
        let fromText = searchFrom.trimmingCharacters(in: .whitespacesAndNewlines)
        let toText = searchTo.trimmingCharacters(in: .whitespacesAndNewlines)
        if fromText.isEmpty && toText.isEmpty { return .absent }
        guard let start = ReportingDate(iso8601: fromText), let end = ReportingDate(iso8601: toText) else {
            return .invalid
        }
        return .ready(DateRange(start: start, end: end))
    }

    private func present(_ result: ReportResult) {
        switch result {
        case .spendingTotal(let cents), .incomeTotal(let cents):
            rows = [BreakdownRow(month: nil, categoryName: "Total", cents: cents.value)]
            rangeLabel = monthTitle(model.today)
            comparison = nil
            answer = signedEuro(cents.value)
        case .total(let cents, let range):
            rows = [BreakdownRow(month: nil, categoryName: "Total", cents: cents)]
            rangeLabel = "\(range.start.iso8601) – \(range.end.iso8601)"
            comparison = nil
            answer = "\(signedEuro(cents)) (\(rangeLabel))"
        case .breakdown(let breakdown, let range):
            rows = breakdown
            rangeLabel = "\(range.start.iso8601) – \(range.end.iso8601)"
            comparison = nil
            answer = rangeLabel
        case .comparison(let value):
            comparison = value
            rows = [
                BreakdownRow(month: value.earlier.range.start.iso8601, categoryName: nil, cents: value.earlier.cents),
                BreakdownRow(month: value.later.range.start.iso8601, categoryName: nil, cents: value.later.cents),
            ]
            rangeLabel = "\(value.earlier.range.start.iso8601)–\(value.earlier.range.end.iso8601) versus \(value.later.range.start.iso8601)–\(value.later.range.end.iso8601)"
            answer = "\(rangeLabel). Change \(signedEuro(value.absoluteChangeCents))."
        case .transactions(let transactions):
            matches = transactions
            answer = "\(transactions.count) transactions"
        }
    }

    private func rowLabel(_ row: BreakdownRow) -> String {
        [row.month, row.categoryName].compactMap { $0 }.joined(separator: " ")
    }

    private func barWidth(_ row: BreakdownRow) -> CGFloat {
        let peak = rows.map { abs($0.cents) }.max() ?? 1
        guard peak > 0 else { return 0 }
        return CGFloat(abs(row.cents)) / CGFloat(peak) * 140
    }
}

struct PeopleScreen: View {
    @ObservedObject var model: CaptureModel
    @State private var people: [Counterparty] = []
    @State private var aliasName = ""
    @State private var aliasTarget: Counterparty.ID?

    var body: some View {
        NavigationStack {
            Form {
                Section("Counterparties") {
                    ForEach(people) { person in
                        Picker(person.name, selection: binding(for: person)) {
                            Text("None").tag(Optional<LedgerCategoryID>.none)
                            ForEach(model.categories) { category in
                                Text(category.name).tag(Optional(category.id))
                            }
                        }
                    }
                }
                Section("Alias") {
                    TextField("AMZN MKTP", text: $aliasName)
                    Picker("Counterparty", selection: $aliasTarget) {
                        Text("Select").tag(Optional<Counterparty.ID>.none)
                        ForEach(people) { person in
                            Text(person.name).tag(Optional(person.id))
                        }
                    }
                    Button("Confirm alias", action: confirm)
                }
            }
            .navigationTitle("People")
            .onAppear(perform: reload)
        }
    }

    private func binding(for person: Counterparty) -> Binding<LedgerCategoryID?> {
        Binding(
            get: { person.defaultCategory?.id },
            set: { newValue in
                if let newValue {
                    try? model.ledger.setDefaultCategory(newValue, for: person.id)
                }
                reload()
            }
        )
    }

    private func confirm() {
        guard let aliasTarget else { return }
        try? model.ledger.confirmAlias(aliasName, of: aliasTarget)
        aliasName = ""
        reload()
    }

    private func reload() {
        people = (try? model.ledger.counterparties()) ?? []
        try? model.reloadFromOutside()
    }
}

struct TrashScreen: View {
    @ObservedObject var model: CaptureModel
    @State private var entries: [TrashedEntry] = []

    var body: some View {
        NavigationStack {
            List {
                ForEach(entries) { entry in
                    VStack(alignment: .leading) {
                        Text(entry.transaction.counterparty.name)
                        Text("\(entry.daysRemaining) days remaining")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Button("Restore") {
                        try? model.ledger.restore(entry.id)
                        reload()
                    }
                }
            }
            .navigationTitle("Trash")
            .toolbar {
                Button("Purge expired") {
                    try? model.ledger.purgeExpiredTrash(today: model.today)
                    reload()
                }
            }
            .onAppear(perform: reload)
        }
    }

    private func reload() {
        entries = (try? model.ledger.trashedEntries(today: model.today)) ?? []
        try? model.reloadFromOutside()
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

    var body: some View {
        NavigationStack {
            Form {
                TextField("Reporting date column", text: $dateColumn)
                TextEditor(text: $csv).frame(minHeight: 120)
                Button("Preview", action: preview)
                Button("Commit ready rows", action: commit)
                if !message.isEmpty { Text(message) }
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
    }

    private func preview() {
        rows = (try? model.ledger.previewImport(csv, mapping: ImportMapping(reportingDateColumn: dateColumn))) ?? []
        proposals = (try? model.ledger.proposedPayeeDefaults()) ?? []
        message = "\(rows.count) rows"
    }

    private func commit() {
        let result = try? model.ledger.commitImport(
            csv,
            mapping: ImportMapping(reportingDateColumn: dateColumn),
            acceptedPayees: acceptedPayees
        )
        message = "Imported \(result?.importedCount ?? 0)"
        acceptedPayees = []
        try? model.reloadFromOutside()
        preview()
    }

    private func keep(_ row: ImportRow) {
        _ = try? model.ledger.commitImport(
            csv,
            mapping: ImportMapping(reportingDateColumn: dateColumn),
            uncertain: [row.index: .keep],
            acceptedPayees: acceptedPayees
        )
        acceptedPayees = []
        try? model.reloadFromOutside()
        preview()
    }

    private func accept(_ proposal: ProposedPayeeDefault) {
        try? model.ledger.acceptProposedPayeeDefault(for: proposal.counterpartyID)
        try? model.reloadFromOutside()
        preview()
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
