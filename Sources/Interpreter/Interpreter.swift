import Foundation
import Ledger
import struct Ledger.Category

public enum ModelUnavailableReason: String, Equatable, Sendable {
    case deviceNotEligible
    case appleIntelligenceOff
    case modelNotReady
}

public struct CaptureInterpretation: Equatable, Sendable {
    public var draft: EntryDraft
    public var modelUnavailable: ModelUnavailableReason?
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

/// Pluggable backend that maps capture text into a structured draft.
public protocol LanguageModelBackend: Sendable {
    var modelUnavailableReason: ModelUnavailableReason? { get }
    func interpretCapture(_ text: String, context: InterpretationContext) throws -> EntryDraft
    func interpretCaptureAsync(_ text: String, context: InterpretationContext) async throws -> EntryDraft
}

public extension LanguageModelBackend {
    func interpretCaptureAsync(_ text: String, context: InterpretationContext) async throws -> EntryDraft {
        try interpretCapture(text, context: context)
    }
}

/// Deterministic keyword-based backend used when an on-device language model is not used.
public struct KeywordLanguageModelBackend: LanguageModelBackend {
    public let modelUnavailableReason: ModelUnavailableReason?

    public init(modelUnavailableReason: ModelUnavailableReason? = .modelNotReady) {
        self.modelUnavailableReason = modelUnavailableReason
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

}

public struct Interpreter {
    public let backend: any LanguageModelBackend
    public var modelUnavailableReason: ModelUnavailableReason? { backend.modelUnavailableReason }
    private let ledger: Ledger
    private let today: ReportingDate

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

    public func makeContext() throws -> InterpretationContext {
        InterpretationContext(
            today: today,
            categories: try ledger.categories(),
            payees: try ledger.payees(),
            aliasNames: try ledger.confirmedAliases().map(\.name),
            accounts: try ledger.accounts()
        )
    }

}
