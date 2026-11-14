import Ledger
import Testing

@Test func changingAmazonDefaultFromSupermarketToShoppingMovesInheritedButNotOverriddenEntries() throws {
    let ledger = try Ledger.openInMemory()
    let shopping = try namedCategory(ledger, "Shopping")
    let electronics = try namedCategory(ledger, "Electronics")

    let inherited = try recordEntry(ledger, cents: 1200, kind: .expense, payee: "Amazon", date: "2026-01-10", category: "Supermarket")
    let overridden = try recordEntry(ledger, cents: 4500, kind: .expense, payee: "Amazon", date: "2026-01-15", category: "Supermarket")
    try ledger.setCategory(electronics.id, for: overridden.id)

    try ledger.setDefaultCategory(shopping.id, for: inherited.payee!.id)

    let rereadInherited = try ledger.transaction(id: inherited.id)
    let rereadOverridden = try ledger.transaction(id: overridden.id)
    #expect(rereadInherited.category == shopping)
    #expect(rereadInherited.categoryProvenance == .inherited)
    #expect(rereadOverridden.category == electronics)
    #expect(rereadOverridden.categoryProvenance == .overridden)
    #expect(try ledger.defaultCategory(forPayeeName: "Amazon") == shopping)
}

@Test func mergingPayeeMovesTransactionsAndAliasesAndRemovesSource() throws {
    let ledger = try Ledger.openInMemory()
    let amazon = try recordEntry(ledger, cents: 1500, kind: .expense, payee: "Amazon", date: "2026-02-01", category: "Shopping")
    let amzn = try recordEntry(ledger, cents: 2500, kind: .expense, payee: "AMZN MKTP", date: "2026-02-02", category: "Supermarket")
    try ledger.confirmAlias("AMZN*123", of: amzn.payee!.id)

    try ledger.mergePayees(sourceID: amzn.payee!.id, into: amazon.payee!.id)

    #expect(try ledger.payees().map(\.name) == ["Amazon"])
    let moved = try ledger.transaction(id: amzn.id)
    #expect(moved.payee!.id == amazon.payee!.id)
    #expect(moved.payee!.name == "Amazon")

    let aliases = try ledger.confirmedAliases()
    #expect(aliases.contains { $0.name == "AMZN MKTP" && $0.payeeID == amazon.payee!.id })
    #expect(aliases.contains { $0.name == "AMZN*123" && $0.payeeID == amazon.payee!.id })
}

@Test func laterEntryAndImportTypedAsMergedNameResolveToSurvivingPayee() throws {
    let ledger = try Ledger.openInMemory()
    let amazon = try recordEntry(ledger, cents: 1500, kind: .expense, payee: "Amazon", date: "2026-02-01", category: "Shopping")
    let amzn = try recordEntry(ledger, cents: 2500, kind: .expense, payee: "AMZN MKTP", date: "2026-02-02", category: "Shopping")

    try ledger.mergePayees(sourceID: amzn.payee!.id, into: amazon.payee!.id)

    let laterEntry = try recordEntry(ledger, cents: 990, kind: .expense, payee: "AMZN MKTP", date: "2026-02-10", category: "Shopping")
    #expect(laterEntry.payee!.id == amazon.payee!.id)
    #expect(laterEntry.payee!.name == "Amazon")

    let csv = """
    Date,Amount,Source Currency,Target Currency,Exchange Rate,Payee,Category,Source Account,Notes
    2026-03-01T10:00:00+0100,-18.50,EUR,EUR,1.0,AMZN MKTP,Shopping,N26,
    """
    let preview = try ledger.previewImport(csv)
    #expect(preview.first?.proposedDefaultCategoryName == nil)
    let result = try ledger.commitImport(csv)
    #expect(result.importedCount == 1)
    #expect(try ledger.payees().map(\.name) == ["Amazon"])
    #expect(try ledger.proposedPayeeDefaults().isEmpty)

    let imported = try ledger.transactions().first { $0.reportingDate.iso8601 == "2026-03-01" }
    #expect(imported?.payee!.id == amazon.payee!.id)
    #expect(imported?.payee!.name == "Amazon")
}

@Test func mergingPayeeWithProposedDefaultCleansUpProposalAndRejectsSelfMerge() throws {
    let ledger = try Ledger.openInMemory()
    let amazon = try recordEntry(ledger, cents: 1500, kind: .expense, payee: "Amazon", date: "2026-02-01", category: "Shopping")

    let csv = """
    Date,Amount,Source Currency,Target Currency,Exchange Rate,Payee,Category,Source Account,Notes
    2026-02-05T10:00:00+0100,-22.00,EUR,EUR,1.0,AMZN MKTP,Supermarket,N26,
    """
    #expect(try ledger.commitImport(csv).importedCount == 1)
    let proposal = try #require(try ledger.proposedPayeeDefaults().first { $0.payee == "AMZN MKTP" })

    #expect(throws: LedgerError.self) {
        try ledger.mergePayees(sourceID: amazon.payee!.id, into: amazon.payee!.id)
    }

    try ledger.mergePayees(sourceID: proposal.payeeID, into: amazon.payee!.id)
    #expect(try ledger.proposedPayeeDefaults().isEmpty)
    #expect(try ledger.payees().map(\.name) == ["Amazon"])
}
