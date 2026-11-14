import Foundation
import Ledger

/// Deterministic reading of the period and grouping words in a question.
///
/// The on-device model is unreliable at date arithmetic ("this year" often comes
/// back as no period, which reports default to the current month), so any period
/// phrase recognised here wins over the model's dates.
enum QuestionPeriod {
    private static let monthNames: [(String, Int)] = [
        ("january", 1), ("february", 2), ("march", 3), ("april", 4), ("may", 5), ("june", 6),
        ("july", 7), ("august", 8), ("september", 9), ("october", 10), ("november", 11), ("december", 12),
        ("jan", 1), ("feb", 2), ("mar", 3), ("apr", 4), ("jun", 6), ("jul", 7), ("aug", 8),
        ("sep", 9), ("sept", 9), ("oct", 10), ("nov", 11), ("dec", 12),
    ]

    /// The date range named in the question, or nil when it names none.
    static func range(in question: String, today: ReportingDate) -> DateRange? {
        let lower = question.lowercased()

        if contains(lower, #"\b(this year|so far this year|year to date|ytd)\b"#) {
            return DateRange(start: ReportingDate(year: today.year, month: 1, day: 1)!, end: today)
        }
        if contains(lower, #"\b(last|previous) year\b"#) {
            return yearRange(today.year - 1)
        }
        if contains(lower, #"\b(this|current) month\b"#) {
            // No range is the current month already; keep it nil so queries stay comparable.
            return nil
        }
        if contains(lower, #"\b(last|previous) month\b"#) {
            let (year, month) = shift(year: today.year, month: today.month, by: -1)
            return monthRange(year: year, month: month)
        }
        if let n = capture(lower, #"\b(?:last|past|previous) (\d{1,2}) months\b"#).flatMap(Int.init), n > 0 {
            // The last N months including the current one: Sep–Nov for "last 3 months" in November.
            let (year, month) = shift(year: today.year, month: today.month, by: -(n - 1))
            return DateRange(start: ReportingDate(year: year, month: month, day: 1)!, end: today)
        }
        if let match = capture(lower, #"\b(\d{4})-(\d{2})\b"#, group: 0) {
            let parts = match.split(separator: "-")
            if let year = Int(parts[0]), let month = Int(parts[1]), (1...12).contains(month) {
                return monthRange(year: year, month: month)
            }
        }
        // Only a year after a month name or a preposition, so "over 2000" stays an amount.
        let year = capture(lower, #"\b(?:in|during|for|of|since|year|jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sept?(?:ember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?) ((?:19|20)\d{2})\b"#).flatMap(Int.init)
        if let month = monthName(in: lower) {
            // A bare month name means its most recent occurrence.
            let resolvedYear = year ?? (month <= today.month ? today.year : today.year - 1)
            return monthRange(year: resolvedYear, month: month)
        }
        if let year {
            return year == today.year
                ? DateRange(start: ReportingDate(year: year, month: 1, day: 1)!, end: today)
                : yearRange(year)
        }
        return nil
    }

    /// The grouping the question asks for, or nil when it asks for none.
    static func grouping(in question: String) -> Grouping? {
        let lower = question.lowercased()
        let monthly = contains(lower, #"\b(each|every|per|by) month\b|\bmonth by month\b|\bover months?\b"#)
        let byCategory = contains(lower, #"\b(by|per|each) category\b|\bcategories\b"#)
        switch (monthly, byCategory) {
        case (true, true): return .monthAndCategory
        case (true, false): return .month
        case (false, true): return .category
        case (false, false): return nil
        }
    }

    private static func monthName(in lower: String) -> Int? {
        for (name, number) in monthNames {
            // "may" is too common a word on its own; only count it next to a year or "in".
            if name == "may" {
                if contains(lower, #"\b(in|of|during) may\b|\bmay \d{4}\b"#) { return number }
                continue
            }
            if contains(lower, "\\b\(name)\\b") { return number }
        }
        return nil
    }

    private static func monthRange(year: Int, month: Int) -> DateRange {
        DateRange(
            start: ReportingDate(year: year, month: month, day: 1)!,
            end: ReportingDate(year: year, month: month, day: ReportingDate.dayCount(month: month, year: year))!
        )
    }

    private static func yearRange(_ year: Int) -> DateRange {
        DateRange(start: ReportingDate(year: year, month: 1, day: 1)!, end: ReportingDate(year: year, month: 12, day: 31)!)
    }

    private static func shift(year: Int, month: Int, by delta: Int) -> (Int, Int) {
        let index = year * 12 + (month - 1) + delta
        return (index / 12, index % 12 + 1)
    }

    private static func contains(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }

    private static func capture(_ text: String, _ pattern: String, group: Int = 1) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: group), in: text) else { return nil }
        return String(text[range])
    }
}
