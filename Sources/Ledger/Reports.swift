import Foundation

private let spendingExpression = """
CASE
    WHEN entry.kind = 'expense' AND entry_category.counts_as_spending = 1 THEN entry.amount_cents
    WHEN entry.kind = 'refund' AND entry_category.counts_as_spending = 1 THEN -entry.amount_cents
    ELSE 0
END
"""

private let incomeExpression = """
CASE WHEN entry.kind = 'income' THEN entry.amount_cents ELSE 0 END
"""

extension Ledger {
    func performReport(_ operation: ReportOperation, today: ReportingDate) throws -> ReportResult {
        switch operation {
        case .currentMonthSpending:
            let bounds = monthBounds(containing: today)
            let total = try sum(
                expression: spendingExpression,
                start: bounds.start,
                end: bounds.end,
                endIsExclusive: true,
                categoryID: nil,
                payeeName: nil,
                amount: nil
            )
            return .spendingTotal(SignedCents(total))
        case .currentMonthIncome:
            let bounds = monthBounds(containing: today)
            let total = try sum(
                expression: incomeExpression,
                start: bounds.start,
                end: bounds.end,
                endIsExclusive: true,
                categoryID: nil,
                payeeName: nil,
                amount: nil
            )
            return .incomeTotal(SignedCents(total))
        case .total(let query):
            let range = resolvedRange(query.range, today: today)
            let total = try sum(query: query, range: range)
            return .total(cents: total, range: range)
        case .breakdown(let query):
            let range = resolvedRange(query.range, today: today)
            return .breakdown(try breakdown(query, range: range), range: range)
        case .comparison(let measure, let categoryID, let payeeName):
            return .comparison(try comparison(today: today, measure: measure, categoryID: categoryID, payeeName: payeeName))
        case .search(let query):
            return .transactions(try matchingTransactions(query, today: today))
        }
    }

    func resolvedRange(_ range: DateRange?, today: ReportingDate) -> DateRange {
        if let range { return range }
        let start = ReportingDate(year: today.year, month: today.month, day: 1)!
        let last = ReportingDate.dayCount(month: today.month, year: today.year)
        let end = ReportingDate(year: today.year, month: today.month, day: last)!
        return DateRange(start: start, end: end)
    }

    private func expression(for measure: Measure) -> String {
        switch measure {
        case .spending: spendingExpression
        case .income: incomeExpression
        }
    }

    private func sum(query: ReportQuery, range: DateRange) throws -> Int {
        try sum(
            expression: expression(for: query.measure),
            start: range.start.iso8601,
            end: range.end.iso8601,
            endIsExclusive: false,
            categoryID: query.categoryID,
            payeeName: query.payeeName,
            amount: query.amount
        )
    }

    private func sum(
        expression: String,
        start: String,
        end: String,
        endIsExclusive: Bool,
        categoryID: Category.ID?,
        payeeName: String?,
        amount: AmountCondition?
    ) throws -> Int {
        var sql = """
        SELECT COALESCE(SUM(\(expression)), 0)
        \(reportFrom)
        WHERE entry.trashed_on IS NULL
          AND entry.reporting_date >= ?
          AND entry.reporting_date \(endIsExclusive ? "<" : "<=") ?
        """
        var bindings: [SQLiteValue] = [.text(start), .text(end)]
        appendFilters(&sql, bindings: &bindings, categoryID: categoryID, payeeName: payeeName, amount: amount)
        let rows = try connection.query(sql, bindings: bindings)
        return Int(rows.first?.first?.integer ?? 0)
    }

    private func breakdown(_ query: ReportQuery, range: DateRange) throws -> [BreakdownRow] {
        let grouping = query.grouping ?? .category
        let monthSQL = "substr(entry.reporting_date, 1, 7)"
        let (select, group): (String, String)
        switch grouping {
        case .month:
            select = "\(monthSQL), NULL, SUM(\(expression(for: query.measure)))"
            group = monthSQL
        case .category:
            select = "NULL, entry_category.name, SUM(\(expression(for: query.measure)))"
            group = "entry_category.name"
        case .monthAndCategory:
            select = "\(monthSQL), entry_category.name, SUM(\(expression(for: query.measure)))"
            group = "\(monthSQL), entry_category.name"
        }
        var sql = """
        SELECT \(select)
        \(reportFrom)
        WHERE entry.trashed_on IS NULL
          AND entry.reporting_date >= ?
          AND entry.reporting_date <= ?
        """
        var bindings: [SQLiteValue] = [.text(range.start.iso8601), .text(range.end.iso8601)]
        appendFilters(&sql, bindings: &bindings, categoryID: query.categoryID, payeeName: query.payeeName, amount: query.amount)
        sql += " GROUP BY \(group) ORDER BY 1, 2"
        let rows = try connection.query(sql, bindings: bindings)
        var grouped = rows.compactMap { row -> BreakdownRow? in
            guard let cents = row[2].integer else { return nil }
            return BreakdownRow(month: row[0].text, categoryName: row[1].text, cents: Int(cents))
        }
        if grouping == .month || grouping == .monthAndCategory {
            let present = Set(grouped.compactMap(\.month))
            for month in months(in: range) where !present.contains(month) {
                grouped.append(BreakdownRow(month: month, categoryName: nil, cents: 0))
            }
            grouped.sort { ($0.month ?? "", $0.categoryName ?? "") < ($1.month ?? "", $1.categoryName ?? "") }
        }
        if grouped.isEmpty, grouping == .month {
            grouped = months(in: range).map { BreakdownRow(month: $0, categoryName: nil, cents: 0) }
        }
        return grouped
    }

    private func comparison(
        today: ReportingDate,
        measure: Measure,
        categoryID: Category.ID?,
        payeeName: String?
    ) throws -> ComparisonResult {
        let laterStart = ReportingDate(year: today.year, month: today.month, day: 1)!
        var earlierYear = today.year
        var earlierMonth = today.month - 1
        if earlierMonth == 0 {
            earlierMonth = 12
            earlierYear -= 1
        }
        let earlierDayCount = ReportingDate.dayCount(month: earlierMonth, year: earlierYear)
        let earlierEndDay = min(today.day, earlierDayCount)
        let earlierStart = ReportingDate(year: earlierYear, month: earlierMonth, day: 1)!
        let earlierEnd = ReportingDate(year: earlierYear, month: earlierMonth, day: earlierEndDay)!
        let earlierRange = DateRange(start: earlierStart, end: earlierEnd)
        let laterRange = DateRange(start: laterStart, end: today)
        let query = ReportQuery(measure: measure, categoryID: categoryID, payeeName: payeeName)
        let earlierCents = try sum(query: query, range: earlierRange)
        let laterCents = try sum(query: query, range: laterRange)
        let change = laterCents - earlierCents
        let percentage: Double? = earlierCents == 0 ? nil : (Double(change) / Double(earlierCents)) * 100
        return ComparisonResult(
            earlier: PeriodAmount(range: earlierRange, cents: earlierCents),
            later: PeriodAmount(range: laterRange, cents: laterCents),
            absoluteChangeCents: change,
            percentageChange: percentage,
            unequalLengths: earlierEndDay != today.day
        )
    }

    func matchingTransactions(_ query: ReportQuery, today: ReportingDate) throws -> [Transaction] {
        var sql = """
        \(entrySelectSQL)
        WHERE entry.trashed_on IS NULL
        """
        var bindings: [SQLiteValue] = []
        if let range = query.range {
            sql += " AND entry.reporting_date >= ? AND entry.reporting_date <= ?"
            bindings.append(.text(range.start.iso8601))
            bindings.append(.text(range.end.iso8601))
        }
        _ = today
        appendFilters(&sql, bindings: &bindings, categoryID: query.categoryID, payeeName: query.payeeName, amount: query.amount)
        sql += " ORDER BY entry.reporting_date DESC, entry.rowid DESC"
        return try connection.query(sql, bindings: bindings).map(decodeTransaction)
    }

    private var reportFrom: String {
        """
        FROM entry
        JOIN category AS entry_category ON entry_category.id = entry.category_id
        JOIN counterparty ON counterparty.id = entry.counterparty_id
        """
    }

    private func appendFilters(
        _ sql: inout String,
        bindings: inout [SQLiteValue],
        categoryID: Category.ID?,
        payeeName: String?,
        amount: AmountCondition?
    ) {
        if let categoryID {
            sql += " AND entry.category_id = ?"
            bindings.append(.text(stored(categoryID.rawValue)))
        }
        if let payeeName {
            let trimmed = payeeName.trimmingCharacters(in: .whitespacesAndNewlines)
            sql += """
             AND (
                counterparty.name = ?
                OR EXISTS (
                    SELECT 1 FROM counterparty_alias
                    WHERE counterparty_alias.counterparty_id = counterparty.id
                      AND counterparty_alias.name = ?
                )
             )
            """
            bindings.append(.text(trimmed))
            bindings.append(.text(trimmed))
        }
        if let amount {
            let (operatorSQL, cents) = amountSQL(amount)
            sql += " AND entry.amount_cents \(operatorSQL) ?"
            bindings.append(.integer(Int64(cents)))
        }
    }

    private func amountSQL(_ condition: AmountCondition) -> (String, Int) {
        switch condition {
        case .equal(let cents): ("=", cents.value)
        case .greaterThan(let cents): (">", cents.value)
        case .lessThan(let cents): ("<", cents.value)
        case .atLeast(let cents): (">=", cents.value)
        case .atMost(let cents): ("<=", cents.value)
        }
    }

    private func months(in range: DateRange) -> [String] {
        var year = range.start.year
        var month = range.start.month
        let endKey = String(format: "%04d-%02d", range.end.year, range.end.month)
        var keys: [String] = []
        while keys.count < 240 {
            let key = String(format: "%04d-%02d", year, month)
            keys.append(key)
            if key == endKey { break }
            month += 1
            if month == 13 {
                month = 1
                year += 1
            }
        }
        return keys
    }
}
