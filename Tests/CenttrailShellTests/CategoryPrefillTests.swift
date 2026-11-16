@testable import CenttrailShell
import Foundation
@testable import Ledger
import Testing

@MainActor
private func modelWithReweHistory(clearingDefault: Bool) throws -> (CaptureModel, Ledger) {
    let ledger = try Ledger.openInMemory()
    let supermarket = try #require(try ledger.categories().first { $0.name == "Supermarket" })
    _ = try ledger.record(EntryDraft(
        amount: Cents(2_450),
        kind: .expense,
        payee: "REWE",
        reportingDate: ReportingDate(iso8601: "2026-11-02"),
        categoryID: supermarket.id,
        accountID: try ledger.accounts()[0].id
    ))
    if clearingDefault {
        try ledger.connection.execute("UPDATE counterparty SET default_category_id = NULL")
    }
    let model = try CaptureModel(ledger: ledger, today: try #require(ReportingDate(iso8601: "2026-11-14")))
    model.openAddSheet()
    return (model, ledger)
}

@Suite(.serialized)
struct CategoryPrefillTests {
    @MainActor
    @Test func typingAKnownPayeePreselectsItsCategoryAndTheOwnerCanChangeIt() throws {
        for clearingDefault in [false, true] {
            let (model, ledger) = try modelWithReweHistory(clearingDefault: clearingDefault)
            let supermarket = try #require(try ledger.categories().first { $0.name == "Supermarket" })
            let restaurant = try #require(try ledger.categories().first { $0.name == "Restaurant" })

            model.payee = "Rewe"
            model.prefillCategory()
            #expect(model.categoryID == supermarket.id)

            // The owner overrides the suggestion; later prefills keep the choice.
            model.categoryID = restaurant.id
            model.noteManualCategory()
            model.payee = "Rewe "
            model.prefillCategory()
            #expect(model.categoryID == restaurant.id)
        }
    }

    @MainActor
    @Test func choosingASuggestedOrFrequentPayeePreselectsItsLastUsedCategory() throws {
        let (model, ledger) = try modelWithReweHistory(clearingDefault: true)
        let supermarket = try #require(try ledger.categories().first { $0.name == "Supermarket" })

        model.selectSuggestedPayee("REWE")
        #expect(model.categoryID == supermarket.id)

        model.openAddSheet()
        let frequent = try #require(model.frequentPayees.first { $0.payee.name == "REWE" })
        model.selectFrequentPayee(frequent)
        #expect(model.categoryID == supermarket.id)
    }
}
