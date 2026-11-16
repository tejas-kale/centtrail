import Foundation
@testable import Ledger
import Testing

/// Simulates a payee whose stored default was lost (cleared by sync or never
/// set by an import) while its entries still carry their categories.
private func clearDefaultCategory(_ ledger: Ledger, payee name: String) throws {
    try ledger.connection.execute(
        "UPDATE counterparty SET default_category_id = NULL WHERE name = ? COLLATE NOCASE",
        bindings: [.text(name)]
    )
}

@Test func knownPayeeSuggestsItsDefaultCategoryCaseInsensitively() throws {
    let ledger = try Ledger.openInMemory()
    _ = try recordEntry(ledger, cents: 2_450, kind: .expense, payee: "REWE", date: "2026-11-02", category: "Supermarket")

    #expect(try ledger.suggestedCategory(forPayeeName: "Rewe")?.name == "Supermarket")
    #expect(try ledger.suggestedCategory(forPayeeName: "  rewe ")?.name == "Supermarket")
}

@Test func payeeWithoutADefaultSuggestsItsLastUsedCategory() throws {
    let ledger = try Ledger.openInMemory()
    _ = try recordEntry(ledger, cents: 2_450, kind: .expense, payee: "REWE", date: "2026-11-02", category: "Restaurant")
    _ = try recordEntry(ledger, cents: 1_200, kind: .expense, payee: "REWE", date: "2026-11-09", category: "Supermarket")
    _ = try recordEntry(ledger, cents: 900, kind: .expense, payee: "REWE", date: "2026-11-05", category: "Shopping")
    try clearDefaultCategory(ledger, payee: "REWE")

    #expect(try ledger.defaultCategory(forPayeeName: "Rewe") == nil)
    #expect(try ledger.suggestedCategory(forPayeeName: "Rewe")?.name == "Supermarket")
}

@Test func lastUsedCategorySkipsTrashedEntriesAndUncategorised() throws {
    let ledger = try Ledger.openInMemory()
    _ = try recordEntry(ledger, cents: 1_200, kind: .expense, payee: "Lidl", date: "2026-11-01", category: "Supermarket")
    let trashed = try recordEntry(ledger, cents: 500, kind: .expense, payee: "Lidl", date: "2026-11-08", category: "Restaurant")
    try ledger.trash(trashed.id, on: try #require(ReportingDate(iso8601: "2026-11-09")))
    _ = try ledger.record(EntryDraft(
        amount: Cents(300),
        kind: .expense,
        payee: "Lidl",
        reportingDate: ReportingDate(iso8601: "2026-11-10"),
        categoryID: try ledger.uncategorisedCategory().id,
        accountID: try ledger.accounts()[0].id
    ))
    try clearDefaultCategory(ledger, payee: "Lidl")

    #expect(try ledger.suggestedCategory(forPayeeName: "Lidl")?.name == "Supermarket")
}

@Test func duplicatePayeesWithTheSameNameStillSuggestACategory() throws {
    let ledger = try Ledger.openInMemory()
    _ = try recordEntry(ledger, cents: 2_450, kind: .expense, payee: "REWE", date: "2026-11-02", category: "Supermarket")
    // A second device or an import created another "Rewe" payee with no default
    // and no entries. Its UUID sorts first, so name resolution picks it.
    try ledger.connection.execute(
        "INSERT INTO counterparty (id, name, default_category_id) VALUES (?, ?, NULL)",
        bindings: [.text("00000000-0000-0000-0000-000000000001"), .text("Rewe")]
    )

    #expect(try ledger.suggestedCategory(forPayeeName: "Rewe")?.name == "Supermarket")
}

@Test func unknownPayeeSuggestsNothing() throws {
    let ledger = try Ledger.openInMemory()
    _ = try recordEntry(ledger, cents: 2_450, kind: .expense, payee: "REWE", date: "2026-11-02", category: "Supermarket")

    #expect(try ledger.suggestedCategory(forPayeeName: "Edeka") == nil)
    #expect(try ledger.suggestedCategory(forPayeeName: "") == nil)
}

@Test func explicitCategoryOverrideSurvivesDraftCompletionForAPayeeWithoutADefault() throws {
    let ledger = try Ledger.openInMemory()
    _ = try recordEntry(ledger, cents: 2_450, kind: .expense, payee: "REWE", date: "2026-11-02", category: "Supermarket")
    try clearDefaultCategory(ledger, payee: "REWE")
    let restaurant = try namedCategory(ledger, "Restaurant")

    let completion = try ledger.completeDraft(
        amount: Cents(900),
        payeeText: "Rewe",
        date: ReportingDate(iso8601: "2026-11-10"),
        defaults: EntryDraft(categoryID: restaurant.id, overridesCategory: true)
    )
    #expect(completion.draft.categoryID == restaurant.id)
    #expect(completion.draft.overridesCategory)

    let suggested = try ledger.completeDraft(amount: Cents(900), payeeText: "Rewe", date: ReportingDate(iso8601: "2026-11-10"))
    #expect(suggested.draft.categoryID == (try namedCategory(ledger, "Supermarket")).id)
}
