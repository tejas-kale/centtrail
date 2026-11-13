import Foundation

public struct ImportMapping: Equatable, Sendable {
    public var reportingDateColumn: String

    public init(reportingDateColumn: String = "Date") {
        self.reportingDateColumn = reportingDateColumn
    }
}

public enum ImportRowState: Equatable, Sendable {
    case ready
    case needsCorrection([String])
    case definiteRepeat
    case uncertainMatch
}

public struct ImportRow: Equatable, Sendable, Identifiable {
    public let index: Int
    public let state: ImportRowState
    public let reportingDate: String?
    public let amountText: String?
    public let categoryName: String?
    public let payee: String?

    public var id: Int { index }
}

public enum UncertainDecision: Equatable, Sendable {
    case keep
    case skip
}

public struct ImportCommitResult: Equatable, Sendable {
    public let importedCount: Int
}

private let incomeCategoryNames: Set<String> = ["Salary", "Kindergeld"]

extension Ledger {
    public func previewImport(_ csv: String, mapping: ImportMapping = ImportMapping()) throws -> [ImportRow] {
        try classifiedRows(csv, mapping: mapping).map(\.row)
    }

    public func commitImport(
        _ csv: String,
        mapping: ImportMapping = ImportMapping(),
        uncertain: [Int: UncertainDecision] = [:]
    ) throws -> ImportCommitResult {
        let classified = try classifiedRows(csv, mapping: mapping)
        var imported = 0
        for item in classified {
            switch item.row.state {
            case .ready:
                try commit(item)
                imported += 1
            case .definiteRepeat, .needsCorrection:
                break
            case .uncertainMatch:
                if uncertain[item.row.index] == .keep {
                    try commit(item)
                    imported += 1
                }
            }
        }
        return ImportCommitResult(importedCount: imported)
    }

    private struct ClassifiedImport {
        var row: ImportRow
        var draft: EntryDraft?
        var fingerprint: ImportFingerprint?
    }

    private struct ImportFingerprint {
        var timestamp: String
        var amountCents: Int
        var payee: String
        var sourceAccount: String
        var reportingDate: ReportingDate
        var kind: Kind
        var category: Category
        var note: String?
    }

    private func classifiedRows(_ csv: String, mapping: ImportMapping) throws -> [ClassifiedImport] {
        let table = parseCSV(csv)
        guard let header = table.first else { return [] }
        let records = table.dropFirst()
        let categories = try categories()
        var classified: [ClassifiedImport] = []
        for (offset, record) in records.enumerated() {
            let fields = Dictionary(uniqueKeysWithValues: zip(header, record).map { ($0.0, $0.1) })
            let payee = fields["Payee"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let categoryName = fields["Category"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let amountText = fields["Amount"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let timestamp = fields["Date"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let sourceAccount = fields["Source Account"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let dateText = fields[mapping.reportingDateColumn]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let note = fields["Notes"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            var reasons: [String] = []
            let reportingDate = reportingDate(from: dateText)
            if reportingDate == nil { reasons.append("The reporting date could not be read.") }
            guard let parsedAmount = signedCents(from: amountText) else {
                reasons.append("The amount could not be read.")
                classified.append(ClassifiedImport(
                    row: ImportRow(index: offset, state: .needsCorrection(reasons), reportingDate: reportingDate?.iso8601, amountText: amountText, categoryName: categoryName, payee: payee),
                    draft: nil,
                    fingerprint: nil
                ))
                continue
            }
            if fields["Source Currency"]?.trimmingCharacters(in: .whitespacesAndNewlines) != "EUR"
                || fields["Target Currency"]?.trimmingCharacters(in: .whitespacesAndNewlines) != "EUR"
                || fields["Exchange Rate"]?.trimmingCharacters(in: .whitespacesAndNewlines) != "1.0" {
                reasons.append("Only EUR at rate 1.0 can be imported.")
            }
            let category = categories.first { $0.name == categoryName }
            if category == nil { reasons.append("Unknown category \(categoryName).") }
            if payee.isEmpty { reasons.append("The payee is missing.") }
            let isIncomeCategory = incomeCategoryNames.contains(categoryName)
            if parsedAmount.sign > 0, category != nil, !isIncomeCategory {
                reasons.append("A positive amount in an expense category is held until the refund and transfer format is confirmed.")
            }
            let kind: Kind = parsedAmount.sign < 0 ? .expense : .income
            let rowDate = reportingDate?.iso8601
            if !reasons.isEmpty || category == nil || reportingDate == nil {
                classified.append(ClassifiedImport(
                    row: ImportRow(index: offset, state: .needsCorrection(reasons), reportingDate: rowDate, amountText: amountText, categoryName: categoryName, payee: payee),
                    draft: nil,
                    fingerprint: nil
                ))
                continue
            }
            let fingerprint = ImportFingerprint(
                timestamp: String(timestamp.prefix(19)),
                amountCents: parsedAmount.cents,
                payee: payee,
                sourceAccount: sourceAccount,
                reportingDate: reportingDate!,
                kind: kind,
                category: category!,
                note: note?.isEmpty == true ? nil : note
            )
            let state = try importState(for: fingerprint, earlierInFile: classified)
            let draft = EntryDraft(
                amount: Cents(parsedAmount.cents),
                kind: kind,
                counterparty: payee,
                reportingDate: fingerprint.reportingDate,
                categoryID: category!.id,
                note: fingerprint.note
            )
            classified.append(ClassifiedImport(
                row: ImportRow(index: offset, state: state, reportingDate: rowDate, amountText: amountText, categoryName: categoryName, payee: payee),
                draft: draft,
                fingerprint: fingerprint
            ))
        }
        return classified
    }

    private func importState(for fingerprint: ImportFingerprint, earlierInFile: [ClassifiedImport]) throws -> ImportRowState {
        let definite = try connection.query(
            """
            SELECT id FROM import_row
            WHERE source_timestamp = ? AND amount_cents = ? AND payee = ? AND source_account = ?
            """,
            bindings: [
                .text(fingerprint.timestamp),
                .integer(Int64(fingerprint.amountCents)),
                .text(fingerprint.payee),
                .text(fingerprint.sourceAccount),
            ]
        )
        if !definite.isEmpty { return .definiteRepeat }
        if earlierInFile.contains(where: {
            guard let other = $0.fingerprint else { return false }
            return other.timestamp == fingerprint.timestamp
                && other.amountCents == fingerprint.amountCents
                && other.payee == fingerprint.payee
                && other.sourceAccount == fingerprint.sourceAccount
        }) {
            return .definiteRepeat
        }
        let sameDay = try connection.query(
            """
            SELECT entry.id
            FROM entry
            JOIN counterparty ON counterparty.id = entry.counterparty_id
            WHERE entry.trashed_on IS NULL
              AND entry.reporting_date = ?
              AND entry.amount_cents = ?
              AND counterparty.name = ?
            """,
            bindings: [
                .text(fingerprint.reportingDate.iso8601),
                .integer(Int64(fingerprint.amountCents)),
                .text(fingerprint.payee),
            ]
        )
        if !sameDay.isEmpty { return .uncertainMatch }
        if earlierInFile.contains(where: {
            guard let other = $0.fingerprint, $0.row.state == .ready || $0.row.state == .uncertainMatch else { return false }
            return other.reportingDate == fingerprint.reportingDate
                && other.amountCents == fingerprint.amountCents
                && other.payee == fingerprint.payee
                && other.timestamp != fingerprint.timestamp
        }) {
            return .uncertainMatch
        }
        return .ready
    }

    private func commit(_ item: ClassifiedImport) throws {
        guard let draft = item.draft, let fingerprint = item.fingerprint else { return }
        let recorded = try record(draft)
        try connection.execute(
            """
            INSERT INTO import_row (id, entry_id, source_timestamp, amount_cents, payee, source_account)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(stored(UUID())),
                .text(stored(recorded.id.rawValue)),
                .text(fingerprint.timestamp),
                .integer(Int64(fingerprint.amountCents)),
                .text(fingerprint.payee),
                .text(fingerprint.sourceAccount),
            ]
        )
    }

    private func reportingDate(from text: String) -> ReportingDate? {
        if let date = ReportingDate(iso8601: String(text.prefix(10))), text.count >= 10 {
            return date
        }
        return ReportingDate(iso8601: text)
    }

    private func signedCents(from text: String) -> (sign: Int, cents: Int)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let sign = trimmed.hasPrefix("-") ? -1 : 1
        let digits = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "+-"))
        let parts = digits.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 1 || parts.count == 2 else { return nil }
        guard let euros = Int(parts[0]), parts[0].allSatisfy(\.isNumber) else { return nil }
        let fraction: Int
        if parts.count == 2 {
            guard (1...2).contains(parts[1].count), parts[1].allSatisfy(\.isNumber), let parsed = Int(parts[1]) else { return nil }
            fraction = parts[1].count == 1 ? parsed * 10 : parsed
        } else {
            fraction = 0
        }
        return (sign, euros * 100 + fraction)
    }
}

private func parseCSV(_ text: String) -> [[String]] {
    var rows: [[String]] = []
    var row: [String] = []
    var field = ""
    var inQuotes = false
    var characters = text.makeIterator()
    while let character = characters.next() {
        if inQuotes {
            if character == "\"" {
                inQuotes = false
            } else {
                field.append(character)
            }
        } else if character == "\"" {
            inQuotes = true
        } else if character == "," {
            row.append(field)
            field = ""
        } else if character == "\n" {
            row.append(field)
            rows.append(row)
            row = []
            field = ""
        } else if character != "\r" {
            field.append(character)
        }
    }
    if !field.isEmpty || !row.isEmpty {
        row.append(field)
        rows.append(row)
    }
    return rows
}
