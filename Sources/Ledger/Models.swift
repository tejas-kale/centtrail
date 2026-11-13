import Foundation

public struct Cents: Hashable, Sendable {
    public let value: Int

    public init(_ value: Int) {
        precondition(value >= 0, "An amount is a non-negative number of EUR cents.")
        self.value = value
    }

    /// Parses a non-negative euro amount with at most two decimal places.
    /// A dot or a comma is the decimal separator. "12.50" and "12,50" are 1250 cents.
    public init?(euroText: String) {
        let trimmed = euroText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let separatorCount = trimmed.count(where: { $0 == "." || $0 == "," })
        guard separatorCount <= 1 else { return nil }

        let parts = trimmed.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "." || $0 == "," })
        guard parts.count == 1 || parts.count == 2 else { return nil }
        guard let euros = Self.digits(parts[0]) else { return nil }

        let fraction: Int
        if parts.count == 2 {
            let text = parts[1]
            guard (1...2).contains(text.count), let parsed = Self.digits(text) else { return nil }
            fraction = text.count == 1 ? parsed * 10 : parsed
        } else {
            fraction = 0
        }

        self.init(euros * 100 + fraction)
    }

    private static func digits(_ text: Substring) -> Int? {
        guard !text.isEmpty, text.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(text)
    }
}

public enum Kind: String, Hashable, Sendable {
    case expense
    case income
}

public struct ReportingDate: Hashable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init?(year: Int, month: Int, day: Int) {
        guard (1...12).contains(month), (1...Self.days(in: month, year: year)).contains(day) else {
            return nil
        }
        self.year = year
        self.month = month
        self.day = day
    }

    public init?(iso8601: String) {
        let parts = iso8601.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4,
              parts[1].count == 2,
              parts[2].count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2])
        else {
            return nil
        }
        self.init(year: year, month: month, day: day)
    }

    public var iso8601: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    private static func days(in month: Int, year: Int) -> Int {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12:
            31
        case 4, 6, 9, 11:
            30
        case 2:
            isLeap(year) ? 29 : 28
        default:
            0
        }
    }

    private static func isLeap(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }
}

public struct Counterparty: Hashable, Sendable, Identifiable {
    public let id: ID
    public let name: String

    public struct ID: Hashable, Sendable {
        public let rawValue: UUID

        public init(rawValue: UUID) {
            self.rawValue = rawValue
        }
    }

    public init(id: ID, name: String) {
        self.id = id
        self.name = name
    }
}

public struct Transaction: Hashable, Sendable, Identifiable {
    public let id: ID
    public let amount: Cents
    public let kind: Kind
    public let counterparty: Counterparty
    public let reportingDate: ReportingDate
    public let category: Category

    public struct ID: Hashable, Sendable {
        public let rawValue: UUID

        public init(rawValue: UUID) {
            self.rawValue = rawValue
        }
    }

    public init(
        id: ID,
        amount: Cents,
        kind: Kind,
        counterparty: Counterparty,
        reportingDate: ReportingDate,
        category: Category
    ) {
        self.id = id
        self.amount = amount
        self.kind = kind
        self.counterparty = counterparty
        self.reportingDate = reportingDate
        self.category = category
    }
}

public enum EntryField: String, Hashable, Sendable {
    case amount
    case kind
    case counterparty
    case reportingDate
    case category
}

public enum ReportOperation: Hashable, Sendable {
    case currentMonthSpending
}

public enum ReportResult: Hashable, Sendable {
    case spendingTotal(Cents)
}

public enum RecordEntryError: Error, Equatable {
    case incomplete(Set<EntryField>)
    case unknownCategory
}

public struct EntryDraft: Equatable, Sendable {
    public var amount: Cents?
    public var kind: Kind?
    public var counterparty: String?
    public var reportingDate: ReportingDate?
    public var categoryID: Category.ID?

    public init(
        amount: Cents? = nil,
        kind: Kind? = nil,
        counterparty: String? = nil,
        reportingDate: ReportingDate? = nil,
        categoryID: Category.ID? = nil
    ) {
        self.amount = amount
        self.kind = kind
        self.counterparty = counterparty
        self.reportingDate = reportingDate
        self.categoryID = categoryID
    }
}
