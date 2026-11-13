import Foundation
import Ledger
import struct Ledger.Category

public enum ModelUnavailableReason: String, Equatable, Sendable {
    case deviceNotEligible
    case appleIntelligenceOff
    case modelNotReady
}

public enum ReportInterpretation: Equatable, Sendable {
    case operation(ReportOperation)
    case clarification([String])
    case unsupported(String)
}

public struct CaptureInterpretation: Equatable, Sendable {
    public var draft: EntryDraft
    public var modelUnavailable: ModelUnavailableReason?
}

public struct InterpretationScore: Equatable, Sendable {
    public let operationMatches: Bool
    public let argumentMismatches: [String]

    public var passed: Bool { operationMatches && argumentMismatches.isEmpty }
}

public struct Interpreter {
    public let modelUnavailableReason: ModelUnavailableReason?
    private let ledger: Ledger
    private let today: ReportingDate

    public static let supportedExplanation = """
    Centtrail can answer four kinds of question: a total, a breakdown by month or category, \
    a comparison of this month with last month, and a search for transactions.
    """

    public init(ledger: Ledger, today: ReportingDate, modelUnavailableReason: ModelUnavailableReason? = .modelNotReady) {
        self.ledger = ledger
        self.today = today
        self.modelUnavailableReason = modelUnavailableReason
    }

    public func interpretReport(_ text: String) throws -> ReportInterpretation {
        let folded = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = folded.lowercased()
        let names = try knownNames()
        let tokens = lower.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let hits = names.filter { known in
            let name = known.name.lowercased()
            if lower.contains(name) { return true }
            return tokens.contains { token in name == token || name.hasPrefix(token + " ") }
        }
        let kept = hits.filter { candidate in
            !hits.contains { other in
                other.name.count > candidate.name.count
                    && lower.contains(other.name.lowercased())
                    && other.name.lowercased().contains(candidate.name.lowercased())
            }
        }
        if kept.count > 1, Set(kept.map { $0.name.lowercased() }).count > 1 {
            return .clarification(kept.map(\.name).sorted())
        }
        let categoryID = kept.first { $0.kind == .category }?.categoryID
        let counterpartyName = kept.first { $0.kind == .counterparty }?.name
        let measure: Measure = lower.contains("income") || lower.contains("earned") ? .income : .spending

        if lower.contains("vs") || lower.contains("versus") || lower.contains("compared") {
            return .operation(.comparison(measure: measure, categoryID: categoryID, counterpartyName: counterpartyName))
        }
        if lower.contains("by category") || lower.contains("over month") || lower.contains("each month") || lower.contains("breakdown") {
            let grouping: Grouping = (lower.contains("over month") || lower.contains("each month")) && lower.contains("by category")
                ? .monthAndCategory
                : (lower.contains("over month") || lower.contains("each month") ? .month : .category)
            return .operation(.breakdown(ReportQuery(measure: measure, categoryID: categoryID, counterpartyName: counterpartyName, grouping: grouping)))
        }
        if lower.contains("find") || lower.contains("search") || lower.contains("exactly")
            || lower.contains("over ") || lower.contains("under ") || lower.contains("more than") || lower.contains("less than") {
            return .operation(.search(searchQuery(lower, categoryID: categoryID, counterpartyName: counterpartyName)))
        }
        if lower.contains("how much") || lower.contains("total") || lower.contains("spend") || lower.contains("spent") || lower.contains("income") {
            return .operation(.total(ReportQuery(measure: measure, categoryID: categoryID, counterpartyName: counterpartyName)))
        }
        return .unsupported(Self.supportedExplanation)
    }

    public func interpretCapture(_ text: String) throws -> CaptureInterpretation {
        let draft = try captureDraft(from: text)
        return CaptureInterpretation(draft: draft, modelUnavailable: modelUnavailableReason)
    }

    public func score(_ actual: ReportInterpretation, expected: ReportInterpretation) -> InterpretationScore {
        switch (actual, expected) {
        case (.operation(let actualOperation), .operation(let expectedOperation)):
            return scoreOperation(actualOperation, expectedOperation)
        case (.clarification(let actualNames), .clarification(let expectedNames)):
            let matches = actualNames == expectedNames
            return InterpretationScore(operationMatches: matches, argumentMismatches: matches ? [] : ["candidates"])
        case (.unsupported, .unsupported):
            return InterpretationScore(operationMatches: true, argumentMismatches: [])
        default:
            return InterpretationScore(operationMatches: false, argumentMismatches: ["operation"])
        }
    }

    private func captureDraft(from text: String) throws -> EntryDraft {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        let kind: Kind = lower.contains("income") || lower.contains("from ") ? .income : .expense
        let amount = firstAmount(in: trimmed)
        let name = captureCounterparty(in: trimmed)
        let date = captureDate(in: lower)
        let category = try categoryMentioned(in: lower) ?? (name.flatMap { try? ledger.defaultCategory(forCounterpartyName: $0) })
        let overrides = (try? categoryMentioned(in: lower)) != nil
        return EntryDraft(
            amount: amount,
            kind: kind,
            counterparty: name,
            reportingDate: date,
            categoryID: category?.id,
            overridesCategory: overrides && category != nil
        )
    }

    private func firstAmount(in text: String) -> Cents? {
        var number = ""
        var started = false
        for character in text {
            if character.isNumber || character == "." || character == "," {
                started = true
                number.append(character == "," ? "." : character)
            } else if started {
                break
            }
        }
        return Cents(euroText: number)
    }

    private func captureCounterparty(in text: String) -> String? {
        let lower = text.lowercased()
        if let range = lower.range(of: " at ") {
            return tailName(text[range.upperBound...])
        }
        if let range = lower.range(of: " from ") {
            return tailName(text[range.upperBound...])
        }
        return nil
    }

    private func tailName(_ text: Substring) -> String? {
        var name = String(text)
        for marker in [" yesterday", " today", " on "] {
            if let range = name.lowercased().range(of: marker) {
                name = String(name[..<range.lowerBound])
            }
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func captureDate(in lower: String) -> ReportingDate? {
        if lower.contains("yesterday") { return today.addingDays(-1) }
        if lower.contains("today") { return today }
        if let range = lower.range(of: #"\d{4}-\d{2}-\d{2}"#, options: .regularExpression) {
            return ReportingDate(iso8601: String(lower[range]))
        }
        return today
    }

    private func categoryMentioned(in lower: String) throws -> Category? {
        let categories = try ledger.categories()
        return categories.first { lower.contains($0.name.lowercased()) }
    }

    private struct KnownName {
        var name: String
        var kind: NameKind
        var categoryID: Category.ID?
    }

    private enum NameKind { case category, counterparty }

    private func knownNames() throws -> [KnownName] {
        var names = try ledger.categories().map {
            KnownName(name: $0.name, kind: .category, categoryID: $0.id)
        }
        for counterparty in try ledger.counterparties() {
            names.append(KnownName(name: counterparty.name, kind: .counterparty, categoryID: nil))
        }
        for alias in try ledger.confirmedAliases() {
            names.append(KnownName(name: alias.name, kind: .counterparty, categoryID: nil))
        }
        return names
    }

    private func searchQuery(_ lower: String, categoryID: Category.ID?, counterpartyName: String?) -> ReportQuery {
        var amount: AmountCondition?
        if let cents = euroCondition(in: lower) {
            if lower.contains("over") || lower.contains("more than") || lower.contains("greater than") {
                amount = .greaterThan(cents)
            } else if lower.contains("under") || lower.contains("less than") {
                amount = .lessThan(cents)
            } else if lower.contains("exactly") {
                amount = .equal(cents)
            }
        }
        return ReportQuery(measure: .spending, categoryID: categoryID, counterpartyName: counterpartyName, amount: amount)
    }

    private func euroCondition(in lower: String) -> Cents? {
        guard let range = lower.range(of: #"\d+(?:[.,]\d{1,2})?"#, options: .regularExpression) else { return nil }
        return Cents(euroText: String(lower[range]))
    }

    private func scoreOperation(_ actual: ReportOperation, _ expected: ReportOperation) -> InterpretationScore {
        switch (actual, expected) {
        case (.total(let actualQuery), .total(let expectedQuery)),
             (.breakdown(let actualQuery), .breakdown(let expectedQuery)),
             (.search(let actualQuery), .search(let expectedQuery)):
            return scoreQuery(actualQuery, expectedQuery, operationMatches: true)
        case (.comparison(let actualMeasure, let actualCategory, let actualName), .comparison(let expectedMeasure, let expectedCategory, let expectedName)):
            var mismatches: [String] = []
            if actualMeasure != expectedMeasure { mismatches.append("measure") }
            if actualCategory != expectedCategory { mismatches.append("category") }
            if actualName != expectedName { mismatches.append("counterparty") }
            return InterpretationScore(operationMatches: true, argumentMismatches: mismatches)
        case (.currentMonthSpending, .currentMonthSpending), (.currentMonthIncome, .currentMonthIncome):
            return InterpretationScore(operationMatches: true, argumentMismatches: [])
        default:
            return InterpretationScore(operationMatches: false, argumentMismatches: ["operation"])
        }
    }

    private func scoreQuery(_ actual: ReportQuery, _ expected: ReportQuery, operationMatches: Bool) -> InterpretationScore {
        var mismatches: [String] = []
        if actual.measure != expected.measure { mismatches.append("measure") }
        if actual.range != expected.range { mismatches.append("range") }
        if actual.categoryID != expected.categoryID { mismatches.append("category") }
        if actual.counterpartyName != expected.counterpartyName { mismatches.append("counterparty") }
        if actual.amount != expected.amount { mismatches.append("amount") }
        if actual.grouping != expected.grouping { mismatches.append("grouping") }
        return InterpretationScore(operationMatches: operationMatches, argumentMismatches: mismatches)
    }
}
