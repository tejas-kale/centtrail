import Foundation
import Ledger
import Testing

@Test func importingTheSampleExportTwiceKeepsTwentyNineEntries() throws {
    let ledger = try Ledger.openInMemory()
    let url = try #require(Bundle.module.url(forResource: "sample-export", withExtension: "csv", subdirectory: "Fixtures"))
    let csv = try String(contentsOf: url, encoding: .utf8)
    let preview = try ledger.previewImport(csv)
    #expect(preview.count == 29)
    #expect(preview.allSatisfy { row in
        if case .ready = row.state { return true }
        return false
    })
    #expect(try ledger.commitImport(csv).importedCount == 29)
    #expect(try ledger.commitImport(csv).importedCount == 0)
    #expect(try ledger.transactions().count == 29)
    let names = try ledger.payees().map(\.name)
    #expect(names.contains("REWE"))
    #expect(names.contains("WinSIM"))
    #expect(names.contains("REWE ") == false)
    #expect(try ledger.defaultCategory(forPayeeName: "ALDI Data and Analytics") == nil)
    #expect(try ledger.defaultCategory(forPayeeName: "Middle Eats") == nil)
    #expect(try ledger.defaultCategory(forPayeeName: "WinSIM") == nil)
    let proposals = try ledger.proposedPayeeDefaults()
    #expect(proposals.first { $0.payee == "ALDI Data and Analytics" }?.categoryName == "Salary")
    #expect(proposals.first { $0.payee == "Middle Eats" }?.categoryName == "Restaurant")
    #expect(proposals.first { $0.payee == "WinSIM" }?.categoryName == "Utilities")
    for proposal in proposals where ["ALDI Data and Analytics", "Middle Eats", "WinSIM"].contains(proposal.payee) {
        try ledger.acceptProposedPayeeDefault(for: proposal.payeeID)
    }
    #expect(try ledger.defaultCategory(forPayeeName: "ALDI Data and Analytics")?.name == "Salary")
    #expect(try ledger.defaultCategory(forPayeeName: "Middle Eats")?.name == "Restaurant")
    #expect(try ledger.defaultCategory(forPayeeName: "WinSIM")?.name == "Utilities")
    let booking = try #require(try ledger.transactions().first { $0.payee!.name == "Booking" })
    #expect(Set(try ledger.transactions().map(\.account.name)) == ["N26", "Revolut", "Cash"])
    #expect(booking.note == "For the stay on April 29-30")
    #expect(booking.reportingDate.iso8601 == "2025-02-16")
    #expect(preview[0].amountText == "4164.84")
}

@Test func importHoldsBadRowsAndAsksAboutUncertainMatches() throws {
    let ledger = try Ledger.openInMemory()
    let csv = """
    Date,Amount,Source Currency,Target Currency,Exchange Rate,Payee,Category,Source Account,Notes
    2026-04-01T10:00:00+0200,-10.00,EUR,EUR,1.0,Cafe,Not A Category,Cash,
    2026-04-01T11:00:00+0200,-5.00,INR,INR,90,Cafe,Restaurant,Cash,
    2026-04-02T09:00:00+0200,12.00,EUR,EUR,1.0,Cafe,Restaurant,Cash,
    2026-05-01T08:00:00-0500,-3.50,EUR,EUR,1.0,REWE ,Supermarket,N26,
    2026-05-01T09:15:00-0500,-3.50,EUR,EUR,1.0,REWE,Supermarket,Cash,
    """
    let preview = try ledger.previewImport(csv)
    guard case .needsCorrection(let unknown) = preview[0].state else { Issue.record("unknown"); return }
    #expect(unknown.contains("Unknown category Not A Category."))
    guard case .needsCorrection(let currency) = preview[1].state else { Issue.record("currency"); return }
    #expect(currency.contains("Only EUR at rate 1.0 can be imported."))
    #expect(preview[2].state == .ready)
    #expect(preview[3].state == .ready)
    #expect(preview[3].reportingDate == "2026-05-01")
    #expect(preview[4].state == .uncertainMatch)
    #expect(try ledger.commitImport(csv, uncertain: [4: .keep]).importedCount == 3)
    #expect(try ledger.transactions().count == 3)
}

@Test func theOwnerCanChooseAnotherReportingDateColumn() throws {
    let ledger = try Ledger.openInMemory()
    let csv = """
    Date,Paid On,Amount,Source Currency,Target Currency,Exchange Rate,Payee,Category,Source Account,Notes
    2026-01-01T00:00:00+0100,2026-04-02,-9.00,EUR,EUR,1.0,REWE,Supermarket,Cash,
    """
    let preview = try ledger.previewImport(csv, mapping: ImportMapping(reportingDateColumn: "Paid On"))
    #expect(preview.first?.reportingDate == "2026-04-02")
}

@Test func aTimestampKeepsTheOffsetDayWhenUtcFallsOnAnotherDay() throws {
    let ledger = try Ledger.openInMemory()
    let csv = """
    Date,Amount,Source Currency,Target Currency,Exchange Rate,Payee,Category,Source Account,Notes
    2026-01-01T00:30:00+0100,-4.50,EUR,EUR,1.0,Night Cafe,Restaurant,Cash,
    2025-12-31T22:30:00-0500,-8.00,EUR,EUR,1.0,Late Market,Supermarket,Cash,
    """
    let preview = try ledger.previewImport(csv)
    #expect(preview.map(\.reportingDate) == ["2026-01-01", "2025-12-31"])
    #expect(preview.map(\.amountText) == ["-4.50", "-8.00"])
    #expect(try ledger.commitImport(csv).importedCount == 2)
    let dates = try ledger.transactions().map(\.reportingDate.iso8601).sorted()
    #expect(dates == ["2025-12-31", "2026-01-01"])
}

@Test func aNewPayeeProposesItsCategoryUntilTheOwnerAccepts() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("ledger.sqlite")
    let csv = """
    Date,Amount,Source Currency,Target Currency,Exchange Rate,Payee,Category,Source Account,Notes
    2026-04-01T10:00:00+0200,-10.00,EUR,EUR,1.0,Cafe,Restaurant,Cash,
    2026-04-02T10:00:00+0200,-12.00,EUR,EUR,1.0,Cafe,Supermarket,Cash,
    2026-04-03T10:00:00+0200,-3.00,EUR,EUR,1.0,AMZN MKTP,Supermarket,N26,
    """
    do {
        let ledger = try Ledger.open(at: url)
        let amazon = try recordEntry(ledger, cents: 500, kind: .expense, payee: "Amazon", date: "2026-03-01", category: "Supermarket")
        try ledger.confirmAlias("AMZN MKTP", of: amazon.payee!.id)
        let preview = try ledger.previewImport(csv)
        #expect(preview[0].proposedDefaultCategoryName == "Restaurant")
        #expect(preview[0].amountText == "-10.00")
        #expect(preview[1].proposedDefaultCategoryName == nil)
        #expect(preview[2].proposedDefaultCategoryName == nil)
        #expect(try ledger.commitImport(csv).importedCount == 3)
        #expect(try ledger.defaultCategory(forPayeeName: "Cafe") == nil)
        #expect(try ledger.proposedPayeeDefaults().map(\.payee) == ["Cafe"])
        #expect(try ledger.proposedPayeeDefaults().map(\.categoryName) == ["Restaurant"])
        let cafeEntries = try ledger.transactions().filter { $0.payee!.name == "Cafe" }
        #expect(cafeEntries.compactMap(\.category?.name).sorted() == ["Restaurant", "Supermarket"])
        #expect(cafeEntries.first { $0.category!.name == "Restaurant" }?.categoryProvenance == .inherited)
        #expect(cafeEntries.first { $0.category!.name == "Supermarket" }?.categoryProvenance == .overridden)
        let aliasEntry = try ledger.transactions().first { $0.reportingDate.iso8601 == "2026-04-03" }
        #expect(aliasEntry?.payee!.id == amazon.payee!.id)
        #expect(aliasEntry?.payee!.defaultCategory?.name == "Supermarket")
    }
    let reopened = try Ledger.open(at: url)
    #expect(try reopened.defaultCategory(forPayeeName: "Cafe") == nil)
    let proposal = try #require(try reopened.proposedPayeeDefaults().first)
    #expect(proposal.payee == "Cafe")
    #expect(proposal.categoryName == "Restaurant")
    try reopened.acceptProposedPayeeDefault(for: proposal.payeeID)
    #expect(try reopened.defaultCategory(forPayeeName: "Cafe")?.name == "Restaurant")
    #expect(try reopened.proposedPayeeDefaults().isEmpty)
    let hotel = try namedCategory(reopened, "Hotel")
    try reopened.setDefaultCategory(hotel.id, for: proposal.payeeID)
    let afterChange = try reopened.transactions().filter { $0.payee!.name == "Cafe" }
    #expect(afterChange.first { $0.categoryProvenance == .inherited }?.category!.name == "Hotel")
    #expect(afterChange.first { $0.categoryProvenance == .overridden }?.category!.name == "Supermarket")
}

@Test func acceptingAProposedDefaultDuringCommitAppliesIt() throws {
    let ledger = try Ledger.openInMemory()
    let csv = """
    Date,Amount,Source Currency,Target Currency,Exchange Rate,Payee,Category,Source Account,Notes
    2026-04-01T10:00:00+0200,-10.00,EUR,EUR,1.0,Cafe,Restaurant,Cash,
    """
    #expect(try ledger.commitImport(csv, acceptedPayees: ["Cafe"]).importedCount == 1)
    #expect(try ledger.defaultCategory(forPayeeName: "Cafe")?.name == "Restaurant")
    #expect(try ledger.proposedPayeeDefaults().isEmpty)
}

@Test func aRefundImportsAsIncomeIntoANewAccountWithoutChangingPreview() throws {
    let ledger = try Ledger.openInMemory()
    let csv = """
    Date,Amount,Source Currency,Target Currency,Exchange Rate,Payee,Category,Source Account,Notes
    2026-11-02T10:00:00+0100,100.00,EUR,EUR,1.0,Amazon,Shopping,New Bank,Refund
    """
    let preview = try ledger.previewImport(csv)
    #expect(preview.first?.state == .ready)
    #expect(try !ledger.accounts().contains { $0.name == "New Bank" })
    #expect(try ledger.commitImport(csv).importedCount == 1)
    let transaction = try #require(try ledger.transactions().first)
    #expect(transaction.kind == .income)
    #expect(transaction.amount == Cents(10000))
    #expect(transaction.account.name == "New Bank")
    #expect(try ledger.commitImport(csv).importedCount == 0)
}

@Test func importSummaryCountsReadyUncertainAndInvalidRows() throws {
    let ledger = try Ledger.openInMemory()
    let csv = """
    Date,Amount,Source Currency,Target Currency,Exchange Rate,Payee,Category,Source Account,Notes
    2026-11-02T10:00:00+0100,-10.00,EUR,EUR,1.0,Cafe,Restaurant,Cash,
    2026-11-02T11:00:00+0100,-10.00,EUR,EUR,1.0,Cafe,Restaurant,Cash,
    2026-11-03T10:00:00+0100,-20.00,INR,INR,90,Cafe,Restaurant,Cash,
    """
    let preview = try ledger.previewImport(csv)
    #expect(preview.map(\.proposedDefaultCategoryName) == ["Restaurant", nil, nil])
    let result = try ledger.commitImport(csv, uncertain: [1: .skip], acceptedPayees: ["Cafe"])
    #expect(result.importedCount == 1)
    #expect(result.skippedCount == 2)
    #expect(try ledger.defaultCategory(forPayeeName: "Cafe")?.name == "Restaurant")
    #expect(try ledger.proposedPayeeDefaults().isEmpty)
}

@Test func importRequiresAnAccountAndAPositiveMagnitude() throws {
    let ledger = try Ledger.openInMemory()
    let csv = """
    Date,Amount,Source Currency,Target Currency,Exchange Rate,Payee,Category,Source Account,Notes
    2026-11-02T10:00:00+0100,-10.00,EUR,EUR,1.0,Cafe,Restaurant,,
    2026-11-02T11:00:00+0100,0.00,EUR,EUR,1.0,Cafe,Restaurant,Cash,
    """
    let preview = try ledger.previewImport(csv)
    #expect(preview.allSatisfy { if case .needsCorrection = $0.state { true } else { false } })
    let result = try ledger.commitImport(csv)
    #expect(result.importedCount == 0)
    #expect(result.skippedCount == 2)
}
