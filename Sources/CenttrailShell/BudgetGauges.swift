import Ledger
import SwiftUI

extension BudgetStatus {
    /// Gauge colour: tint while normal, amber from 80%, red from 100% (capture-first spec).
    var ayuStyle: AyuStyle {
        switch self {
        case .normal: AyuStyle(role: .tint)
        case .warning: AyuStyle(role: .warning)
        case .exceeded: AyuStyle(role: .error)
        }
    }
}

/// A semicircle opening downwards, swept left to right over `fraction` of its length.
struct GaugeArc: Shape {
    var fraction: Double
    var lineWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        let inset = lineWidth / 2
        let radius = max(min(rect.width / 2, rect.height) - inset, 0)
        let center = CGPoint(x: rect.midX, y: rect.maxY - inset)
        var path = Path()
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(180),
            endAngle: .degrees(180 + 180 * min(max(fraction, 0), 1)),
            clockwise: false
        )
        return path.strokedPath(StrokeStyle(lineWidth: lineWidth, lineCap: .round))
    }
}

/// The arc with the percentage used in its centre.
struct BudgetGaugeDial: View {
    let gauge: BudgetGauge
    let diameter: CGFloat
    let lineWidth: CGFloat
    let valueFont: Font

    var body: some View {
        ZStack(alignment: .bottom) {
            GaugeArc(fraction: 1, lineWidth: lineWidth)
                .fill(.quaternary)
            if gauge.spent.value > 0 {
                GaugeArc(fraction: gauge.fraction, lineWidth: lineWidth)
                    .fill(gauge.status.ayuStyle)
            }
            Text("\(gauge.percentUsed)%")
                .font(valueFont)
                .monospacedDigit()
                .foregroundStyle(gauge.status == .normal ? AnyShapeStyle(.primary) : AnyShapeStyle(gauge.status.ayuStyle))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, lineWidth + 2)
        }
        .frame(width: diameter, height: diameter / 2 + lineWidth / 2)
    }
}

/// Home's budget section: a wrapping grid of small gauges; tapping one opens its details.
struct BudgetGaugeGrid: View {
    let gauges: [BudgetGauge]
    let onSelect: (BudgetGauge) -> Void
    @ScaledMetric(relativeTo: .body) private var diameter: CGFloat = 76

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: diameter + 20), spacing: 12, alignment: .top)], spacing: 16) {
            ForEach(gauges) { gauge in
                Button { onSelect(gauge) } label: {
                    VStack(spacing: 4) {
                        BudgetGaugeDial(gauge: gauge, diameter: diameter, lineWidth: 8, valueFont: .subheadline.weight(.semibold))
                        Text(gauge.category.name)
                            .font(.caption)
                            .lineLimit(1)
                        Text(formatAmount(gauge.budget.value, currency: gauge.currency))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(gauge.category.name) budget")
                .accessibilityValue(
                    "\(gauge.percentUsed)% used, \(formatAmount(gauge.spent.value, currency: gauge.currency)) of \(formatAmount(gauge.budget.value, currency: gauge.currency))"
                )
                .accessibilityHint("Shows this budget's details")
                .accessibilityAddTraits(.isButton)
            }
        }
        .padding(.vertical, 8)
    }
}

/// Pop-up for one budget: the numbers for this month and the entries behind them.
struct BudgetDetailSheet: View {
    @ObservedObject var model: CaptureModel
    let gauge: BudgetGauge
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [LedgerTransaction] = []

    /// The live gauge, so the sheet follows edits made while it is open.
    private var current: BudgetGauge {
        model.monthSummary?.budgetGauges.first { $0.id == gauge.id } ?? gauge
    }

    var body: some View {
        let gauge = current
        NavigationStack {
            List {
                Section {
                    BudgetGaugeDial(gauge: gauge, diameter: 160, lineWidth: 14, valueFont: .title.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .accessibilityHidden(true)
                    LabeledContent("Budget", value: formatAmount(gauge.budget.value, currency: gauge.currency))
                    LabeledContent("Spent this month", value: formatAmount(gauge.spent.value, currency: gauge.currency))
                    if gauge.overBudget.value > 0 {
                        LabeledContent("Over budget") {
                            Text(formatAmount(gauge.overBudget.value, currency: gauge.currency))
                                .foregroundStyle(AyuStyle(role: .error))
                        }
                    } else {
                        LabeledContent("Remaining", value: formatAmount(gauge.remaining.value, currency: gauge.currency))
                    }
                    LabeledContent("Used", value: "\(gauge.percentUsed)%")
                }
                .monospacedDigit()

                Section("This month") {
                    if entries.isEmpty {
                        Text("No spending yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(entries) { transaction in
                            TransactionRow(transaction: transaction, today: model.today)
                        }
                    }
                }
            }
            .ayuGroupedBackground()
            .navigationTitle(gauge.category.name)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: gauge) {
                entries = (try? model.ledger.budgetEntries(for: gauge, on: model.today)) ?? []
            }
        }
        .ayuTheme()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 420)
        #endif
    }
}
