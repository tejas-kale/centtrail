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
    case transfer
}

public enum CategoryProvenance: String, Hashable, Sendable {
    case inherited
    case overridden
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

    public static func dayCount(month: Int, year: Int) -> Int {
        days(in: month, year: year)
    }

    public func addingDays(_ days: Int) -> ReportingDate? {
        let shifted = julianDay + days
        return ReportingDate(julianDay: shifted)
    }

    public func wholeDays(until other: ReportingDate) -> Int {
        other.julianDay - julianDay
    }

    private var julianDay: Int {
        let a = (14 - month) / 12
        let y = year + 4800 - a
        let m = month + 12 * a - 3
        return day + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045
    }

    private init?(julianDay value: Int) {
        let j = value + 32044
        let g = j / 146097
        let dg = j % 146097
        let c = (dg / 36524 + 1) * 3 / 4
        let dc = dg - c * 36524
        let b = dc / 1461
        let db = dc % 1461
        let a = (db / 365 + 1) * 3 / 4
        let da = db - a * 365
        let y = g * 400 + c * 100 + b * 4 + a
        let m = (da * 5 + 308) / 153 - 2
        let d = da - (m + 4) * 153 / 5 + 122
        let year = y - 4800 + (m + 2) / 12
        let month = (m + 2) % 12 + 1
        let day = d + 1
        self.init(year: year, month: month, day: day)
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

public struct Payee: Hashable, Sendable, Identifiable {
    public let id: ID
    public let name: String
    public let defaultCategory: Category?

    public struct ID: Hashable, Sendable {
        public let rawValue: UUID

        public init(rawValue: UUID) {
            self.rawValue = rawValue
        }
    }

    public init(id: ID, name: String, defaultCategory: Category?) {
        self.id = id
        self.name = name
        self.defaultCategory = defaultCategory
    }
}

public struct Transaction: Hashable, Sendable, Identifiable {
    public let id: ID
    public let amount: Cents
    public let kind: Kind
    public let payee: Payee
    public let reportingDate: ReportingDate
    public let category: Category
    public let categoryProvenance: CategoryProvenance
    public let note: String?

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
        payee: Payee,
        reportingDate: ReportingDate,
        category: Category,
        categoryProvenance: CategoryProvenance = .inherited,
        note: String? = nil
    ) {
        self.id = id
        self.amount = amount
        self.kind = kind
        self.payee = payee
        self.reportingDate = reportingDate
        self.category = category
        self.categoryProvenance = categoryProvenance
        self.note = note
    }
}

public enum EntryField: String, Hashable, Sendable {
    case amount
    case kind
    case payee
    case reportingDate
    case category
}

public struct SignedCents: Hashable, Sendable {
    public let value: Int

    public init(_ value: Int) {
        self.value = value
    }
}

public struct DateRange: Hashable, Sendable {
    public let start: ReportingDate
    public let end: ReportingDate

    public init(start: ReportingDate, end: ReportingDate) {
        self.start = start
        self.end = end
    }
}

public enum Measure: Hashable, Sendable {
    case spending
    case income
}

public enum AmountCondition: Hashable, Sendable {
    case equal(Cents)
    case greaterThan(Cents)
    case lessThan(Cents)
    case atLeast(Cents)
    case atMost(Cents)
}

public enum Grouping: Hashable, Sendable {
    case month
    case category
    case monthAndCategory
}

public struct ReportQuery: Hashable, Sendable {
    public var measure: Measure
    public var range: DateRange?
    public var categoryID: Category.ID?
    public var payeeName: String?
    public var amount: AmountCondition?
    public var grouping: Grouping?

    public init(
        measure: Measure,
        range: DateRange? = nil,
        categoryID: Category.ID? = nil,
        payeeName: String? = nil,
        amount: AmountCondition? = nil,
        grouping: Grouping? = nil
    ) {
        self.measure = measure
        self.range = range
        self.categoryID = categoryID
        self.payeeName = payeeName
        self.amount = amount
        self.grouping = grouping
    }
}

public enum ReportOperation: Hashable, Sendable {
    case currentMonthSpending
    case currentMonthIncome
    case total(ReportQuery)
    case breakdown(ReportQuery)
    case comparison(measure: Measure, categoryID: Category.ID?, payeeName: String?)
    case search(ReportQuery)
}

public struct BreakdownRow: Hashable, Sendable, Identifiable {
    public var id: String { "\(month ?? "")|\(categoryName ?? "")" }
    public let month: String?
    public let categoryName: String?
    public let cents: Int

    public init(month: String?, categoryName: String?, cents: Int) {
        self.month = month
        self.categoryName = categoryName
        self.cents = cents
    }
}

public struct PeriodAmount: Hashable, Sendable {
    public let range: DateRange
    public let cents: Int

    public init(range: DateRange, cents: Int) {
        self.range = range
        self.cents = cents
    }
}

public struct ComparisonResult: Hashable, Sendable {
    public let earlier: PeriodAmount
    public let later: PeriodAmount
    public let absoluteChangeCents: Int
    public let percentageChange: Double?
    public let unequalLengths: Bool

    public init(
        earlier: PeriodAmount,
        later: PeriodAmount,
        absoluteChangeCents: Int,
        percentageChange: Double?,
        unequalLengths: Bool
    ) {
        self.earlier = earlier
        self.later = later
        self.absoluteChangeCents = absoluteChangeCents
        self.percentageChange = percentageChange
        self.unequalLengths = unequalLengths
    }
}

public enum ReportResult: Hashable, Sendable {
    case spendingTotal(SignedCents)
    case incomeTotal(SignedCents)
    case total(cents: Int, range: DateRange)
    case breakdown([BreakdownRow], range: DateRange)
    case comparison(ComparisonResult)
    case transactions([Transaction])
}

public enum RecordEntryError: Error, Equatable {
    case incomplete(Set<EntryField>)
    case unknownCategory
    case unknownEntry
}

public struct EntryDraft: Equatable, Sendable {
    public var amount: Cents?
    public var kind: Kind?
    public var payee: String?
    public var reportingDate: ReportingDate?
    public var categoryID: Category.ID?

    public init(
        amount: Cents? = nil,
        kind: Kind? = nil,
        payee: String? = nil,
        reportingDate: ReportingDate? = nil,
        categoryID: Category.ID? = nil,
        overridesCategory: Bool = false,
        note: String? = nil
    ) {
        self.amount = amount
        self.kind = kind
        self.payee = payee
        self.reportingDate = reportingDate
        self.categoryID = categoryID
        self.overridesCategory = overridesCategory
        self.note = note
    }

    public var overridesCategory: Bool
    public var note: String?
}
