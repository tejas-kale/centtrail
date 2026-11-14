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

    var body: some View {
        Form {
            Section {
                Button("Choose CSV file", systemImage: "doc") { isChoosingFile = true }
                if let filename { Text(filename).foregroundStyle(.secondary) }
                if let message { Text(message).foregroundStyle(isError ? .red : .secondary) }
            }
            if filename != nil {
                Section("Preview") {
                    LabeledContent("Ready", value: String(rows.filter { $0.state == .ready }.count))
                    LabeledContent("Needs a fix", value: String(rows.filter { if case .needsCorrection = $0.state { true } else { false } }.count))
                    LabeledContent("Definite repeats", value: String(rows.filter { $0.state == .definiteRepeat }.count))
                    LabeledContent("Uncertain matches", value: String(rows.filter { $0.state == .uncertainMatch }.count))
                    TextField("Reporting date column", text: $dateColumn)
                        .onSubmit { preview() }
                    Button("Update preview", action: preview)
                }
                if rows.contains(where: { $0.proposedDefaultCategoryName != nil }) {
                    Section("Proposed payee defaults") {
                        ForEach(rows.filter { $0.proposedDefaultCategoryName != nil }) { row in
                            if let payee = row.payee, let category = row.proposedDefaultCategoryName {
                                Toggle("\(payee): \(category)", isOn: defaultBinding(for: payee))
                            }
                        }
                    }
                }
                Section("Rows") {
                    ForEach(rows) { row in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(row.payee ?? "Unknown payee") · \(row.amountText ?? "Unknown amount")")
                            Text("\(row.categoryName ?? "") · \(row.reportingDate ?? "Unknown date")")
                                .font(.footnote).foregroundStyle(.secondary)
                            Text(stateLabel(row.state)).font(.footnote).foregroundStyle(.secondary)
                            if row.state == .uncertainMatch {
                                Picker("Decision", selection: Binding(
                                    get: { decisions[row.index] },
                                    set: { decisions[row.index] = $0 }
                                )) {
                                    Text("Choose").tag(Optional<UncertainDecision>.none)
                                    Text("Keep").tag(Optional(UncertainDecision.keep))
                                    Text("Skip").tag(Optional(UncertainDecision.skip))
                                }
                            }
                        }
                    }
                }
                Section {
                    if unresolvedMatches { Text("Choose Keep or Skip for each uncertain match before importing.").font(.footnote) }
                    Button("Import transactions", action: commit)
                        .disabled(unresolvedMatches || !hasRowsToImport)
                }
            }
            if !proposals.isEmpty {
                Section("Unaccepted payee defaults") {
                    ForEach(proposals) { proposal in
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
            acceptedPayees = []
            decisions = [:]
            preview()
        } catch {
            message = "The CSV file could not be opened. Choose a readable UTF-8 CSV file. \(error.localizedDescription)"
            isError = true
        }
    }

    private func defaultBinding(for payee: String) -> Binding<Bool> {
        Binding(get: { acceptedPayees.contains(payee) }, set: { accepted in
            if accepted { acceptedPayees.insert(payee) } else { acceptedPayees.remove(payee) }
        })
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
            try model.reloadFromOutside()
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
            try model.reloadFromOutside()
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
