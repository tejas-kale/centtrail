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
    public let proposedDefaultCategoryName: String?

    public var id: Int { index }

    public init(
        index: Int,
        state: ImportRowState,
        reportingDate: String?,
        amountText: String?,
        categoryName: String?,
        payee: String?,
        proposedDefaultCategoryName: String? = nil
    ) {
        self.index = index
        self.state = state
        self.reportingDate = reportingDate
        self.amountText = amountText
        self.categoryName = categoryName
        self.payee = payee
        self.proposedDefaultCategoryName = proposedDefaultCategoryName
    }
}

public struct ImportCommitResult: Equatable, Sendable {
    public let importedCount: Int
    public let skippedCount: Int
}

public enum UncertainDecision: Hashable, Sendable {
    case keep
    case skip
}

public struct ProposedPayeeDefault: Equatable, Sendable, Identifiable {
    public let payeeID: Payee.ID
    public let payee: String
    public let categoryName: String

    public var id: Payee.ID { payeeID }

    public init(payeeID: Payee.ID, payee: String, categoryName: String) {
        self.payeeID = payeeID
        self.payee = payee
        self.categoryName = categoryName
    }
}

extension Ledger {
    public func previewImport(_ csv: String, mapping: ImportMapping = ImportMapping()) throws -> [ImportRow] {
        try classifiedRows(csv, mapping: mapping).map(\.row)
    }

    public func commitImport(
        _ csv: String,
        mapping: ImportMapping = ImportMapping(),
        uncertain: [Int: UncertainDecision] = [:],
        acceptedPayees: Set<String> = []
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
        for payee in acceptedPayees {
            let name = payee.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let id = try resolvePayeeID(named: name) else { continue }
            if try proposedCategoryID(for: id) != nil {
                try acceptProposedPayeeDefault(for: Payee.ID(rawValue: id))
            }
        }
        return ImportCommitResult(importedCount: imported, skippedCount: classified.count - imported)
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
        let table = try parseCSV(csv)
        guard let rawHeader = table.first else { return [] }
        let header = rawHeader.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !header.contains(""), Set(header).count == header.count else {
            throw LedgerError(message: "The CSV has empty or duplicate column names. Export it again with one unique name per column.")
        }
        let required: Set<String> = ["Date", "Amount", "Payee", "Category", "Source Account", "Source Currency", "Target Currency", "Exchange Rate", mapping.reportingDateColumn]
        let missing = required.subtracting(header).sorted()
        guard missing.isEmpty else {
            throw LedgerError(message: "The CSV is missing columns: \(missing.joined(separator: ", ")). Choose the original export file.")
        }
        let records = table.dropFirst()
        let categories = try categories()
        var classified: [ClassifiedImport] = []
        for (offset, record) in records.enumerated() {
            if record.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { continue }
            guard record.count == header.count else {
                throw LedgerError(message: "CSV row \(offset + 2) has \(record.count) fields; expected \(header.count). Fix the row or export the file again.")
            }
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
            if sourceAccount.isEmpty { reasons.append("The source account is missing.") }
            if parsedAmount.cents == 0 { reasons.append("The amount must be greater than zero.") }
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
            let proposedName = try proposedDefaultName(payee: payee, categoryName: category!.name, earlierInFile: classified)
            let draft = EntryDraft(
                amount: Cents(parsedAmount.cents),
                kind: kind,
                payee: payee,
                reportingDate: fingerprint.reportingDate,
                categoryID: category!.id,
                note: fingerprint.note
            )
            classified.append(ClassifiedImport(
                row: ImportRow(
                    index: offset,
                    state: state,
                    reportingDate: rowDate,
                    amountText: amountText,
                    categoryName: categoryName,
                    payee: payee,
                    proposedDefaultCategoryName: proposedName
                ),
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
              AND (
                counterparty.name = ? COLLATE NOCASE
                OR EXISTS (
                  SELECT 1 FROM counterparty_alias
                  WHERE counterparty_alias.counterparty_id = entry.counterparty_id
                    AND counterparty_alias.name = ? COLLATE NOCASE
                )
              )
            """,
            bindings: [
                .text(fingerprint.reportingDate.iso8601),
                .integer(Int64(fingerprint.amountCents)),
                .text(fingerprint.payee),
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

    private func proposedDefaultName(payee: String, categoryName: String, earlierInFile: [ClassifiedImport]) throws -> String? {
        guard !payee.isEmpty, !categoryName.isEmpty else { return nil }
        if earlierInFile.contains(where: { $0.fingerprint?.payee == payee }) { return nil }
        if try resolvePayeeID(named: payee) != nil { return nil }
        return categoryName
    }

    public func proposedPayeeDefaults() throws -> [ProposedPayeeDefault] {
        let rows = try connection.query(
            """
            SELECT counterparty.id, counterparty.name, category.name
            FROM proposed_payee_default
            JOIN counterparty ON counterparty.id = proposed_payee_default.counterparty_id
            JOIN effective_category AS category ON category.id = proposed_payee_default.category_id
            ORDER BY counterparty.name
            """
        )
        return try rows.map { row in
            guard row.count == 3,
                  let id = row[0].text.flatMap(UUID.init(uuidString:)),
                  let payee = row[1].text,
                  let categoryName = row[2].text
            else {
                throw LedgerError(message: "The ledger returned a proposed default it could not read.")
            }
            return ProposedPayeeDefault(payeeID: Payee.ID(rawValue: id), payee: payee, categoryName: categoryName)
        }
    }

    public func acceptProposedPayeeDefault(for payeeID: Payee.ID) throws {
        guard let categoryID = try proposedCategoryID(for: payeeID.rawValue) else {
            throw LedgerError(message: "That payee has no proposed default.")
        }
        try setDefaultCategory(categoryID, for: payeeID)
    }

    private func commit(_ item: ClassifiedImport) throws {
        guard var draft = item.draft, let fingerprint = item.fingerprint else { return }
        if let existing = try accounts().first(where: { $0.name.caseInsensitiveCompare(fingerprint.sourceAccount) == .orderedSame }) {
            draft.accountID = existing.id
        } else {
            draft.accountID = try addAccount(name: fingerprint.sourceAccount).id
        }
        let recorded = try record(draft, proposeDefaultForNewPayee: true)
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
        let unsigned = trimmed.hasPrefix("-") || trimmed.hasPrefix("+") ? String(trimmed.dropFirst()) : trimmed
        guard let amount = Cents(euroText: unsigned) else { return nil }
        return (sign, amount.value)
    }
}

private func parseCSV(_ text: String) throws -> [[String]] {
    var rows: [[String]] = []
    var row: [String] = []
    var field = ""
    var inQuotes = false
    var closedQuote = false
    let characters = Array(text)
    var index = 0
    while index < characters.count {
        let character = characters[index]
        if inQuotes {
            if character == "\"" {
                if index + 1 < characters.count, characters[index + 1] == "\"" {
                    field.append("\"")
                    index += 1
                } else {
                    inQuotes = false
                    closedQuote = true
                }
            } else { field.append(character) }
        } else if character == "," {
            row.append(field)
            field = ""
            closedQuote = false
        } else if character == "\n" || character == "\r\n" {
            row.append(field)
            rows.append(row)
            row = []
            field = ""
            closedQuote = false
        } else if character == "\r" {
            // Ignore standalone carriage returns from legacy line endings.
        } else if character == "\"", field.isEmpty, !closedQuote {
            inQuotes = true
        } else if closedQuote || character == "\"" {
            throw LedgerError(message: "The CSV has misplaced quotation marks. Export it again with standard CSV quoting.")
        } else { field.append(character) }
        index += 1
    }
    guard !inQuotes else {
        throw LedgerError(message: "The CSV ends inside a quoted field. Export the complete file again.")
    }
    if !field.isEmpty || !row.isEmpty || closedQuote {
        row.append(field)
        rows.append(row)
    }
    return rows
}
