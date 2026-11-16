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

    var body: some View {
        Form {
            Section {
                Button("Choose CSV file", systemImage: "doc") { isChoosingFile = true }
                if let filename { Text(filename).foregroundStyle(.secondary) }
                if let message { Text(message).foregroundStyle(isError ? AnyShapeStyle(.ayuError) : AnyShapeStyle(.secondary)) }
            }
            .ayuRows()
            if filename != nil && !rows.isEmpty {
                Section {
                    LabeledContent("Transactions to import", value: String(readyCount + keptUncertainCount))
                    Button("Import transactions", systemImage: "square.and.arrow.down", action: commit)
                        .disabled(unresolvedMatches || !hasRowsToImport)
                } footer: {
                    if unresolvedMatches {
                        Text("Choose Keep or Skip for each possible duplicate below before importing.")
                    } else {
                        Text("Payees remember their category automatically for future entries.")
                    }
                }
                .ayuRows()
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
                    .ayuRows()
                }
                if !definiteRepeatRows.isEmpty {
                    Section {
                        DisclosureGroup("\(definiteRepeatRows.count) already imported — will be skipped") {
                            ForEach(definiteRepeatRows) { rowSummary($0) }
                        }
                    }
                    .ayuRows()
                }
                if !correctionRows.isEmpty {
                    Section {
                        DisclosureGroup("\(correctionRows.count) can't be imported") {
                            ForEach(correctionRows) { row in
                                VStack(alignment: .leading, spacing: 4) {
                                    rowSummary(row)
                                    Text(stateLabel(row.state)).font(.footnote).foregroundStyle(.ayuError)
                                }
                            }
                        }
                    }
                    .ayuRows()
                }
                Section {
                    TextField("Reporting date column", text: $dateColumn)
                        .onSubmit { preview() }
                    Button("Update preview", systemImage: "arrow.clockwise", action: preview)
                } header: {
                    Text("Options")
                }
                .ayuRows()
            }
        }
        .ayuGroupedBackground()
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
                uncertain: decisions)
            try model.reload()
            try refreshPreview()
            message = "\(result.importedCount) imported, \(result.skippedCount) skipped"
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
