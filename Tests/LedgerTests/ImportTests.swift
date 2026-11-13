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
    let names = try ledger.counterparties().map(\.name)
    #expect(names.contains("REWE"))
    #expect(names.contains("WinSIM"))
    #expect(names.contains("REWE ") == false)
    let booking = try #require(try ledger.transactions().first { $0.counterparty.name == "Booking" })
    #expect(booking.note == "For the stay on April 29-30")
    #expect(booking.reportingDate.iso8601 == "2025-02-16")
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
    guard case .needsCorrection(let positive) = preview[2].state else { Issue.record("positive"); return }
    #expect(positive.contains("A positive amount in an expense category is held until the refund and transfer format is confirmed."))
    #expect(preview[3].state == .ready)
    #expect(preview[3].reportingDate == "2026-05-01")
    #expect(preview[4].state == .uncertainMatch)
    #expect(try ledger.commitImport(csv, uncertain: [4: .keep]).importedCount == 2)
    #expect(try ledger.transactions().count == 2)
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
