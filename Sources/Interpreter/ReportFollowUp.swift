import Foundation
import Ledger
import struct Ledger.Category

/// Deterministic reading of short follow-up questions such as "And on software?" or
/// "What about last year?".
///
/// The on-device model sees each question on its own, so a follow-up loses the previous
/// question's period and grouping. A follow-up keeps the previous operation and changes
/// only the subject, period or measure it names.
enum ReportFollowUp {
    static func isFollowUp(_ question: String) -> Bool {
        let lower = question.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return lower.range(
            of: #"^(and|also|what about|how about|same for|same but)\b"#,
            options: .regularExpression
        ) != nil
    }

    static func interpret(
        _ question: String,
        previous: ReportOperation,
        context: InterpretationContext,
        resolvedName: String?
    ) -> ReportInterpretation? {
        guard isFollowUp(question), !InterpreterQueryHelpers.containsMutationVerb(in: question) else { return nil }
        let lower = question.lowercased()

        let subject: Subject?
        if let resolvedName {
            guard let match = subjectNamed(resolvedName, in: context) else {
                return .unsupported("I couldn't find \"\(resolvedName)\" in your categories or payees.")
            }
            subject = match
        } else {
            let names = context.categories.map(\.name) + context.payees.map(\.name) + context.aliasNames
            let hits = Array(Set(InterpreterQueryHelpers.matchingKnownNames(from: names, question: question, nameOf: { $0 }))).sorted()
            if hits.count > 1 { return .clarification(hits) }
            subject = hits.first.flatMap { subjectNamed($0, in: context) }
        }

        let namesPeriod = QuestionPeriod.namesPeriod(in: question, today: context.today)
        let range = QuestionPeriod.range(in: question, today: context.today)

        let measure: Measure?
        if lower.contains("income") || lower.contains("earn") {
            measure = .income
        } else if lower.contains("spen") {
            measure = .spending
        } else {
            measure = nil
        }

        // Nothing recognisable to change: let the model read the question instead.
        guard subject != nil || namesPeriod || measure != nil else { return nil }

        func apply(_ query: ReportQuery) -> ReportQuery {
            var query = query
            if let subject {
                query.categoryID = subject.categoryID
                query.payeeName = subject.payeeName
            }
            if namesPeriod { query.range = range }
            if let measure { query.measure = measure }
            return query
        }

        switch previous {
        case .total(let query):
            return .operation(.total(apply(query)))
        case .breakdown(let query):
            return .operation(.breakdown(apply(query)))
        case .search(let query):
            return .operation(.search(apply(query)))
        case .currentMonthSpending:
            return .operation(.total(apply(ReportQuery(measure: .spending))))
        case .currentMonthIncome:
            return .operation(.total(apply(ReportQuery(measure: .income))))
        case .comparison(let previousMeasure, let categoryID, let payeeName):
            if range != nil { return .unsupported(unsupportedComparisonExplanation) }
            return .operation(.comparison(
                measure: measure ?? previousMeasure,
                categoryID: subject.map(\.categoryID) ?? categoryID,
                payeeName: subject.map(\.payeeName) ?? payeeName
            ))
        }
    }

    private struct Subject {
        var categoryID: Category.ID?
        var payeeName: String?
    }

    private static func subjectNamed(_ name: String, in context: InterpretationContext) -> Subject? {
        let target = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let category = context.categories.first(where: { $0.name.caseInsensitiveCompare(target) == .orderedSame }) {
            return Subject(categoryID: category.id, payeeName: nil)
        }
        if let payee = context.payees.first(where: { $0.name.caseInsensitiveCompare(target) == .orderedSame }) {
            return Subject(categoryID: nil, payeeName: payee.name)
        }
        if let alias = context.aliasNames.first(where: { $0.caseInsensitiveCompare(target) == .orderedSame }) {
            return Subject(categoryID: nil, payeeName: alias)
        }
        return nil
    }
}

public extension Interpreter {
    /// Reads `text` as a follow-up to `previous`, or returns nil when it isn't one.
    func interpretFollowUp(
        _ text: String,
        previous: ReportOperation,
        resolvedName: String? = nil
    ) throws -> ReportInterpretation? {
        ReportFollowUp.interpret(text, previous: previous, context: try makeContext(), resolvedName: resolvedName)
    }
}
