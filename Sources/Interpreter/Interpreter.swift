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

/// Snapshot of ledger metadata passed to a language model backend for interpretation.
public struct InterpretationContext: Sendable {
    public let today: ReportingDate
    public let categories: [Category]
    public let payees: [Payee]
    public let aliasNames: [String]
    public let accounts: [Account]

    public init(
        today: ReportingDate,
        categories: [Category],
        payees: [Payee],
        aliasNames: [String] = [],
        accounts: [Account] = []
    ) {
        self.today = today
        self.categories = categories
        self.payees = payees
        self.aliasNames = aliasNames
        self.accounts = accounts
    }
}

/// Pluggable backend that maps natural-language questions and capture text into structured intents.
public protocol LanguageModelBackend: Sendable {
    var modelUnavailableReason: ModelUnavailableReason? { get }
    func interpretReport(
        _ text: String,
        context: InterpretationContext,
        resolvedName: String?
    ) throws -> ReportInterpretation
    func interpretReportAsync(
        _ text: String,
        context: InterpretationContext,
        resolvedName: String?
    ) async throws -> ReportInterpretation
    func interpretCapture(_ text: String, context: InterpretationContext) throws -> EntryDraft
    func interpretCaptureAsync(_ text: String, context: InterpretationContext) async throws -> EntryDraft
}

public extension LanguageModelBackend {
    func interpretReport(_ text: String, context: InterpretationContext) throws -> ReportInterpretation {
        try interpretReport(text, context: context, resolvedName: nil)
    }

    func interpretReportAsync(
        _ text: String,
        context: InterpretationContext,
        resolvedName: String?
    ) async throws -> ReportInterpretation {
        try interpretReport(text, context: context, resolvedName: resolvedName)
    }

    func interpretCaptureAsync(_ text: String, context: InterpretationContext) async throws -> EntryDraft {
        try interpretCapture(text, context: context)
    }
}

enum InterpreterQueryHelpers {
    private static let mutationVerbs: Set<String> = [
        "add", "record", "delete", "remove", "trash", "restore",
        "edit", "change", "update", "rename", "merge", "import",
    ]

    static func containsMutationVerb(in text: String) -> Bool {
        let tokens = text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        return tokens.contains { mutationVerbs.contains($0) }
    }

    static func matchingKnownNames<T>(
        from items: [T],
        question: String,
        nameOf: (T) -> String
    ) -> [T] {
        let lowerQuestion = question.lowercased()
        let questionTokens = lowerQuestion.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let hits = items.filter { item in
            let lowerName = nameOf(item).lowercased()
            if lowerQuestion.contains(lowerName) { return true }
            return questionTokens.contains { token in lowerName == token || lowerName.hasPrefix(token + " ") }
        }
        return hits.filter { candidate in
            let candidateLower = nameOf(candidate).lowercased()
            return !hits.contains { other in
                let otherName = nameOf(other)
                let otherLower = otherName.lowercased()
                return otherName.count > nameOf(candidate).count
                    && lowerQuestion.contains(otherLower)
                    && otherLower.contains(candidateLower)
            }
        }
    }
}

/// Deterministic keyword-based backend used when an on-device language model is not used.
public struct KeywordLanguageModelBackend: LanguageModelBackend {
    public let modelUnavailableReason: ModelUnavailableReason?

    public init(modelUnavailableReason: ModelUnavailableReason? = .modelNotReady) {
        self.modelUnavailableReason = modelUnavailableReason
    }

    public func interpretReport(
        _ text: String,
        context: InterpretationContext,
        resolvedName: String?
    ) throws -> ReportInterpretation {
        let folded = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !folded.isEmpty else {
            return .unsupported(Interpreter.supportedExplanation)
        }
        if InterpreterQueryHelpers.containsMutationVerb(in: folded) {
            return .unsupported("Ask is read-only and cannot change your data. \(Interpreter.supportedExplanation)")
        }
        let lower = folded.lowercased()

        let names = knownNames(from: context)
        let kept: [KnownName]
        if let resolvedName {
            let target = resolvedName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            kept = names.filter { $0.name.lowercased() == target }
        } else {
            kept = InterpreterQueryHelpers.matchingKnownNames(from: names, question: folded, nameOf: \.name)
            if Set(kept.map { $0.name.lowercased() }).count > 1 {
                let uniqueNames = Set(kept.map(\.name))
                return .clarification(uniqueNames.sorted())
            }
        }

        let categoryID = kept.first { $0.kind == .category }?.categoryID
        let payeeName = kept.first { $0.kind == .payee }?.name
        let measure: Measure = lower.contains("income") || lower.contains("earned") ? .income : .spending

        if lower.contains("vs") || lower.contains("versus") || lower.contains("compared") {
            guard !hasUnsupportedComparisonPeriod(lower) else { return .unsupported(unsupportedComparisonExplanation) }
            return .operation(.comparison(measure: measure, categoryID: categoryID, payeeName: payeeName))
        }

        let range = parsedRange(in: lower, today: context.today)

        if lower.contains("by category") || lower.contains("over month") || lower.contains("each month") || lower.contains("breakdown") {
            let grouping: Grouping = (lower.contains("over month") || lower.contains("each month")) && lower.contains("by category")
                ? .monthAndCategory
                : (lower.contains("over month") || lower.contains("each month") ? .month : .category)
            return .operation(.breakdown(ReportQuery(
                measure: measure,
                range: range,
                categoryID: categoryID,
                payeeName: payeeName,
                grouping: grouping
            )))
        }
        if lower.contains("find") || lower.contains("search") || lower.contains("list") || lower.contains("show")
            || lower.contains("biggest") || lower.contains("largest") || lower.contains("exactly")
            || lower.contains("over ") || lower.contains("under ") || lower.contains("more than") || lower.contains("less than") {
            return .operation(.search(searchQuery(lower, range: range, categoryID: categoryID, payeeName: payeeName)))
        }
        if lower.contains("how much") || lower.contains("total") || lower.contains("spend") || lower.contains("spent")
            || lower.contains("income") || lower.contains("earned") {
            return .operation(.total(ReportQuery(
                measure: measure,
                range: range,
                categoryID: categoryID,
                payeeName: payeeName
            )))
        }
        return .unsupported(Interpreter.supportedExplanation)
    }

    public func interpretCapture(_ text: String, context: InterpretationContext) throws -> EntryDraft {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        let kind: Kind?
        if lower.contains("income") || lower.contains("from ") || lower.contains("refund") {
            kind = .income
        } else if lower.contains("expense") || lower.contains("spent") || lower.contains("paid") {
            kind = .expense
        } else {
            kind = nil
        }
        let amount = firstAmount(in: trimmed)
        let name = capturePayee(in: trimmed)
        let date = captureDate(in: lower, today: context.today)
        let mentionedCategory = context.categories.first { lower.contains($0.name.lowercased()) }
        let payeeDefault = name.flatMap { candidate in
            context.payees.first { $0.name.caseInsensitiveCompare(candidate) == .orderedSame }?.defaultCategory
        }
        let category = mentionedCategory ?? payeeDefault
        let account = context.accounts.sorted { $0.name.count > $1.name.count }.first { account in
            let name = NSRegularExpression.escapedPattern(for: account.name)
            return lower.range(of: "\\b(?:with|using|via)\\s+\(name.lowercased())\\b", options: .regularExpression) != nil
        }
        return EntryDraft(
            amount: amount,
            kind: kind,
            payee: name,
            reportingDate: date,
            categoryID: category?.id,
            accountID: account?.id,
            overridesCategory: mentionedCategory != nil
        )
    }

    private struct KnownName {
        var name: String
        var kind: NameKind
        var categoryID: Category.ID?
    }

    private enum NameKind { case category, payee }

    private func knownNames(from context: InterpretationContext) -> [KnownName] {
        var names = context.categories.map {
            KnownName(name: $0.name, kind: .category, categoryID: $0.id)
        }
        for payee in context.payees {
            names.append(KnownName(name: payee.name, kind: .payee, categoryID: nil))
        }
        for alias in context.aliasNames {
            names.append(KnownName(name: alias, kind: .payee, categoryID: nil))
        }
        return names
    }

    private func parsedRange(in lower: String, today: ReportingDate) -> DateRange? {
        if lower.contains("last month") {
            var year = today.year
            var month = today.month - 1
            if month == 0 {
                month = 12
                year -= 1
            }
            let last = ReportingDate.dayCount(month: month, year: year)
            if let start = ReportingDate(year: year, month: month, day: 1),
               let end = ReportingDate(year: year, month: month, day: last) {
                return DateRange(start: start, end: end)
            }
        }
        if let match = lower.range(of: #"\b\d{4}-\d{2}\b"#, options: .regularExpression) {
            let parts = lower[match].split(separator: "-")
            if parts.count == 2, let year = Int(parts[0]), let month = Int(parts[1]), (1...12).contains(month) {
                let last = ReportingDate.dayCount(month: month, year: year)
                if let start = ReportingDate(year: year, month: month, day: 1),
                   let end = ReportingDate(year: year, month: month, day: last) {
                    return DateRange(start: start, end: end)
                }
            }
        }
        return nil
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

    private func capturePayee(in text: String) -> String? {
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
        for marker in [" yesterday", " today", " on ", " with ", " using ", " via "] {
            if let range = name.lowercased().range(of: marker) {
                name = String(name[..<range.lowerBound])
            }
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func captureDate(in lower: String, today: ReportingDate) -> ReportingDate? {
        if lower.contains("yesterday") { return today.addingDays(-1) }
        if lower.contains("today") { return today }
        if let range = lower.range(of: #"\d{4}-\d{2}-\d{2}"#, options: .regularExpression) {
            return ReportingDate(iso8601: String(lower[range]))
        }
        return nil
    }

    private func searchQuery(
        _ lower: String,
        range: DateRange?,
        categoryID: Category.ID?,
        payeeName: String?
    ) -> ReportQuery {
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
        return ReportQuery(
            measure: .spending,
            range: range,
            categoryID: categoryID,
            payeeName: payeeName,
            amount: amount
        )
    }

    private func euroCondition(in lower: String) -> Cents? {
        guard let range = lower.range(of: #"\d+(?:[.,]\d{1,2})?"#, options: .regularExpression) else { return nil }
        return Cents(euroText: String(lower[range]))
    }
}

public struct Interpreter {
    public let backend: any LanguageModelBackend
    public var modelUnavailableReason: ModelUnavailableReason? { backend.modelUnavailableReason }
    private let ledger: Ledger
    private let today: ReportingDate

    public static let supportedExplanation = """
    Centtrail can answer four kinds of question: a total, a breakdown by month or category, \
    a comparison of this month with last month, and a search for transactions.
    """

    public init(
        ledger: Ledger,
        today: ReportingDate,
        backend: any LanguageModelBackend = AppleFoundationModelBackend()
    ) {
        self.ledger = ledger
        self.today = today
        self.backend = backend
    }

    public init(
        ledger: Ledger,
        today: ReportingDate,
        modelUnavailableReason: ModelUnavailableReason?
    ) {
        self.init(
            ledger: ledger,
            today: today,
            backend: KeywordLanguageModelBackend(modelUnavailableReason: modelUnavailableReason)
        )
    }

    public func interpretReport(_ text: String, resolvedName: String? = nil) throws -> ReportInterpretation {
        let context = try makeContext()
        return try backend.interpretReport(text, context: context, resolvedName: resolvedName)
    }

    public func interpretReportAsync(_ text: String, resolvedName: String? = nil) async throws -> ReportInterpretation {
        let context = try makeContext()
        return try await backend.interpretReportAsync(text, context: context, resolvedName: resolvedName)
    }

    public func interpretCapture(_ text: String, defaults: EntryDraft? = nil) throws -> CaptureInterpretation {
        let context = try makeContext()
        let draft = try backend.interpretCapture(text, context: context)
        return CaptureInterpretation(draft: mergedCapture(draft, defaults: defaults), modelUnavailable: backend.modelUnavailableReason)
    }

    nonisolated(nonsending) public func interpretCaptureAsync(_ text: String, defaults: EntryDraft? = nil) async throws -> CaptureInterpretation {
        let context = try makeContext()
        let draft = try await backend.interpretCaptureAsync(text, context: context)
        return CaptureInterpretation(draft: mergedCapture(draft, defaults: defaults), modelUnavailable: backend.modelUnavailableReason)
    }

    private func mergedCapture(_ mentioned: EntryDraft, defaults: EntryDraft?) -> EntryDraft {
        let defaults = defaults ?? EntryDraft(kind: .expense, reportingDate: today)
        let kind = mentioned.kind ?? defaults.kind
        return EntryDraft(
            amount: mentioned.amount ?? defaults.amount,
            kind: kind,
            payee: mentioned.payee ?? defaults.payee,
            reportingDate: mentioned.reportingDate ?? defaults.reportingDate,
            categoryID: mentioned.categoryID ?? defaults.categoryID,
            accountID: mentioned.accountID ?? defaults.accountID,
            destinationAccountID: kind == .transfer ? (mentioned.destinationAccountID ?? defaults.destinationAccountID) : nil,
            overridesCategory: mentioned.categoryID == nil ? defaults.overridesCategory : mentioned.overridesCategory,
            note: mentioned.note ?? defaults.note
        )
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

    public func makeContext() throws -> InterpretationContext {
        InterpretationContext(
            today: today,
            categories: try ledger.categories(),
            payees: try ledger.payees(),
            aliasNames: try ledger.confirmedAliases().map(\.name),
            accounts: try ledger.accounts()
        )
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
            if actualName != expectedName { mismatches.append("payee") }
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
        if actual.payeeName != expected.payeeName { mismatches.append("payee") }
        if actual.amount != expected.amount { mismatches.append("amount") }
        if actual.grouping != expected.grouping { mismatches.append("grouping") }
        return InterpretationScore(operationMatches: operationMatches, argumentMismatches: mismatches)
    }
}

let unsupportedComparisonExplanation = "Comparisons currently support this month against the same days of last month. Ask for a total or breakdown for another date range."

func hasUnsupportedComparisonPeriod(_ question: String) -> Bool {
    let remainder = question.lowercased()
        .replacingOccurrences(of: "this month", with: "")
        .replacingOccurrences(of: "last month", with: "")
    let pattern = #"\d{4}|\d{1,2}[/.-]\d{1,2}|\b(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?|years?|weeks?|quarters?|days?|months?|today|yesterday|tomorrow|between|since|until)\b"#
    return remainder.range(of: pattern, options: .regularExpression) != nil
}
