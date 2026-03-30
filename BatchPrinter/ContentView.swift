import Foundation
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: MainViewModel
    @AppStorage(L10n.languagePreferenceKey) private var selectedLanguage = L10n.Language.system.rawValue
    @State private var showPreprocessOutputChoice = false
    @State private var showPreprocessInfo = false
    @State private var showPageRangeInfo = false
    @State private var tableSortOrder: [KeyPathComparator<PrintJob>] = [
        KeyPathComparator(\.fileName, order: .forward)
    ]

    private let outerCornerRadius: CGFloat = 22
    private let innerCornerRadius: CGFloat = 16

    private var displayedJobs: [PrintJob] {
        viewModel.filteredJobs.sorted(using: tableSortOrder)
    }

    private func localized(_ key: String) -> String {
        L10n.tr(key, languageRawValue: selectedLanguage)
    }

    private func localizedFormat(_ key: String, _ args: CVarArg...) -> String {
        String(
            format: localized(key),
            locale: L10n.locale(for: selectedLanguage),
            arguments: args
        )
    }

    private var preprocessButtonTitle: String {
        viewModel.isPreprocessing ? localized("controls.preprocessing") : localized("controls.preprocess")
    }

    private var printButtonTitle: String {
        viewModel.selectedJobIDs.isEmpty ? localized("controls.print_all") : localized("controls.print_selected")
    }

    private var cancelButtonTitle: String {
        viewModel.isCancelling ? localized("controls.cancelling") : localized("common.cancel")
    }

    private var summaryText: String {
        let counts = viewModel.summaryCounts
        return localizedFormat(
            "summary.format",
            counts.total,
            counts.printed,
            counts.failed,
            counts.skipped,
            counts.cancelled
        )
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .controlBackgroundColor).opacity(0.9),
                    Color(nsColor: .underPageBackgroundColor)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {
                header
                controls
                tableSection(minHeight: 240)
                logSection(minHeight: 140, maxHeight: 220)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, 22)
            .padding(.vertical, 24)
        }
        .alert("alert.error.title", isPresented: Binding(
            get: { viewModel.lastErrorMessage != nil },
            set: { newValue in if !newValue { viewModel.lastErrorMessage = nil } }
        )) {
            Button("common.ok", role: .cancel) { viewModel.lastErrorMessage = nil }
        } message: {
            Text(viewModel.lastErrorMessage ?? "")
        }
        .confirmationDialog(
            "preprocess.output_dialog.title",
            isPresented: $showPreprocessOutputChoice,
            titleVisibility: .visible
        ) {
            Button("preprocess.output_dialog.use_system_temp") {
                viewModel.preprocessAllToPDF(outputMode: .systemTemporary)
            }
            Button("preprocess.output_dialog.choose_folder") {
                viewModel.preprocessAllToPDF(outputMode: .userSelected)
            }
            Button("common.cancel", role: .cancel) { }
        } message: {
            Text("preprocess.output_dialog.message")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("app.title")
                .font(.system(size: 36, weight: .bold, design: .rounded))

            Text("app.subtitle")
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("header.folder")
                    .fontWeight(.semibold)
                Text(viewModel.selectedFolderURL?.path ?? localized("header.no_folder_selected"))
                    .lineLimit(2)
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassCard(cornerRadius: outerCornerRadius)
    }

    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button("controls.choose_folder") { viewModel.chooseFolder() }
                    .disabled(viewModel.isPrinting || viewModel.isPreprocessing)
                Toggle("controls.scan_subfolders", isOn: $viewModel.recursiveScan)
                    .toggleStyle(.checkbox)
                Button("controls.refresh_files") { viewModel.scanFiles() }
                    .disabled(viewModel.isPrinting || viewModel.isPreprocessing)
                HStack(spacing: 6) {
                    Button {
                        showPreprocessOutputChoice = true
                    }
                    label: {
                        Text(preprocessButtonTitle)
                    }
                    .disabled(viewModel.jobs.isEmpty || viewModel.isPrinting || viewModel.isPreprocessing)

                    Button {
                        showPreprocessInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("controls.preprocess.help")
                    .popover(isPresented: $showPreprocessInfo, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("preprocess.info.title")
                                .font(.headline)
                            Text("preprocess.info.line1")
                            Text("preprocess.info.line2")
                            Text("preprocess.info.line3")
                            Text("preprocess.info.line4")
                                .foregroundStyle(.secondary)
                        }
                        .padding(14)
                        .frame(width: 360)
                    }
                }
                Button("controls.clear") { viewModel.clearJobs() }
                    .disabled(viewModel.jobs.isEmpty || viewModel.isPrinting || viewModel.isPreprocessing)
                Spacer()
                Button("controls.copy_logs") { viewModel.copyLogsToPasteboard() }
                    .disabled(viewModel.logStore.lines.isEmpty)
                Button("controls.clear_logs") { viewModel.clearLogs() }
                    .disabled(viewModel.logStore.lines.isEmpty)
            }

            HStack(spacing: 12) {
                Text("controls.printer")
                    .fontWeight(.semibold)
                Picker("controls.printer", selection: $viewModel.selectedPrinterName) {
                    if viewModel.availablePrinters.isEmpty {
                        Text("controls.no_printer").tag("")
                    } else {
                        ForEach(viewModel.availablePrinters, id: \.self) { printer in
                            if printer == WordPrinter.virtualPDFPrinterName {
                                Text(localized("printer.virtual_pdf")).tag(printer)
                            } else {
                                Text(printer).tag(printer)
                            }
                        }
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 280)

                Button("controls.refresh_printers") { viewModel.refreshPrinters() }

                Toggle("controls.show_only_failures", isOn: $viewModel.showOnlyFailures)
                    .toggleStyle(.checkbox)

                Text("controls.language")
                    .fontWeight(.semibold)
                Picker("controls.language", selection: $selectedLanguage) {
                    Text("language.system").tag(L10n.Language.system.rawValue)
                    Text("language.english").tag(L10n.Language.english.rawValue)
                    Text("language.simplified_chinese").tag(L10n.Language.simplifiedChinese.rawValue)
                }
                .pickerStyle(.menu)
                .frame(width: 150)

                Spacer()
                Text(summaryText)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button {
                    viewModel.startPrintingSelectedOrAll()
                }
                label: {
                    Text(printButtonTitle)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.jobs.isEmpty || viewModel.isPrinting || viewModel.isPreprocessing)

                Button {
                    viewModel.cancelPrinting()
                }
                label: {
                    Text(cancelButtonTitle)
                }
                .disabled(!viewModel.isPrinting)

                Spacer()
            }

            HStack(spacing: 6) {
                Text("controls.page_range")
                    .font(.caption)
                    .fontWeight(.semibold)
                Button {
                    showPageRangeInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("controls.page_range.help")
                .popover(isPresented: $showPageRangeInfo, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("page_range.info.title")
                            .font(.headline)
                        Text("page_range.info.line1")
                        Text("page_range.info.line2")
                        Text("page_range.info.line3")
                        Text("page_range.info.line4")
                        Text("page_range.info.line5")
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .frame(width: 320)
                }
                Spacer()
            }

            HStack {
                Text("controls.preprocess_folder")
                    .font(.caption)
                    .fontWeight(.semibold)
                Text(viewModel.preprocessOutputFolderURL?.path ?? localized("controls.not_selected"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
            }
        }
        .padding(14)
        .glassCard(cornerRadius: outerCornerRadius)
        .id(selectedLanguage)
    }

    private func tableSection(minHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("table.title")
                .font(.title3.bold())
                .padding(.horizontal, 2)

            Table(displayedJobs, selection: $viewModel.selectedJobIDs, sortOrder: $tableSortOrder) {
                TableColumn("table.file", value: \.fileName) { job in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(job.fileName)
                            .lineLimit(1)
                        Text(job.directoryName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .width(min: 280)

                TableColumn("table.status") { job in
                    Text(job.status.localizedLabel)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(statusColor(for: job.status).opacity(0.2), in: Capsule())
                }
                .width(106)

                TableColumn("table.pages") { job in
                    TextField("table.all_pages", text: viewModel.pageRangeBinding(for: job.id))
                        .textFieldStyle(.roundedBorder)
                        .disabled(viewModel.isPrinting)
                }
                .width(120)

                TableColumn("table.total") { job in
                    if let totalPages = job.totalPages {
                        Text("\(totalPages)")
                    } else {
                        Text("—")
                            .foregroundStyle(.secondary)
                    }
                }
                .width(60)

                TableColumn("table.preprocessed") { job in
                    if let preprocessedPDFURL = job.preprocessedPDFURL,
                       FileManager.default.fileExists(atPath: preprocessedPDFURL.path) {
                        Text("common.yes")
                    } else {
                        Text("common.no")
                            .foregroundStyle(.secondary)
                    }
                }
                .width(100)

                TableColumn("table.copies") { job in
                    Stepper(value: viewModel.copiesBinding(for: job.id), in: 1...99) {
                        Text("\(max(1, job.copies))")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .disabled(viewModel.isPrinting)
                }
                .width(90)

                TableColumn("table.message") { job in
                    Text(job.message)
                        .lineLimit(2)
                }
                .width(min: 320)

                TableColumn("table.printed_at") { job in
                    if let printedAt = job.printedAt {
                        Text(printedAt, style: .time)
                    } else {
                        Text("—")
                    }
                }
                .width(100)

                TableColumn("table.path") { job in
                    Text(job.fileURL.path)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
                .width(min: 380)
            }
            .contextMenu(forSelectionType: UUID.self) { selection in
                if let id = selection.first,
                   let job = viewModel.jobs.first(where: { $0.id == id }) {
                    Button("table.reveal_in_finder") {
                        viewModel.revealInFinder(job: job)
                    }
                }
            } primaryAction: { selection in
                if let id = selection.first,
                   let job = viewModel.jobs.first(where: { $0.id == id }) {
                    viewModel.revealInFinder(job: job)
                }
            }
            .frame(minHeight: minHeight, maxHeight: .infinity)
            .padding(8)
            .glassCard(cornerRadius: innerCornerRadius)
        }
        .layoutPriority(1)
    }

    private func logSection(minHeight: CGFloat, maxHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("logs.title")
                .font(.title3.bold())
                .padding(.horizontal, 2)

            ScrollView {
                Text(viewModel.logStore.allText.isEmpty ? L10n.tr("logs.empty") : viewModel.logStore.allText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .font(.system(.caption, design: .monospaced))
                    .padding(12)
            }
            .frame(minHeight: minHeight, maxHeight: maxHeight)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: innerCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: innerCornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            }
        }
        .padding(14)
        .glassCard(cornerRadius: outerCornerRadius)
    }

    private func statusColor(for status: PrintJobStatus) -> Color {
        switch status {
        case .pending:
            return .gray
        case .printing:
            return .blue
        case .success:
            return .green
        case .failed:
            return .red
        case .skipped:
            return .orange
        case .cancelled:
            return .brown
        }
    }
}

private extension View {
    func glassCard(cornerRadius: CGFloat) -> some View {
        background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.08), radius: 18, x: 0, y: 8)
    }
}
