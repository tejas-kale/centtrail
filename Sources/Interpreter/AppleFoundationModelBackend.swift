import Foundation
import FoundationModels
import Ledger
import struct Ledger.Category

@Generable(description: "Fields extracted from a natural-language expense or income entry.")
public struct GeneratedCaptureDraft: Sendable, Equatable {
    @Generable
    public enum EntryKind: String, Sendable, Equatable {
        case expense
        case income
    }

    @Guide(description: "Amount in euros (positive number), or nil if not stated.")
    public var amountEuros: Double?

    @Guide(description: "Expense or income only if the sentence explicitly indicates one; otherwise nil to keep the form's selected kind.")
    public var kind: EntryKind?

    @Guide(description: "Payee name, or nil if not stated.")
    public var payee: String?

    @Guide(description: "Date in YYYY-MM-DD format, or nil if not stated.")
    public var reportingDate: String?

    @Guide(description: "Exact category name from the provided categories list if explicitly mentioned, or nil.")
    public var categoryName: String?

    @Guide(description: "Exact account name from the provided accounts list if explicitly mentioned, such as Revolut in 'with Revolut'; otherwise nil.")
    public var accountName: String?

    @Guide(description: "Optional short note, or nil.")
    public var note: String?

    public init(
        amountEuros: Double? = nil,
        kind: EntryKind? = nil,
        payee: String? = nil,
        reportingDate: String? = nil,
        categoryName: String? = nil,
        accountName: String? = nil,
        note: String? = nil
    ) {
        self.amountEuros = amountEuros
        self.kind = kind
        self.payee = payee
        self.reportingDate = reportingDate
        self.categoryName = categoryName
        self.accountName = accountName
        self.note = note
    }
}

/// Language model backend backed by Apple's on-device Foundation Models framework,
/// falling back to `KeywordLanguageModelBackend` when the system reports the model unavailable.
public struct AppleFoundationModelBackend: LanguageModelBackend {
    public typealias AvailabilityProvider = @Sendable () -> ModelUnavailableReason?
    public typealias CaptureGenerator = @Sendable (String, InterpretationContext) async throws -> GeneratedCaptureDraft

    private let availabilityProvider: AvailabilityProvider
    private let captureGenerator: CaptureGenerator?

    public init(
        availabilityProvider: @escaping AvailabilityProvider = {
            Self.mapAvailability(SystemLanguageModel.default.availability)
        },
        captureGenerator: CaptureGenerator? = nil
    ) {
        self.availabilityProvider = availabilityProvider
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
            return EntryDraft()
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

    func validateCaptureDraft(
        _ generated: GeneratedCaptureDraft,
        context: InterpretationContext
    ) -> EntryDraft {
        let amount: Cents?
        if let euros = generated.amountEuros, euros > 0 {
            amount = Cents(roundedEuros: euros)
        } else {
            amount = nil
        }

        let kind: Kind? = generated.kind.map { $0 == .income ? .income : .expense }
        let payee = trimmedNonEmpty(generated.payee)
        let reportingDate = trimmedNonEmpty(generated.reportingDate).flatMap { ReportingDate(iso8601: $0) }

        let mentionedCategory = trimmedNonEmpty(generated.categoryName).flatMap { name in
            context.categories.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        }
        let payeeDefault = payee.flatMap { candidate in
            context.payees.first { $0.name.caseInsensitiveCompare(candidate) == .orderedSame }?.defaultCategory
        }
        let category = mentionedCategory ?? payeeDefault
        let account = trimmedNonEmpty(generated.accountName).flatMap { name in
            context.accounts.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        }

        return EntryDraft(
            amount: amount,
            kind: kind,
            payee: payee,
            reportingDate: reportingDate,
            categoryID: category?.id,
            accountID: account?.id,
            overridesCategory: mentionedCategory != nil,
            note: trimmedNonEmpty(generated.note)
        )
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

    private static let captureInstructions = """
    You extract structured fields from a short expense or income sentence.
    Leave unmentioned fields nil so the existing form's values stay unchanged.
    If no date is mentioned, leave reportingDate nil.
    Only set categoryName if a category from the provided list is explicitly mentioned.
    Only set accountName if an account from the provided list is explicitly mentioned.
    Keep the account phrase out of the payee name: '20 euros at Middle Eats with Revolut' means payee Middle Eats and account Revolut.
    """

    private static func capturePrompt(text: String, context: InterpretationContext) -> String {
        let categories = context.categories.map(\.name).sorted().joined(separator: ", ")
        let accounts = context.accounts.map(\.name).sorted().joined(separator: ", ")
        let payees = (context.payees.map(\.name) + context.aliasNames).sorted().joined(separator: ", ")
        return """
        Today: \(context.today.iso8601)
        Categories: \(categories.isEmpty ? "(none)" : categories)
        Accounts: \(accounts.isEmpty ? "(none)" : accounts)
        Payees and aliases: \(payees.isEmpty ? "(none)" : payees)
        Entry text: \(text)
        """
    }
}
