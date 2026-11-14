import Ledger
import Testing

@Test func ownerCategoriesAreSeededWithTrimmedNames() throws {
    let ledger = try Ledger.openInMemory()
    let names = try ledger.categories().map(\.name)

    #expect(names == [
        "Anagha",
        "Bureaucracy",
        "Electronics",
        "Entertainment",
        "Flight",
        "Friend",
        "Hotel",
        "Household Requirements",
        "Ishwa",
        "Kindergeld",
        "Kita",
        "Medicine",
        "Reading",
        "Rent",
        "Restaurant",
        "Salary",
        "Savings",
        "Self Care",
        "Shopping",
        "Software",
        "Study",
        "Supermarket",
        "Taxi",
        "Train",
        "Utilities",
        "Vacation",
    ])
}

@Test func addingAndRenamingCategoriesKeepsTransactionClassification() throws {
    let ledger = try Ledger.openInMemory()
    let pets = try ledger.addCategory(name: "  Pets  ", countsAsSpending: true)
    #expect(pets.name == "Pets")
    #expect(pets.countsAsSpending == true)
    #expect(try ledger.categories().contains(pets))

    let date = try #require(ReportingDate(iso8601: "2026-03-10"))
    let recorded = try ledger.record(EntryDraft(
        amount: Cents(1_500),
        kind: .expense,
        payee: "Fressnapf",
        reportingDate: date,
        categoryID: pets.id,
        accountID: try ledger.accounts()[0].id
    ))
    #expect(recorded.category!.id == pets.id)
    #expect(recorded.category!.name == "Pets")

    let renamed = try ledger.renameCategory(id: pets.id, to: "Animals")
    #expect(renamed.id == pets.id)
    #expect(renamed.name == "Animals")

    let fetched = try ledger.transaction(id: recorded.id)
    #expect(fetched.category!.id == pets.id)
    #expect(fetched.category!.name == "Animals")

    let payee = try #require(try ledger.payees().first { $0.name == "Fressnapf" })
    #expect(payee.defaultCategory?.name == "Animals")
}

@Test func removingUnusedCategorySucceedsAndInUseCategoryIsRefusedWithCount() throws {
    let ledger = try Ledger.openInMemory()
    let unused = try ledger.addCategory(name: "Temporary", countsAsSpending: true)
    try ledger.removeCategory(id: unused.id)
    #expect(try !ledger.categories().contains(where: { $0.id == unused.id }))

    let hobbies = try ledger.addCategory(name: "Hobbies", countsAsSpending: true)
    _ = try recordEntry(ledger, cents: 1_000, kind: .expense, payee: "Shop A", date: "2026-03-01", category: "Hobbies")
    let second = try recordEntry(ledger, cents: 2_000, kind: .expense, payee: "Shop B", date: "2026-03-02", category: "Hobbies")
    try ledger.trash(second.id, on: try #require(ReportingDate(iso8601: "2026-03-03")))

    do {
        try ledger.removeCategory(id: hobbies.id)
        Issue.record("Expected removeCategory to refuse when transactions use the category")
    } catch let error as LedgerError {
        #expect(error.message.contains("2"))
        #expect(error.message.lowercased().contains("transaction"))
    }
    #expect(try ledger.categories().contains(where: { $0.id == hobbies.id }))
}

@Test func blankOrDuplicateCategoryNamesAreRefused() throws {
    let ledger = try Ledger.openInMemory()
    #expect(throws: LedgerError.self) {
        try ledger.addCategory(name: "   ", countsAsSpending: true)
    }
    #expect(throws: LedgerError.self) {
        try ledger.addCategory(name: "Supermarket", countsAsSpending: true)
    }
    let custom = try ledger.addCategory(name: "Custom", countsAsSpending: true)
    #expect(throws: LedgerError.self) {
        try ledger.renameCategory(id: custom.id, to: "  ")
    }
    #expect(throws: LedgerError.self) {
        try ledger.renameCategory(id: custom.id, to: "Supermarket")
    }
}
