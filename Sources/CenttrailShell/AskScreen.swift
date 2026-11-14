import Charts
import Interpreter
import Ledger
import SwiftUI

public enum AskPreset: String, CaseIterable, Identifiable, Sendable {
    case thisMonthByCategory = "This month by category"
    case thisMonthVsLastMonth = "This month vs last month"
    case biggestExpenses = "Biggest expenses"

    public var id: String { rawValue }
}

public enum AskCard: Equatable, Sendable {
    case total(cents: Int, range: DateRange)
    case breakdown(rows: [BreakdownRow], grouping: Grouping, range: DateRange)
    case comparison(LedgerComparison)
    case transactions([LedgerTransaction], range: DateRange)
}

public struct AskMessage: Identifiable, Equatable, Sendable {
    public enum Role: Equatable, Sendable {
        case user
        case assistant
    }

    public enum Content: Equatable, Sendable {
        case text(String)
        case answer(sentence: String, card: AskCard)
        case clarification(question: String, prompt: String, options: [String])
    }

    public let id: UUID
    public let role: Role
    public let content: Content

    public init(id: UUID = UUID(), role: Role, content: Content) {
        self.id = id
        self.role = role
        self.content = content
    }
}

@MainActor
public final class AskModel: ObservableObject {
    public let ledger: Ledger
    public let today: ReportingDate
    private let interpreter: Interpreter?

    @Published public var inputText: String = ""
    @Published public var messages: [AskMessage] = []

    public init(ledger: Ledger, today: ReportingDate, interpreter: Interpreter?) {
        self.ledger = ledger
        self.today = today
        self.interpreter = interpreter
    }

    public convenience init(ledger: Ledger, today: ReportingDate) {
        self.init(ledger: ledger, today: today, interpreter: Interpreter(ledger: ledger, today: today))
    }

    public func submitInput() {
        let question = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        inputText = ""
        messages.append(AskMessage(role: .user, content: .text(question)))
        interpretAndRun(question, resolvedName: nil)
    }

    public func resolveClarification(question: String, choice: String) {
        messages.append(AskMessage(role: .user, content: .text(choice)))
        interpretAndRun(question, resolvedName: choice)
    }

    public func runPreset(_ preset: AskPreset) {
        messages.append(AskMessage(role: .user, content: .text(preset.rawValue)))
        switch preset {
        case .thisMonthByCategory:
            execute(.breakdown(ReportQuery(measure: .spending, grouping: .category)))
        case .thisMonthVsLastMonth:
            execute(.comparison(measure: .spending, categoryID: nil, payeeName: nil))
        case .biggestExpenses:
            execute(
                .search(ReportQuery(measure: .spending, range: currentMonthRange())),
                biggestExpensesOnly: true
            )
        }
    }

    private func interpretAndRun(_ question: String, resolvedName: String?) {
        guard let interpreter else {
            messages.append(AskMessage(
                role: .assistant,
                content: .text("Try one of the preset questions above.")
            ))
            return
        }
        do {
            let interpretation = try interpreter.interpretReport(question, resolvedName: resolvedName)
            switch interpretation {
            case .operation(let operation):
                execute(operation)
            case .clarification(let options):
                messages.append(AskMessage(
                    role: .assistant,
                    content: .clarification(
                        question: question,
                        prompt: "Which one did you mean?",
                        options: options
                    )
                ))
            case .unsupported(let explanation):
                messages.append(AskMessage(role: .assistant, content: .text(explanation)))
            }
        } catch {
            messages.append(AskMessage(role: .assistant, content: .text(error.localizedDescription)))
        }
    }

    private func execute(_ operation: ReportOperation, biggestExpensesOnly: Bool = false) {
        do {
            let resolvedOperation: ReportOperation
            let searchRange: DateRange
            let measure: Measure
            let grouping: Grouping

            switch operation {
            case .search(var query):
                let range = query.range ?? currentMonthRange()
                query.range = range
                resolvedOperation = .search(query)
                searchRange = range
                measure = query.measure
                grouping = .category
            case .breakdown(let query):
                resolvedOperation = operation
                searchRange = query.range ?? currentMonthRange()
                measure = query.measure
                grouping = query.grouping ?? .category
            case .total(let query):
                resolvedOperation = operation
                searchRange = query.range ?? currentMonthRange()
                measure = query.measure
                grouping = .category
            case .currentMonthIncome:
                resolvedOperation = operation
                searchRange = currentMonthRange()
                measure = .income
                grouping = .category
            case .currentMonthSpending, .comparison:
                resolvedOperation = operation
                searchRange = currentMonthRange()
                measure = .spending
                grouping = .category
            }

            let result = try ledger.runReport(resolvedOperation, today: today)
            let answer = formatAnswer(
                result: result,
                measure: measure,
                grouping: grouping,
                fallbackRange: searchRange,
                biggestExpensesOnly: biggestExpensesOnly
            )
            messages.append(AskMessage(role: .assistant, content: answer))
        } catch {
            messages.append(AskMessage(role: .assistant, content: .text(error.localizedDescription)))
        }
    }

    private func formatAnswer(
        result: ReportResult,
        measure: Measure,
        grouping: Grouping,
        fallbackRange: DateRange,
        biggestExpensesOnly: Bool
    ) -> AskMessage.Content {
        switch result {
        case .spendingTotal(let signed):
            let cents = signed.value
            let sentence = "You spent \(formatEuro(cents)) from \(dateRangeLabel(fallbackRange))."
            return .answer(sentence: sentence, card: .total(cents: cents, range: fallbackRange))

        case .incomeTotal(let signed):
            let cents = signed.value
            let sentence = "Your income was \(formatEuro(cents)) from \(dateRangeLabel(fallbackRange))."
            return .answer(sentence: sentence, card: .total(cents: cents, range: fallbackRange))

        case .total(let cents, let range):
            let verb = measure == .income ? "Your income was" : "You spent"
            let sentence = "\(verb) \(formatEuro(cents)) from \(dateRangeLabel(range))."
            return .answer(sentence: sentence, card: .total(cents: cents, range: range))

        case .breakdown(let rows, let range):
            let displayRows = grouping == .category ? rows.filter { $0.cents > 0 } : rows
            let total = displayRows.reduce(0) { $0 + $1.cents }
            let noun = measure == .income ? "income" : "spending"
            let sentence = displayRows.isEmpty
                ? "No \(noun) recorded from \(dateRangeLabel(range))."
                : "Total \(noun) was \(formatEuro(total)) from \(dateRangeLabel(range))."
            return .answer(sentence: sentence, card: .breakdown(rows: displayRows, grouping: grouping, range: range))

        case .comparison(let comparison):
            let noun = measure == .income ? "Income" : "Spending"
            var parts = [
                "\(noun) was \(formatEuro(comparison.later.cents)) (\(shortRangeLabel(comparison.later.range)))",
                "vs \(formatEuro(comparison.earlier.cents)) (\(shortRangeLabel(comparison.earlier.range)))",
                "(\(formatSignedEuro(comparison.absoluteChangeCents))"
            ]
            if let pct = comparison.percentageChange {
                parts[2] += ", \(formatPercentageChange(pct)))"
            } else {
                parts[2] += ")"
            }
            let sentence = parts.joined(separator: " ") + "."
            return .answer(sentence: sentence, card: .comparison(comparison))

        case .transactions(let allTransactions):
            let filtered: [LedgerTransaction]
            if biggestExpensesOnly {
                filtered = Array(
                    allTransactions
                        .filter { $0.kind == .expense }
                        .sorted { $0.amount.value > $1.amount.value }
                        .prefix(10)
                )
            } else {
                filtered = allTransactions
            }
            let total = filtered.reduce(0) { $0 + $1.amount.value }
            let sentence = filtered.isEmpty
                ? "No matching transactions from \(dateRangeLabel(fallbackRange))."
                : "Found \(filtered.count) \(filtered.count == 1 ? "transaction" : "transactions") totalling \(formatEuro(total)) from \(dateRangeLabel(fallbackRange))."
            return .answer(sentence: sentence, card: .transactions(filtered, range: fallbackRange))
        }
    }

    private func currentMonthRange() -> DateRange {
        let start = ReportingDate(year: today.year, month: today.month, day: 1)!
        let last = ReportingDate.dayCount(month: today.month, year: today.year)
        let end = ReportingDate(year: today.year, month: today.month, day: last)!
        return DateRange(start: start, end: end)
    }
}

struct AskScreen: View {
    @StateObject private var askModel: AskModel

    init(model: CaptureModel) {
        _askModel = StateObject(wrappedValue: AskModel(ledger: model.ledger, today: model.today))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                presetChipsBar
                Divider()
                chatThread
                Divider()
                inputBar
            }
            .navigationTitle("Ask")
        }
    }

    private var presetChipsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AskPreset.allCases) { preset in
                    Button(preset.rawValue) {
                        askModel.runPreset(preset)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
    }

    private var chatThread: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if askModel.messages.isEmpty {
                        ContentUnavailableView(
                            "Ask Centtrail",
                            systemImage: "sparkles",
                            description: Text("Ask a question about your spending, or tap a preset above.")
                        )
                        .padding(.top, 40)
                    } else {
                        ForEach(askModel.messages) { message in
                            AskMessageRow(message: message) { question, choice in
                                askModel.resolveClarification(question: question, choice: choice)
                            }
                            .id(message.id)
                        }
                    }
                }
                .padding()
            }
            .onChange(of: askModel.messages.count) { _, _ in
                if let lastID = askModel.messages.last?.id {
                    withAnimation {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Ask about your spending", text: $askModel.inputText)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    askModel.submitInput()
                }
            Button {
                askModel.submitInput()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .disabled(askModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Send question")
        }
        .padding()
    }
}

private struct AskMessageRow: View {
    let message: AskMessage
    let onClarificationChoice: (String, String) -> Void

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 40)
                if case .text(let text) = message.content {
                    Text(text)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.accentColor.opacity(0.16), in: RoundedRectangle(cornerRadius: 14))
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    switch message.content {
                    case .text(let text):
                        Text(text)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))

                    case .clarification(let question, let prompt, let options):
                        VStack(alignment: .leading, spacing: 8) {
                            Text(prompt)
                            FlowOptions(options: options) { choice in
                                onClarificationChoice(question, choice)
                            }
                        }
                        .padding(12)
                        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))

                    case .answer(let sentence, let card):
                        Text(sentence)
                            .font(.body)
                        AskCardView(card: card)
                    }
                }
                Spacer(minLength: 24)
            }
        }
    }
}

private struct FlowOptions: View {
    let options: [String]
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    Button(option) {
                        onSelect(option)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
    }
}

private struct AskCardView: View {
    let card: AskCard

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch card {
            case .total(let cents, let range):
                Text(formatEuro(cents))
                    .font(.title2.bold())
                    .monospacedDigit()
                Text(dateRangeLabel(range))
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .breakdown(let rows, let grouping, let range):
                if rows.isEmpty {
                    Text("No entries in this period.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Chart(rows) { row in
                        let label = breakdownLabel(row, grouping: grouping)
                        BarMark(
                            x: .value("Label", label),
                            y: .value("Amount", Double(row.cents) / 100.0)
                        )
                    }
                    .frame(height: 180)
                }
                Text(dateRangeLabel(range))
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .comparison(let comparison):
                let earlierLabel = shortRangeLabel(comparison.earlier.range)
                let laterLabel = shortRangeLabel(comparison.later.range)
                Chart {
                    BarMark(
                        x: .value("Period", earlierLabel),
                        y: .value("Amount", Double(comparison.earlier.cents) / 100.0)
                    )
                    BarMark(
                        x: .value("Period", laterLabel),
                        y: .value("Amount", Double(comparison.later.cents) / 100.0)
                    )
                }
                .frame(height: 160)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Earlier: \(dateRangeLabel(comparison.earlier.range)) · \(formatEuro(comparison.earlier.cents))")
                    Text("Later: \(dateRangeLabel(comparison.later.range)) · \(formatEuro(comparison.later.cents))")
                    if comparison.unequalLengths {
                        Text("Unequal month lengths: \(comparison.later.range.end.day) days vs \(comparison.earlier.range.end.day) days")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

            case .transactions(let transactions, let range):
                if transactions.isEmpty {
                    Text("No matching transactions.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(transactions) { transaction in
                        TransactionRow(transaction: transaction)
                        if transaction.id != transactions.last?.id {
                            Divider()
                        }
                    }
                }
                Text(dateRangeLabel(range))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    private func breakdownLabel(_ row: BreakdownRow, grouping: Grouping) -> String {
        switch grouping {
        case .category:
            return row.categoryName ?? "Uncategorized"
        case .month:
            return row.month ?? ""
        case .monthAndCategory:
            return [row.month, row.categoryName].compactMap { $0 }.joined(separator: " · ")
        }
    }
}

private func dateRangeLabel(_ range: DateRange) -> String {
    "\(range.start.iso8601) – \(range.end.iso8601)"
}
