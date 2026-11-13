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
