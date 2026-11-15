import Foundation
import Ledger

public enum ModelUnavailableReason: String, Equatable, Sendable {
    case deviceNotEligible
    case appleIntelligenceOff
    case modelNotReady
}

/// Only the three fields voice capture extracts; category and account come from payee memory.
public struct ParsedCapture: Equatable, Sendable {
    public var amount: Cents?
    public var payeeText: String?
    public var reportingDate: ReportingDate?

    public init(
        amount: Cents? = nil,
        payeeText: String? = nil,
        reportingDate: ReportingDate? = nil
    ) {
        self.amount = amount
        self.payeeText = payeeText
        self.reportingDate = reportingDate
    }
}

public struct CaptureInterpretation: Equatable, Sendable {
    public var parsed: ParsedCapture
    public var draft: EntryDraft
    public var missingFields: Set<EntryField>
    public var modelUnavailable: ModelUnavailableReason?
}

/// Snapshot of ledger metadata passed to a language model backend for interpretation.
public struct InterpretationContext: Sendable {
    public let today: ReportingDate
    public let payees: [Payee]
    public let aliasNames: [String]

    public init(
        today: ReportingDate,
        payees: [Payee],
        aliasNames: [String] = []
    ) {
        self.today = today
        self.payees = payees
        self.aliasNames = aliasNames
    }
}

/// Pluggable backend that maps capture text into amount, payee text and date.
public protocol LanguageModelBackend: Sendable {
    var modelUnavailableReason: ModelUnavailableReason? { get }
    func interpretCapture(_ text: String, context: InterpretationContext) throws -> ParsedCapture
    func interpretCaptureAsync(_ text: String, context: InterpretationContext) async throws -> ParsedCapture
}

public extension LanguageModelBackend {
    func interpretCaptureAsync(_ text: String, context: InterpretationContext) async throws -> ParsedCapture {
        try interpretCapture(text, context: context)
    }
}

/// Deterministic keyword-based backend used when an on-device language model is not used.
public struct KeywordLanguageModelBackend: LanguageModelBackend {
    public let modelUnavailableReason: ModelUnavailableReason?

    public init(modelUnavailableReason: ModelUnavailableReason? = .modelNotReady) {
        self.modelUnavailableReason = modelUnavailableReason
    }

    public func interpretCapture(_ text: String, context: InterpretationContext) throws -> ParsedCapture {
        var remaining = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let date = extractDate(from: &remaining, today: context.today)
        let amount = extractAmount(from: &remaining)
        let payee = extractPayee(from: remaining)
        return ParsedCapture(amount: amount, payeeText: payee, reportingDate: date)
    }

    private func extractDate(from text: inout String, today: ReportingDate) -> ReportingDate? {
        let lower = text.lowercased()
        if let range = lower.range(of: #"\b\d{4}-\d{2}-\d{2}\b"#, options: .regularExpression),
           let parsed = ReportingDate(iso8601: String(lower[range])) {
            text.removeSubrange(range)
            return parsed
        }
        if let range = lower.range(of: #"\byesterday\b"#, options: .regularExpression) {
            text.removeSubrange(range)
            return today.addingDays(-1)
        }
        if let range = lower.range(of: #"\btoday\b"#, options: .regularExpression) {
            text.removeSubrange(range)
            return today
        }
        return nil
    }

    private func extractAmount(from text: inout String) -> Cents? {
        let pattern = #"(?:[€₹]\s*)?(\d+(?:[.,]\d{1,2})?)(?:\s*(?:euros?|eur|€|rupees?|inr|₹))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }
        let fullRange = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: fullRange),
              let numberRange = Range(match.range(at: 1), in: text),
              let matchRange = Range(match.range(at: 0), in: text)
        else {
            return nil
        }
        let normalized = text[numberRange].replacingOccurrences(of: ",", with: ".")
        let amount = Cents(euroText: normalized)
        text.removeSubrange(matchRange)
        return amount
    }

    private func extractPayee(from text: String) -> String? {
        var candidate = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = candidate.lowercased()
        if let range = lower.range(of: " at ") {
            candidate = String(candidate[range.upperBound...])
        } else if let range = lower.range(of: " from ") {
            candidate = String(candidate[range.upperBound...])
        }

        let leadingStopWords = ["spent", "paid", "expense", "income", "refund", "at", "from", "for", "to", "on"]
        var changed = true
        while changed {
            changed = false
            candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            for word in leadingStopWords {
                if candidate.lowercased().hasPrefix(word + " ") {
                    candidate.removeFirst(word.count + 1)
                    changed = true
                    break
                } else if candidate.lowercased() == word {
                    candidate = ""
                    changed = true
                    break
                }
            }
        }
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
        let parsed = try backend.interpretCapture(text, context: context)
        return try complete(parsed, defaults: defaults)
    }

    nonisolated(nonsending) public func interpretCaptureAsync(_ text: String, defaults: EntryDraft? = nil) async throws -> CaptureInterpretation {
        let context = try makeContext()
        let parsed = try await backend.interpretCaptureAsync(text, context: context)
        return try complete(parsed, defaults: defaults)
    }

    private func complete(_ parsed: ParsedCapture, defaults: EntryDraft?) throws -> CaptureInterpretation {
        let base = defaults ?? EntryDraft(kind: .expense, reportingDate: today)
        let completion = try ledger.completeDraft(
            amount: parsed.amount,
            payeeText: parsed.payeeText,
            date: parsed.reportingDate,
            defaults: base
        )
        return CaptureInterpretation(
            parsed: parsed,
            draft: completion.draft,
            missingFields: completion.missingFields,
            modelUnavailable: backend.modelUnavailableReason
        )
    }

    public func makeContext() throws -> InterpretationContext {
        InterpretationContext(
            today: today,
            payees: try ledger.payees(),
            aliasNames: try ledger.confirmedAliases().map(\.name)
        )
    }
}
