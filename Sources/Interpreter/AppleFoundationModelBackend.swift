import Foundation
import FoundationModels
import Ledger
import struct Ledger.Category

@Generable(description: "A read-only financial report query or unsupported refusal.")
public struct GeneratedReportIntent: Sendable, Equatable {
    @Generable
    public enum OperationKind: String, Sendable, Equatable {
        case total
        case breakdown
        case comparison
        case search
        case unsupported
    }

    @Generable
    public enum MeasureKind: String, Sendable, Equatable {
        case spending
        case income
    }

    @Generable
    public enum GroupingKind: String, Sendable, Equatable {
        case category
        case month
        case monthAndCategory
    }

    @Generable
    public enum AmountComparisonKind: String, Sendable, Equatable {
        case greaterThan
        case lessThan
        case equal
    }

    @Guide(description: "The report operation kind, or unsupported for mutations or out-of-scope questions.")
    public var operation: OperationKind

    @Guide(description: "Whether the question asks about spending or income.")
    public var measure: MeasureKind

    @Guide(description: "Start date in YYYY-MM-DD format if a period is specified, otherwise nil.")
    public var startDate: String?

    @Guide(description: "End date in YYYY-MM-DD format if a period is specified, otherwise nil.")
    public var endDate: String?

    @Guide(description: "Exact category name from the provided categories list, or nil.")
    public var categoryName: String?

    @Guide(description: "Exact payee or alias name from the provided payees/aliases list, or nil.")
    public var payeeName: String?

    @Guide(description: "Grouping for breakdown operations: category, month, or monthAndCategory.")
    public var grouping: GroupingKind?

    @Guide(description: "Amount filter operator for search operations: greaterThan, lessThan, or equal.")
    public var amountComparison: AmountComparisonKind?

    @Guide(description: "Amount threshold in euros (e.g. 50.0 or 12.50) for search operations, or nil.")
    public var amountEuros: Double?

    @Guide(description: "Plain explanation when operation is unsupported.")
    public var unsupportedReason: String?

    public init(
        operation: OperationKind,
        measure: MeasureKind,
        startDate: String? = nil,
        endDate: String? = nil,
        categoryName: String? = nil,
        payeeName: String? = nil,
        grouping: GroupingKind? = nil,
        amountComparison: AmountComparisonKind? = nil,
        amountEuros: Double? = nil,
        unsupportedReason: String? = nil
    ) {
        self.operation = operation
        self.measure = measure
        self.startDate = startDate
        self.endDate = endDate
        self.categoryName = categoryName
        self.payeeName = payeeName
        self.grouping = grouping
        self.amountComparison = amountComparison
        self.amountEuros = amountEuros
        self.unsupportedReason = unsupportedReason
    }
}

@Generable(description: "Fields extracted from a natural-language expense or income entry.")
public struct GeneratedCaptureDraft: Sendable, Equatable {
    @Generable
    public enum EntryKind: String, Sendable, Equatable {
        case expense
        case income
    }

    @Guide(description: "Amount in euros (positive number), or nil if not stated.")
    public var amountEuros: Double?

    @Guide(description: "Whether this is an expense or income.")
    public var kind: EntryKind

    @Guide(description: "Payee name, or nil if not stated.")
    public var payee: String?

    @Guide(description: "Date in YYYY-MM-DD format, or nil if not stated.")
    public var reportingDate: String?

    @Guide(description: "Exact category name from the provided categories list if explicitly mentioned, or nil.")
    public var categoryName: String?

    @Guide(description: "Optional short note, or nil.")
    public var note: String?

    public init(
        amountEuros: Double? = nil,
        kind: EntryKind = .expense,
        payee: String? = nil,
        reportingDate: String? = nil,
        categoryName: String? = nil,
        note: String? = nil
    ) {
        self.amountEuros = amountEuros
        self.kind = kind
        self.payee = payee
        self.reportingDate = reportingDate
        self.categoryName = categoryName
        self.note = note
    }
}

/// Language model backend backed by Apple's on-device Foundation Models framework,
/// falling back to `KeywordLanguageModelBackend` when the system reports the model unavailable.
public struct AppleFoundationModelBackend: LanguageModelBackend {
    public typealias AvailabilityProvider = @Sendable () -> ModelUnavailableReason?
    public typealias ReportGenerator = @Sendable (String, InterpretationContext) async throws -> GeneratedReportIntent
    public typealias CaptureGenerator = @Sendable (String, InterpretationContext) async throws -> GeneratedCaptureDraft

    private static let mutationVerbs: Set<String> = [
        "add", "record", "delete", "remove", "trash", "restore",
        "edit", "change", "update", "rename", "merge", "import",
    ]

    private let availabilityProvider: AvailabilityProvider
    private let reportGenerator: ReportGenerator?
    private let captureGenerator: CaptureGenerator?

    public init(
        availabilityProvider: @escaping AvailabilityProvider = {
            Self.mapAvailability(SystemLanguageModel.default.availability)
        },
        reportGenerator: ReportGenerator? = nil,
        captureGenerator: CaptureGenerator? = nil
    ) {
        self.availabilityProvider = availabilityProvider
        self.reportGenerator = reportGenerator
        self.captureGenerator = captureGenerator
    }

    public var modelUnavailableReason: ModelUnavailableReason? {
        availabilityProvider()
    }

    public static func mapAvailability(_ availability: SystemLanguageModel.Availability) -> ModelUnavailableReason? {
        switch availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled):
            return .appleIntelligenceOff
        case .unavailable(.modelNotReady):
            return .modelNotReady
        case .unavailable:
            return .modelNotReady
        }
    }

    public func interpretReport(
        _ text: String,
        context: InterpretationContext,
        resolvedName: String?
    ) throws -> ReportInterpretation {
        if let unavailable = modelUnavailableReason {
            return try KeywordLanguageModelBackend(modelUnavailableReason: unavailable)
                .interpretReport(text, context: context, resolvedName: resolvedName)
        }
        return try runBlocking {
            try await interpretReportAsync(text, context: context, resolvedName: resolvedName)
        }
    }

    public func interpretReportAsync(
        _ text: String,
        context: InterpretationContext,
        resolvedName: String?
    ) async throws -> ReportInterpretation {
        if let unavailable = modelUnavailableReason {
            return try KeywordLanguageModelBackend(modelUnavailableReason: unavailable)
                .interpretReport(text, context: context, resolvedName: resolvedName)
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .unsupported(Interpreter.supportedExplanation)
        }

        let tokens = trimmed.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        if tokens.contains(where: { Self.mutationVerbs.contains($0) }) {
            return .unsupported("Ask is read-only and cannot change your data. \(Interpreter.supportedExplanation)")
        }

        let intent: GeneratedReportIntent
        if let reportGenerator {
            intent = try await reportGenerator(trimmed, context)
        } else {
            let prompt = Self.reportPrompt(question: trimmed, context: context, resolvedName: resolvedName)
            let session = LanguageModelSession(instructions: Self.reportInstructions)
            let response = try await session.respond(to: prompt, generating: GeneratedReportIntent.self)
            intent = response.content
        }

        return validateReportIntent(intent, question: trimmed, context: context, resolvedName: resolvedName)
    }

    public func interpretCapture(_ text: String, context: InterpretationContext) throws -> EntryDraft {
        if let unavailable = modelUnavailableReason {
            return try KeywordLanguageModelBackend(modelUnavailableReason: unavailable)
                .interpretCapture(text, context: context)
        }
        return try runBlocking {
            try await interpretCaptureAsync(text, context: context)
        }
    }

    public func interpretCaptureAsync(_ text: String, context: InterpretationContext) async throws -> EntryDraft {
        if let unavailable = modelUnavailableReason {
            return try KeywordLanguageModelBackend(modelUnavailableReason: unavailable)
                .interpretCapture(text, context: context)
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return EntryDraft(reportingDate: context.today)
        }

        let generated: GeneratedCaptureDraft
        if let captureGenerator {
            generated = try await captureGenerator(trimmed, context)
        } else {
            let prompt = Self.capturePrompt(text: trimmed, context: context)
            let session = LanguageModelSession(instructions: Self.captureInstructions)
            let response = try await session.respond(to: prompt, generating: GeneratedCaptureDraft.self)
            generated = response.content
        }

        return validateCaptureDraft(generated, context: context)
    }

    // MARK: - Validation

    func validateReportIntent(
        _ intent: GeneratedReportIntent,
        question: String,
        context: InterpretationContext,
        resolvedName: String?
    ) -> ReportInterpretation {
        if intent.operation == .unsupported {
            let reason = intent.unsupportedReason?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let reason, !reason.isEmpty {
                return .unsupported(reason)
            }
            return .unsupported(Interpreter.supportedExplanation)
        }

        // Validate date range: either both nil (current month default) or both valid YYYY-MM-DD with start.iso8601 <= end.iso8601.
        let range: DateRange?
        switch (trimmedNonEmpty(intent.startDate), trimmedNonEmpty(intent.endDate)) {
        case (nil, nil):
            range = nil
        case (let startStr?, let endStr?):
            guard let start = ReportingDate(iso8601: startStr),
                  let end = ReportingDate(iso8601: endStr),
                  start.iso8601 <= end.iso8601 else {
                return .unsupported("I couldn't understand that date range. Try YYYY-MM-DD or a month like \"last month\".")
            }
            range = DateRange(start: start, end: end)
        default:
            return .unsupported("I couldn't understand that date range. Please specify both a start and end date or omit the period.")
        }

        // Resolve category & payee names, checking for ambiguity unless resolvedName is already chosen.
        let resolution = resolveNames(
            categoryName: trimmedNonEmpty(intent.categoryName),
            payeeName: trimmedNonEmpty(intent.payeeName),
            question: question,
            context: context,
            resolvedName: resolvedName
        )
        let categoryID: Category.ID?
        let payeeName: String?
        switch resolution {
        case .resolved(let resolvedCategoryID, let resolvedPayeeName):
            categoryID = resolvedCategoryID
            payeeName = resolvedPayeeName
        case .clarification(let candidates):
            return .clarification(candidates)
        case .invalid(let explanation):
            return .unsupported(explanation)
        }

        let measure: Measure = intent.measure == .income ? .income : .spending

        switch intent.operation {
        case .total:
            return .operation(.total(ReportQuery(
                measure: measure,
                range: range,
                categoryID: categoryID,
                payeeName: payeeName
            )))

        case .breakdown:
            let grouping: Grouping
            switch intent.grouping {
            case .month:
                grouping = .month
            case .monthAndCategory:
                grouping = .monthAndCategory
            case .category, nil:
                grouping = .category
            }
            return .operation(.breakdown(ReportQuery(
                measure: measure,
                range: range,
                categoryID: categoryID,
                payeeName: payeeName,
                grouping: grouping
            )))

        case .comparison:
            return .operation(.comparison(
                measure: measure,
                categoryID: categoryID,
                payeeName: payeeName
            ))

        case .search:
            let amountCondition: AmountCondition?
            if let comparison = intent.amountComparison {
                guard let euros = intent.amountEuros, euros.isFinite, euros >= 0 else {
                    return .unsupported("I couldn't understand the amount filter in that question.")
                }
                let cents = Cents(Int((euros * 100.0).rounded()))
                switch comparison {
                case .greaterThan:
                    amountCondition = .greaterThan(cents)
                case .lessThan:
                    amountCondition = .lessThan(cents)
                case .equal:
                    amountCondition = .equal(cents)
                }
            } else if let euros = intent.amountEuros {
                guard euros.isFinite, euros >= 0 else {
                    return .unsupported("I couldn't understand the amount filter in that question.")
                }
                amountCondition = .equal(Cents(Int((euros * 100.0).rounded())))
            } else {
                amountCondition = nil
            }
            return .operation(.search(ReportQuery(
                measure: measure,
                range: range,
                categoryID: categoryID,
                payeeName: payeeName,
                amount: amountCondition
            )))

        case .unsupported:
            return .unsupported(Interpreter.supportedExplanation)
        }
    }

    func validateCaptureDraft(
        _ generated: GeneratedCaptureDraft,
        context: InterpretationContext
    ) -> EntryDraft {
        let amount: Cents?
        if let euros = generated.amountEuros, euros.isFinite, euros > 0 {
            amount = Cents(Int((euros * 100.0).rounded()))
        } else {
            amount = nil
        }

        let kind: Kind = generated.kind == .income ? .income : .expense
        let payee = trimmedNonEmpty(generated.payee)
        let reportingDate = trimmedNonEmpty(generated.reportingDate).flatMap { ReportingDate(iso8601: $0) } ?? context.today

        let mentionedCategory = trimmedNonEmpty(generated.categoryName).flatMap { name in
            context.categories.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        }
        let payeeDefault = payee.flatMap { candidate in
            context.payees.first { $0.name.caseInsensitiveCompare(candidate) == .orderedSame }?.defaultCategory
        }
        let category = mentionedCategory ?? payeeDefault

        return EntryDraft(
            amount: amount,
            kind: kind,
            payee: payee,
            reportingDate: reportingDate,
            categoryID: category?.id,
            overridesCategory: mentionedCategory != nil,
            note: trimmedNonEmpty(generated.note)
        )
    }

    private enum NameResolution {
        case resolved(categoryID: Category.ID?, payeeName: String?)
        case clarification([String])
        case invalid(String)
    }

    private func resolveNames(
        categoryName: String?,
        payeeName: String?,
        question: String,
        context: InterpretationContext,
        resolvedName: String?
    ) -> NameResolution {
        if let resolvedName {
            let target = resolvedName.trimmingCharacters(in: .whitespacesAndNewlines)
            if let category = context.categories.first(where: { $0.name.caseInsensitiveCompare(target) == .orderedSame }) {
                return .resolved(categoryID: category.id, payeeName: nil)
            }
            if let payee = context.payees.first(where: { $0.name.caseInsensitiveCompare(target) == .orderedSame }) {
                return .resolved(categoryID: nil, payeeName: payee.name)
            }
            if let alias = context.aliasNames.first(where: { $0.caseInsensitiveCompare(target) == .orderedSame }) {
                return .resolved(categoryID: nil, payeeName: alias)
            }
            return .invalid("I couldn't find \"\(target)\" in your categories or payees.")
        }

        // Check if the question itself contains an ambiguous prefix/token matching multiple known names
        // (e.g., "Amazon" when both "Amazon" and "Amazon Fresh" exist and the user didn't say "Amazon Fresh").
        let lowerQuestion = question.lowercased()
        let questionTokens = lowerQuestion.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let allKnownNames = context.categories.map(\.name) + context.payees.map(\.name) + context.aliasNames
        let hits = allKnownNames.filter { name in
            let lowerName = name.lowercased()
            if lowerQuestion.contains(lowerName) { return true }
            return questionTokens.contains { token in lowerName == token || lowerName.hasPrefix(token + " ") }
        }
        let prunedHits = hits.filter { candidate in
            !hits.contains { other in
                other.count > candidate.count
                    && lowerQuestion.contains(other.lowercased())
                    && other.lowercased().contains(candidate.lowercased())
            }
        }
        let uniquePruned = Array(Set(prunedHits)).sorted()
        if uniquePruned.count > 1 {
            return .clarification(uniquePruned)
        }

        var resolvedCategoryID: Category.ID?
        if let categoryName {
            if let match = context.categories.first(where: { $0.name.caseInsensitiveCompare(categoryName) == .orderedSame }) {
                resolvedCategoryID = match.id
            } else {
                let candidates = matchingCandidates(for: categoryName, in: allKnownNames)
                if candidates.count > 1 {
                    return .clarification(candidates)
                }
                return .invalid("I couldn't find a category named \"\(categoryName)\".")
            }
        }

        var resolvedPayeeName: String?
        if let payeeName {
            if let match = context.payees.first(where: { $0.name.caseInsensitiveCompare(payeeName) == .orderedSame }) {
                resolvedPayeeName = match.name
            } else if let alias = context.aliasNames.first(where: { $0.caseInsensitiveCompare(payeeName) == .orderedSame }) {
                resolvedPayeeName = alias
            } else {
                let candidates = matchingCandidates(for: payeeName, in: allKnownNames)
                if candidates.count > 1 {
                    return .clarification(candidates)
                }
                return .invalid("I couldn't find a payee named \"\(payeeName)\".")
            }
        }

        return .resolved(categoryID: resolvedCategoryID, payeeName: resolvedPayeeName)
    }

    private func matchingCandidates(for query: String, in names: [String]) -> [String] {
        let lower = query.lowercased()
        let matches = names.filter { name in
            let candidate = name.lowercased()
            return candidate.contains(lower) || lower.contains(candidate)
        }
        return Array(Set(matches)).sorted()
    }

    private func trimmedNonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private final class BlockingResultBox<Value: Sendable>: @unchecked Sendable {
        var result: Result<Value, Error>?
    }

    private func runBlocking<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) throws -> T {
        let box = BlockingResultBox<T>()
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            do {
                box.result = .success(try await operation())
            } catch {
                box.result = .failure(error)
            }
            semaphore.signal()
        }
        semaphore.wait()
        return try box.result!.get()
    }

    // MARK: - Prompts

    private static let reportInstructions = """
    You translate personal finance questions into read-only report queries.
    Never invent numbers or execute mutations (add, delete, edit, merge, import).
    For mutation requests or questions outside spending/income totals, breakdowns, comparisons, or transaction searches, return operation = unsupported.
    If no date period is mentioned, leave startDate and endDate nil (which defaults to the current calendar month).
    Only use categoryName from the provided categories list and payeeName from the provided payees/aliases list.
    """

    private static func reportPrompt(
        question: String,
        context: InterpretationContext,
        resolvedName: String?
    ) -> String {
        let categories = context.categories.map(\.name).sorted().joined(separator: ", ")
        let payees = (context.payees.map(\.name) + context.aliasNames).sorted().joined(separator: ", ")
        var prompt = """
        Today: \(context.today.iso8601)
        Categories: \(categories.isEmpty ? "(none)" : categories)
        Payees and aliases: \(payees.isEmpty ? "(none)" : payees)
        Question: \(question)
        """
        if let resolvedName {
            prompt += "\nThe user clarified the name as: \(resolvedName)"
        }
        return prompt
    }

    private static let captureInstructions = """
    You extract structured fields from a short expense or income sentence.
    If no date is mentioned, leave reportingDate nil.
    Only set categoryName if a category from the provided list is explicitly mentioned.
    """

    private static func capturePrompt(text: String, context: InterpretationContext) -> String {
        let categories = context.categories.map(\.name).sorted().joined(separator: ", ")
        return """
        Today: \(context.today.iso8601)
        Categories: \(categories.isEmpty ? "(none)" : categories)
        Entry text: \(text)
        """
    }
}
