import Foundation
import FoundationModels
import Ledger

@Generable(description: "Amount, payee and date extracted from a short spoken transaction.")
public struct GeneratedCaptureDraft: Sendable, Equatable {
    @Guide(description: "Amount as a positive decimal number, or nil if not stated.")
    public var amountEuros: Double?

    @Guide(description: "Payee name, or nil if not stated.")
    public var payee: String?

    @Guide(description: "Date in YYYY-MM-DD format (resolve relative dates like 'yesterday' against Today), or nil if not stated.")
    public var reportingDate: String?

    public init(
        amountEuros: Double? = nil,
        payee: String? = nil,
        reportingDate: String? = nil
    ) {
        self.amountEuros = amountEuros
        self.payee = payee
        self.reportingDate = reportingDate
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

    public func interpretCapture(_ text: String, context: InterpretationContext) throws -> ParsedCapture {
        if let unavailable = modelUnavailableReason {
            return try KeywordLanguageModelBackend(modelUnavailableReason: unavailable)
                .interpretCapture(text, context: context)
        }
        return try runBlocking {
            try await interpretCaptureAsync(text, context: context)
        }
    }

    public func interpretCaptureAsync(_ text: String, context: InterpretationContext) async throws -> ParsedCapture {
        if let unavailable = modelUnavailableReason {
            return try KeywordLanguageModelBackend(modelUnavailableReason: unavailable)
                .interpretCapture(text, context: context)
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ParsedCapture()
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

        return validateParsedCapture(generated)
    }

    // MARK: - Validation

    func validateParsedCapture(_ generated: GeneratedCaptureDraft) -> ParsedCapture {
        let amount: Cents?
        if let euros = generated.amountEuros, euros > 0 {
            amount = Cents(roundedEuros: euros)
        } else {
            amount = nil
        }

        let payee = trimmedNonEmpty(generated.payee)
        let reportingDate = trimmedNonEmpty(generated.reportingDate).flatMap { ReportingDate(iso8601: $0) }

        return ParsedCapture(
            amount: amount,
            payeeText: payee,
            reportingDate: reportingDate
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
    You extract only amount, payee, and date from a short spoken transaction.
    Leave unmentioned fields nil.
    If no date is mentioned, leave reportingDate nil.
    Resolve relative dates such as "yesterday" or "today" against Today into YYYY-MM-DD.
    Prefer matching a payee or alias from the provided list when spoken.
    """

    private static func capturePrompt(text: String, context: InterpretationContext) -> String {
        let payees = (context.payees.map(\.name) + context.aliasNames).sorted().joined(separator: ", ")
        return """
        Today: \(context.today.iso8601)
        Payees and aliases: \(payees.isEmpty ? "(none)" : payees)
        Entry text: \(text)
        """
    }
}
