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
    @Published public private(set) var isThinking: Bool = false
    /// The last operation answered, so a follow-up ("And on software?") can reuse its period and grouping.
    private var lastOperation: ReportOperation?

    public var modelUnavailableReason: ModelUnavailableReason? {
        interpreter?.modelUnavailableReason
    }

    public var unavailableNote: String? {
        guard let reason = interpreter?.modelUnavailableReason else { return nil }
        switch reason {
        case .deviceNotEligible:
            return "On-device model unavailable: this device isn't eligible for Apple Intelligence. Using keyword search and presets."
        case .appleIntelligenceOff:
            return "On-device model unavailable: Apple Intelligence is turned off in Settings. Using keyword search and presets."
        case .modelNotReady:
            return "On-device model unavailable: the Apple Intelligence model is still downloading or not ready. Using keyword search and presets."
        }
    }

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
        if let lastOperation {
            do {
                if let followUp = try interpreter.interpretFollowUp(
                    question,
                    previous: lastOperation,
                    resolvedName: resolvedName
                ) {
                    handleInterpretation(followUp, question: question)
                    return
                }
            } catch {
                messages.append(AskMessage(role: .assistant, content: .text(error.localizedDescription)))
                return
            }
        }
        if interpreter.modelUnavailableReason != nil {
            do {
                let interpretation = try interpreter.interpretReport(question, resolvedName: resolvedName)
                handleInterpretation(interpretation, question: question)
            } catch {
                messages.append(AskMessage(role: .assistant, content: .text(error.localizedDescription)))
            }
            return
        }

        let context: InterpretationContext
        do {
            context = try interpreter.makeContext()
        } catch {
            messages.append(AskMessage(role: .assistant, content: .text(error.localizedDescription)))
            return
        }
        let backend = interpreter.backend
        isThinking = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isThinking = false }
            do {
                let interpretation = try await backend.interpretReportAsync(
                    question,
                    context: context,
                    resolvedName: resolvedName
                )
                self.handleInterpretation(interpretation, question: question)
            } catch {
                self.messages.append(AskMessage(role: .assistant, content: .text(error.localizedDescription)))
            }
        }
    }

    private func handleInterpretation(_ interpretation: ReportInterpretation, question: String) {
        switch interpretation {
        case .operation(let operation):
            execute(operation, biggestExpensesOnly: question.localizedCaseInsensitiveContains("biggest"))
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
            lastOperation = resolvedOperation
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
        ledger.resolvedRange(nil, today: today)
    }
}

struct AskScreen: View {
    @StateObject private var askModel: AskModel
    @FocusState private var isInputFocused: Bool

    init(model: CaptureModel) {
        _askModel = StateObject(wrappedValue: AskModel(ledger: model.ledger, today: model.today))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let note = askModel.unavailableNote {
                    unavailableBanner(note)
                    Divider()
                }
                presetChipsBar
                Divider()
                chatThread
                    .contentShape(Rectangle())
                    .onTapGesture { isInputFocused = false }
                Divider()
                inputBar
            }
            .navigationTitle("Ask")
        }
    }

    private func unavailableBanner(_ note: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text(note)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.08))
    }

    private var presetChipsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AskPreset.allCases) { preset in
                    Button(preset.rawValue) {
                        isInputFocused = false
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
                        if askModel.isThinking {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Thinking…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 4)
                        }
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.immediately)
            .onChange(of: askModel.messages.count) { _, _ in
                if let lastID = askModel.messages.last?.id {
                    withAnimation {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
        }
    }

    /// Sends the question and hides the keyboard so the tab bar is reachable again.
    private func submit() {
        askModel.submitInput()
        isInputFocused = false
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Ask about your spending", text: $askModel.inputText)
                .textFieldStyle(.roundedBorder)
                .focused($isInputFocused)
                .submitLabel(.send)
                .onSubmit(submit)
            Button(action: submit) {
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
                        .textSelection(.enabled)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.accentColor.opacity(0.16), in: RoundedRectangle(cornerRadius: 14))
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    switch message.content {
                    case .text(let text):
                        Text(text)
                            .textSelection(.enabled)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))

                    case .clarification(let question, let prompt, let options):
                        VStack(alignment: .leading, spacing: 8) {
                            Text(prompt)
                                .textSelection(.enabled)
                            FlowOptions(options: options) { choice in
                                onClarificationChoice(question, choice)
                            }
                        }
                        .padding(12)
                        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))

                    case .answer(let sentence, let card):
                        Text(sentence)
                            .textSelection(.enabled)
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
                } else if grouping == .category {
                    Chart(rows) { row in
                        BarMark(
                            x: .value("Category", row.categoryName ?? "Uncategorized"),
                            y: .value("Amount", Double(row.cents) / 100.0)
                        )
                    }
                    .frame(height: 180)
                } else {
                    MonthlyBreakdownChart(rows: rows, byCategory: grouping == .monthAndCategory)
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
        .textSelection(.enabled)
    }

}

/// Bars per month on a date axis: "Jan", "Feb", … within one year, with the year
/// added under the first month and under each month where the year changes.
private struct MonthlyBreakdownChart: View {
    let rows: [BreakdownRow]
    let byCategory: Bool

    private static let calendar = Calendar(identifier: .gregorian)

    private struct Bar: Identifiable {
        let id: String
        let month: Date
        let category: String
        let euros: Double
    }

    private var bars: [Bar] {
        rows.compactMap { row in
            guard let month = row.month.flatMap(Self.monthStart) else { return nil }
            return Bar(id: row.id, month: month, category: row.categoryName ?? "Uncategorized", euros: Double(row.cents) / 100.0)
        }
    }

    /// Every month shown, thinned so labels don't collide when the range is long.
    private var ticks: [Date] {
        let months = Array(Set(bars.map(\.month))).sorted()
        let step = max(1, Int((Double(months.count) / 12.0).rounded(.up)))
        return stride(from: 0, to: months.count, by: step).map { months[$0] }
    }

    private var spansYears: Bool {
        Set(bars.map { Self.calendar.component(.year, from: $0.month) }).count > 1
    }

    var body: some View {
        let ticks = ticks
        let spansYears = spansYears
        Chart(bars) { bar in
            if byCategory {
                BarMark(x: .value("Month", bar.month, unit: .month), y: .value("Amount", bar.euros))
                    .foregroundStyle(by: .value("Category", bar.category))
            } else {
                BarMark(x: .value("Month", bar.month, unit: .month), y: .value("Amount", bar.euros))
            }
        }
        .chartXAxis {
            AxisMarks(values: ticks) { value in
                AxisTick()
                AxisValueLabel(centered: true) {
                    if let date = value.as(Date.self) {
                        let index = ticks.firstIndex(of: date) ?? 0
                        let year = Self.calendar.component(.year, from: date)
                        let showsYear = spansYears
                            && (index == 0 || Self.calendar.component(.year, from: ticks[index - 1]) != year)
                        VStack(spacing: 0) {
                            Text(Self.monthLabel(date))
                            if spansYears {
                                Text(showsYear ? String(year) : " ")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .fixedSize()
                    }
                }
            }
        }
        .frame(height: spansYears ? 200 : 180)
    }

    private static func monthStart(_ text: String) -> Date? {
        let parts = text.split(separator: "-")
        guard parts.count == 2, let year = Int(parts[0]), let month = Int(parts[1]) else { return nil }
        return calendar.date(from: DateComponents(year: year, month: month, day: 1))
    }

    private static func monthLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        return formatter.string(from: date)
    }
}

private func dateRangeLabel(_ range: DateRange) -> String {
    "\(range.start.iso8601) – \(range.end.iso8601)"
}
