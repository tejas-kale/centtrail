import Ledger
import Testing

@Test func reservedUncategorisedCategoryExistsAndNeverBecomesPayeeDefault() throws {
    let ledger = try Ledger.openInMemory()
    let uncategorised = try ledger.uncategorisedCategory()

    #expect(uncategorised.name == "Uncategorised")
    #expect(uncategorised.countsAsSpending == true)
    #expect(try !ledger.categories().contains(where: { $0.id == uncategorised.id }))

    let date = try #require(ReportingDate(iso8601: "2026-11-10"))
    let recorded = try ledger.record(EntryDraft(
        amount: Cents(900),
        kind: .expense,
        payee: "Corner Shop",
        reportingDate: date,
        categoryID: uncategorised.id,
        accountID: try ledger.accounts()[0].id
    ))
    #expect(recorded.payee?.defaultCategory == nil)

    let payee = try #require(recorded.payee as Payee?)
    #expect(throws: LedgerError.self) {
        try ledger.setDefaultCategory(uncategorised.id, for: payee.id)
    }
    #expect(throws: LedgerError.self) {
        try ledger.addCategory(name: "Uncategorised", countsAsSpending: true)
    }
    #expect(throws: LedgerError.self) {
        try ledger.renameCategory(id: uncategorised.id, to: "Other")
    }
    #expect(throws: LedgerError.self) {
        try ledger.removeCategory(id: uncategorised.id)
    }
}

@Test func recordForReviewFlagsEntryUnderUncategorisedAndListsInboxNewestFirst() throws {
    let ledger = try Ledger.openInMemory()
    let account = try ledger.accounts()[0]
    let uncategorised = try ledger.uncategorisedCategory()
    let nov05 = try #require(ReportingDate(iso8601: "2026-11-05"))
    let nov12 = try #require(ReportingDate(iso8601: "2026-11-12"))

    let older = try ledger.recordForReview(EntryDraft(
        amount: Cents(1400),
        kind: .expense,
        payee: "Mystery Cafe",
        reportingDate: nov05,
        accountID: account.id
    ))
    let newerSameDayFirst = try ledger.recordForReview(EntryDraft(
        amount: Cents(2500),
        kind: .income,
        payee: "Friend Refund",
        reportingDate: nov12,
        accountID: account.id
    ))
    let newerSameDaySecond = try ledger.recordForReview(EntryDraft(
        amount: Cents(800),
        kind: .expense,
        payee: "Kiosk",
        reportingDate: nov12,
        accountID: account.id
    ))
    let trashed = try ledger.recordForReview(EntryDraft(
        amount: Cents(500),
        kind: .expense,
        payee: "Mistake",
        reportingDate: nov12,
        accountID: account.id
    ))
    try ledger.trash(trashed.id, on: nov12)

    #expect(older.needsReview == true)
    #expect(older.category == uncategorised)
    #expect(older.payee?.defaultCategory == nil)

    let inbox = try ledger.reviewInbox()
    #expect(inbox.map(\.id) == [newerSameDaySecond.id, newerSameDayFirst.id, older.id])
}

@Test func correctingReviewEntryClearsFlagAndSetsMissingPayeeDefault() throws {
    let ledger = try Ledger.openInMemory()
    let account = try ledger.accounts()[0]
    let supermarket = try #require(try ledger.categories().first { $0.name == "Supermarket" })
    let restaurant = try #require(try ledger.categories().first { $0.name == "Restaurant" })
    let date = try #require(ReportingDate(iso8601: "2026-11-12"))

    let firstReview = try ledger.recordForReview(EntryDraft(
        amount: Cents(1800),
        kind: .expense,
        payee: "Bistro Uno",
        reportingDate: date,
        accountID: account.id
    ))
    try ledger.setCategory(restaurant.id, for: firstReview.id)

    let updatedFirst = try ledger.transaction(id: firstReview.id)
    #expect(updatedFirst.needsReview == false)
    #expect(updatedFirst.category == restaurant)
    #expect(updatedFirst.payee?.defaultCategory == restaurant)
    #expect(try ledger.reviewInbox().isEmpty)

    // Payee already has Restaurant default; correcting another review entry keeps Restaurant default.
    let secondReview = try ledger.recordForReview(EntryDraft(
        amount: Cents(500),
        kind: .expense,
        payee: "Bistro Uno",
        reportingDate: date,
        accountID: account.id
    ))
    let updatedSecond = try ledger.update(secondReview.id, with: EntryDraft(
        amount: Cents(500),
        kind: .expense,
        payee: "Bistro Uno",
        reportingDate: date,
        categoryID: supermarket.id,
        accountID: account.id
    ))
    #expect(updatedSecond.needsReview == false)
    #expect(updatedSecond.category == supermarket)
    #expect(updatedSecond.payee?.defaultCategory == restaurant)
    #expect(try ledger.reviewInbox().isEmpty)
}

@Test func reviewEntriesCountInSpendingAndMonthSummaryIncludesReviewCount() throws {
    let ledger = try Ledger.openInMemory()
    let account = try ledger.accounts()[0]
    let supermarket = try #require(try ledger.categories().first { $0.name == "Supermarket" })
    let oct31 = try #require(ReportingDate(iso8601: "2026-10-31"))
    let nov10 = try #require(ReportingDate(iso8601: "2026-11-10"))
    let today = try #require(ReportingDate(iso8601: "2026-11-15"))

    _ = try recordEntry(ledger, cents: 2000, kind: .expense, payee: "Lidl", date: "2026-11-05", category: "Supermarket")
    let novReviewExpense = try ledger.recordForReview(EntryDraft(
        amount: Cents(1350),
        kind: .expense,
        payee: "Street Stall",
        reportingDate: nov10,
        accountID: account.id
    ))
    _ = try ledger.recordForReview(EntryDraft(
        amount: Cents(5000),
        kind: .income,
        payee: "Side Gig",
        reportingDate: nov10,
        accountID: account.id
    ))
    _ = try ledger.recordForReview(EntryDraft(
        amount: Cents(700),
        kind: .expense,
        payee: "Old Shop",
        reportingDate: oct31,
        accountID: account.id
    ))

    let summary = try ledger.monthSummary(on: today)
    #expect(summary.spendingCents == 3350)
    #expect(summary.reviewCount == 3)
    #expect(try ledger.runReport(.currentMonthSpending, today: today) == .spendingTotal(SignedCents(3350)))

    try ledger.setCategory(supermarket.id, for: novReviewExpense.id)
    let updatedSummary = try ledger.monthSummary(on: today)
    #expect(updatedSummary.spendingCents == 3350)
    #expect(updatedSummary.reviewCount == 2)
}



