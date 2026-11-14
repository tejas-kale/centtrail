import Foundation
import Ledger
import Testing

@Test func editingAnEntryPreservesItsIdentityAndValidatesEveryField() throws {
    let ledger = try Ledger.openInMemory()
    let original = try recordEntry(ledger, cents: 1000, kind: .expense, payee: "REWE", date: "2026-11-01", category: "Supermarket")
    let date = try #require(ReportingDate(iso8601: "2026-11-10"))
    let category = try namedCategory(ledger, "Shopping")
    let accounts = try ledger.accounts()
    let edited = try ledger.update(original.id, with: EntryDraft(amount: Cents(2500), kind: .income, payee: "Shop", reportingDate: date, categoryID: category.id, accountID: accounts[1].id, overridesCategory: true, note: "Correction"))
    #expect(edited.id == original.id)
    #expect(edited.amount == Cents(2500))
    #expect(edited.kind == .income)
    #expect(edited.payee?.name == "Shop")
    #expect(edited.reportingDate == date)
    #expect(edited.account == accounts[1])
    #expect(edited.category == category)
    #expect(edited.categoryProvenance == .overridden)
    #expect(edited.note == "Correction")
    #expect(try ledger.transactions() == [edited])
    #expect(throws: RecordEntryError.incomplete([.amount])) {
        try ledger.update(original.id, with: EntryDraft(kind: .transfer, reportingDate: date, accountID: accounts[0].id, destinationAccountID: accounts[3].id))
    }
    #expect(try ledger.transaction(id: original.id) == edited)
    let transfer = try ledger.update(original.id, with: EntryDraft(amount: Cents(50000), kind: .transfer, reportingDate: date, accountID: accounts[0].id, destinationAccountID: accounts[3].id))
    #expect(transfer.id == original.id)
    #expect(transfer.payee == nil)
    #expect(transfer.category == nil)
    #expect(transfer.destinationAccount == accounts[3])
    #expect(try ledger.runReport(.currentMonthIncome, today: date) == .incomeTotal(SignedCents(0)))
}

@Test func editingKeepsImportIdentityAndInheritedClassification() throws {
    let ledger = try Ledger.openInMemory()
    let csv = """
    Date,Amount,Source Currency,Target Currency,Exchange Rate,Payee,Category,Source Account,Notes
    2026-11-01,-10.00,EUR,EUR,1.0,REWE,Supermarket,N26,Original note
    """
    _ = try ledger.commitImport(csv, acceptedPayees: ["REWE"])
    let entry = try #require(try ledger.transactions().first)
    let updated = try ledger.update(entry.id, with: EntryDraft(amount: Cents(2200), kind: entry.kind, payee: entry.payee?.name, reportingDate: entry.reportingDate, categoryID: entry.category?.id, accountID: entry.account.id, note: entry.note))
    #expect(updated.categoryProvenance == .inherited)
    #expect(updated.note == "Original note")
    #expect(try ledger.previewImport(csv).first?.state == .definiteRepeat)
    try ledger.setDefaultCategory(try namedCategory(ledger, "Shopping").id, for: entry.payee!.id)
    #expect(try ledger.transaction(id: entry.id).category?.name == "Shopping")
}
