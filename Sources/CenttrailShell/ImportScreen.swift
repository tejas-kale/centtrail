import Foundation
import Ledger
import SwiftUI
import UniformTypeIdentifiers

struct ImportScreen: View {
    @ObservedObject var model: CaptureModel
    @State private var isChoosingFile = false
    @State private var offeredFilePicker = false
    @State private var filename: String?
    @State private var csv = ""
    @State private var dateColumn = "Date"
    @State private var rows: [ImportRow] = []
    @State private var proposals: [ProposedPayeeDefault] = []
    @State private var acceptedPayees: Set<String> = []
    @State private var decisions: [Int: UncertainDecision] = [:]
    @State private var message: String?
    @State private var isError = false

    private var unresolvedMatches: Bool {
        rows.contains { $0.state == .uncertainMatch && decisions[$0.index] == nil }
    }

    private var hasRowsToImport: Bool {
        rows.contains { $0.state == .ready || ($0.state == .uncertainMatch && decisions[$0.index] == .keep) }
    }

    private var readyCount: Int { rows.filter { $0.state == .ready }.count }
    private var uncertainRows: [ImportRow] { rows.filter { $0.state == .uncertainMatch } }
    private var definiteRepeatRows: [ImportRow] { rows.filter { $0.state == .definiteRepeat } }
    private var correctionRows: [ImportRow] {
        rows.filter { if case .needsCorrection = $0.state { true } else { false } }
    }

    private var keptUncertainCount: Int {
        uncertainRows.filter { decisions[$0.index] == .keep }.count
    }

    /// One entry per payee, in first-seen order, so the list stays short even
    /// when a payee appears on many rows.
    private var payeeDefaults: [PayeeDefaultChoice] {
        var seen: Set<String> = []
        var choices: [PayeeDefaultChoice] = []
        for row in rows {
            guard let payee = row.payee, let category = row.proposedDefaultCategoryName,
                  seen.insert(payee).inserted else { continue }
            choices.append(PayeeDefaultChoice(payee: payee, categoryName: category))
        }
        return choices
    }

    private var earlierProposals: [ProposedPayeeDefault] {
        let current = Set(payeeDefaults.map(\.payee))
        return proposals.filter { !current.contains($0.payee) }
    }

    var body: some View {
        Form {
            Section {
                Button("Choose CSV file", systemImage: "doc") { isChoosingFile = true }
                if let filename { Text(filename).foregroundStyle(.secondary) }
                if let message { Text(message).foregroundStyle(isError ? .red : .secondary) }
            }
            if filename != nil && !rows.isEmpty {
                Section {
                    LabeledContent("Transactions to import", value: String(readyCount + keptUncertainCount))
                    if !payeeDefaults.isEmpty {
                        NavigationLink {
                            PayeeDefaultsSelection(choices: payeeDefaults, accepted: $acceptedPayees)
                        } label: {
                            LabeledContent("Payee defaults",
                                value: "\(acceptedPayees.intersection(payeeDefaults.map(\.payee)).count) of \(payeeDefaults.count)")
                        }
                    }
                    Button("Import transactions", action: commit)
                        .disabled(unresolvedMatches || !hasRowsToImport)
                } footer: {
                    if unresolvedMatches {
                        Text("Choose Keep or Skip for each possible duplicate below before importing.")
                    } else if !payeeDefaults.isEmpty {
                        Text("Payees are saved with their category so future entries fill it in. Open Payee defaults to leave some out.")
                    }
                }
                if !uncertainRows.isEmpty {
                    Section {
                        ForEach(uncertainRows) { row in
                            VStack(alignment: .leading, spacing: 6) {
                                rowSummary(row)
                                Picker("Decision", selection: Binding(
                                    get: { decisions[row.index] },
                                    set: { decisions[row.index] = $0 }
                                )) {
                                    Text("Choose").tag(Optional<UncertainDecision>.none)
                                    Text("Keep").tag(Optional(UncertainDecision.keep))
                                    Text("Skip").tag(Optional(UncertainDecision.skip))
                                }
                                .pickerStyle(.segmented)
                            }
                        }
                    } header: {
                        Text("Possible duplicates")
                    } footer: {
                        Text("These look like transactions already in your ledger.")
                    }
                }
                if !definiteRepeatRows.isEmpty {
                    Section {
                        DisclosureGroup("\(definiteRepeatRows.count) already imported — will be skipped") {
                            ForEach(definiteRepeatRows) { rowSummary($0) }
                        }
                    }
                }
                if !correctionRows.isEmpty {
                    Section {
                        DisclosureGroup("\(correctionRows.count) can't be imported") {
                            ForEach(correctionRows) { row in
                                VStack(alignment: .leading, spacing: 4) {
                                    rowSummary(row)
                                    Text(stateLabel(row.state)).font(.footnote).foregroundStyle(.red)
                                }
                            }
                        }
                    }
                }
                Section {
                    TextField("Reporting date column", text: $dateColumn)
                        .onSubmit { preview() }
                    Button("Update preview", action: preview)
                } header: {
                    Text("Options")
                }
            }
            if !earlierProposals.isEmpty {
                Section("Unaccepted payee defaults") {
                    ForEach(earlierProposals) { proposal in
                        VStack(alignment: .leading) {
                            Text("\(proposal.payee): \(proposal.categoryName)")
                            Button("Accept default") { accept(proposal) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Import CSV")
        .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
            load(result)
        }
        .onAppear {
            guard !offeredFilePicker else { return }
            offeredFilePicker = true
            isChoosingFile = true
        }
    }

    private func load(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let contents = try String(contentsOf: url, encoding: .utf8)
            csv = contents
            filename = url.lastPathComponent
            decisions = [:]
            preview()
            // Default to remembering every payee:category pairing in the file.
            acceptedPayees = Set(payeeDefaults.map(\.payee))
        } catch {
            message = "The CSV file could not be opened. Choose a readable UTF-8 CSV file. \(error.localizedDescription)"
            isError = true
        }
    }

    private func rowSummary(_ row: ImportRow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(row.payee ?? "Unknown payee") · \(row.amountText ?? "Unknown amount")")
            Text("\(row.categoryName ?? "") · \(row.reportingDate ?? "Unknown date")")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func refreshPreview() throws {
        rows = try model.ledger.previewImport(csv, mapping: ImportMapping(reportingDateColumn: dateColumn))
        proposals = try model.ledger.proposedPayeeDefaults()
    }

    private func preview() {
        rows = []
        do {
            try refreshPreview()
            message = rows.isEmpty ? "The file contains no transaction rows. Choose an export with a header and transaction rows." : nil
            isError = rows.isEmpty
        } catch {
            message = error.localizedDescription
            isError = true
        }
    }

    private func commit() {
        do {
            let result = try model.ledger.commitImport(csv,
                mapping: ImportMapping(reportingDateColumn: dateColumn),
                uncertain: decisions, acceptedPayees: acceptedPayees)
            acceptedPayees = []
            try model.reload()
            try refreshPreview()
            message = "\(result.importedCount) imported, \(result.skippedCount) skipped"
            isError = false
        } catch {
            message = error.localizedDescription
            isError = true
        }
    }

    private func accept(_ proposal: ProposedPayeeDefault) {
        do {
            try model.ledger.acceptProposedPayeeDefault(for: proposal.payeeID)
            try model.reload()
            try refreshPreview()
            message = "Default accepted for \(proposal.payee)."
            isError = false
        } catch {
            message = error.localizedDescription
            isError = true
        }
    }

    private func stateLabel(_ state: ImportRowState) -> String {
        switch state {
        case .ready: "Ready"
        case .needsCorrection(let reasons): reasons.joined(separator: " ")
        case .definiteRepeat: "Definite repeat — will be skipped"
        case .uncertainMatch: "Possible repeat — choose Keep or Skip"
        }
    }
}

private struct PayeeDefaultChoice: Identifiable, Hashable {
    let payee: String
    let categoryName: String
    var id: String { payee }
}

/// Every payee:category pairing starts selected; the owner deselects the ones
/// they don't want remembered.
private struct PayeeDefaultsSelection: View {
    let choices: [PayeeDefaultChoice]
    @Binding var accepted: Set<String>

    private var allSelected: Bool { choices.allSatisfy { accepted.contains($0.payee) } }

    var body: some View {
        Form {
            Section {
                Button(allSelected ? "Deselect all" : "Select all") {
                    if allSelected {
                        accepted.subtract(choices.map(\.payee))
                    } else {
                        accepted.formUnion(choices.map(\.payee))
                    }
                }
            }
            Section {
                ForEach(choices) { choice in
                    Toggle(isOn: Binding(
                        get: { accepted.contains(choice.payee) },
                        set: { isOn in
                            if isOn { accepted.insert(choice.payee) } else { accepted.remove(choice.payee) }
                        }
                    )) {
                        VStack(alignment: .leading) {
                            Text(choice.payee)
                            Text(choice.categoryName).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: {
                Text("Selected payees get their category filled in automatically next time.")
            }
        }
        .navigationTitle("Payee defaults")
    }
}
