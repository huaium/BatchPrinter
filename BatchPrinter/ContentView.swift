import Foundation
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: MainViewModel
    @AppStorage(L10n.languagePreferenceKey) private var selectedLanguage = L10n.Language.system
        .rawValue
    @State private var showPreprocessOutputChoice = false
    @State private var showPreprocessInfo = false
    @State private var showPageRangeInfo = false
    @State private var showFileDetails = false
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
        viewModel.isPreprocessing
            ? localized("controls.preprocessing") : localized("controls.preprocess")
    }

    private var printButtonTitle: String {
        viewModel.selectedJobIDs.isEmpty
            ? localized("controls.print_all") : localized("controls.print_selected")
    }

    private var cancelButtonTitle: String {
        viewModel.isCancelling ? localized("controls.cancelling") : localized("common.cancel")
    }

    private var summaryText: String {
        let counts = viewModel.summaryCounts
        if counts.printed == 0 && counts.failed == 0 && counts.skipped == 0 && counts.cancelled == 0
        {
            return localizedFormat("ui.file_count", counts.total)
        }
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
        GeometryReader { geometry in
            VStack(spacing: 12) {
                header
                controls
                tableSection(minHeight: 140)
                    .frame(maxHeight: .infinity)
                printControls
                logSection(minHeight: 90, maxHeight: min(160, geometry.size.height * 0.2))
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .alert(
            "alert.error.title",
            isPresented: Binding(
                get: { viewModel.lastErrorMessage != nil },
                set: { newValue in if !newValue { viewModel.lastErrorMessage = nil } }
            )
        ) {
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
            Button("common.cancel", role: .cancel) {}
        } message: {
            Text("preprocess.output_dialog.message")
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "folder")
                .font(.title)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(
                    viewModel.selectedFolderURL?.lastPathComponent
                        ?? localized("ui.choose_folder_title")
                )
                .font(.title2.weight(.semibold))
                Text(viewModel.selectedFolderURL?.path ?? localized("ui.choose_folder_hint"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(viewModel.selectedFolderURL?.path ?? "")
            }
            Spacer()
            Text("controls.language")
            Picker("controls.language", selection: $selectedLanguage) {
                Text("language.system").tag(L10n.Language.system.rawValue)
                Text("language.english").tag(L10n.Language.english.rawValue)
                Text("language.simplified_chinese").tag(
                    L10n.Language.simplifiedChinese.rawValue)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 150)
            Button("controls.choose_folder") { viewModel.chooseFolder() }
                .disabled(viewModel.isPrinting || viewModel.isPreprocessing)
                .keyboardShortcut("o", modifiers: .command)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("controls.refresh_files") { viewModel.scanFiles() }
                    .disabled(
                        viewModel.selectedFolderURL == nil || viewModel.isPrinting
                            || viewModel.isPreprocessing)
                Toggle("controls.scan_subfolders", isOn: $viewModel.recursiveScan)
                    .toggleStyle(.checkbox)
                    .disabled(viewModel.isPrinting || viewModel.isPreprocessing)
                Spacer()
                Button("controls.clear") { viewModel.clearJobs() }
                    .disabled(
                        viewModel.jobs.isEmpty || viewModel.isPrinting || viewModel.isPreprocessing)
            }
            .padding(14)
            .glassCard(cornerRadius: innerCornerRadius)

            VStack(alignment: .leading, spacing: 8) {
                Text("ui.options")
                    .font(.headline)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        HStack(spacing: 6) {
                            Button {
                                showPreprocessOutputChoice = true
                            } label: {
                                Text(preprocessButtonTitle)
                            }
                            .disabled(
                                viewModel.jobs.isEmpty || viewModel.isPrinting
                                    || viewModel.isPreprocessing)

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
                        Spacer()

                    }
                    HStack {
                        Text("controls.preprocess_folder")
                        Text(
                            viewModel.preprocessOutputFolderURL?.path
                                ?? localized("controls.not_selected")
                        )
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    }
                    .font(.caption)
                    HStack {
                        Button("controls.page_range") { showPageRangeInfo = true }
                            .buttonStyle(.link)
                            .popover(isPresented: $showPageRangeInfo) {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("page_range.info.title").font(.headline)
                                    Text("page_range.info.line1")
                                    Text("page_range.info.line2")
                                    Text("page_range.info.line3")
                                    Text("page_range.info.line4")
                                    Text("page_range.info.line5").foregroundStyle(.secondary)
                                }
                                .padding(14)
                                .frame(width: 320)
                            }
                        Spacer()
                    }
                }
                .padding(.top, 10)
            }
            .padding(14)
            .glassCard(cornerRadius: innerCornerRadius)
        }
    }

    private var printControls: some View {
        HStack(spacing: 12) {
            Text("controls.printer")
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
            .labelsHidden()
            .frame(width: 280)

            Button("controls.refresh_printers") { viewModel.refreshPrinters() }

            Spacer()
            if viewModel.isPrinting || viewModel.isPreprocessing {
                ProgressView().controlSize(.small)
            }
            if viewModel.isPrinting {
                Button(cancelButtonTitle) { viewModel.cancelPrinting() }
                    .disabled(viewModel.isCancelling)
            }
            Button(printButtonTitle) { viewModel.startPrintingSelectedOrAll() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(
                    viewModel.jobs.isEmpty || viewModel.isPrinting || viewModel.isPreprocessing)
        }
    }

    private func tableSection(minHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("table.title").font(.headline)
                if let job = viewModel.jobs.first(where: {
                    viewModel.selectedJobIDs.contains($0.id)
                }) {
                    Button("ui.file_details") { showFileDetails = true }
                        .popover(isPresented: $showFileDetails) {
                            fileDetails(job)
                                .padding(20)
                                .frame(width: 520)
                        }
                }
                Spacer()
                Text(summaryText).font(.caption).foregroundStyle(.secondary)
            }

            if viewModel.jobs.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "doc.on.doc").font(.largeTitle).foregroundStyle(.secondary)
                    Text("ui.empty_title").font(.headline)
                    Text("ui.empty_hint").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: minHeight, maxHeight: .infinity)
            } else {
                Table(
                    displayedJobs, selection: $viewModel.selectedJobIDs, sortOrder: $tableSortOrder
                ) {
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

                    TableColumn("table.copies") { job in
                        Stepper(value: viewModel.copiesBinding(for: job.id), in: 1...99) {
                            Text("\(max(1, job.copies))")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .disabled(viewModel.isPrinting)
                    }
                    .width(90)

                }
                .contextMenu(forSelectionType: UUID.self) { selection in
                    if let id = selection.first,
                        let job = viewModel.jobs.first(where: { $0.id == id })
                    {
                        Button("table.reveal_in_finder") {
                            viewModel.revealInFinder(job: job)
                        }
                    }
                } primaryAction: { selection in
                    if let id = selection.first,
                        let job = viewModel.jobs.first(where: { $0.id == id })
                    {
                        viewModel.revealInFinder(job: job)
                    }
                }
                .frame(minHeight: minHeight, maxHeight: .infinity)
                .padding(8)
                .glassCard(cornerRadius: innerCornerRadius)
            }
        }
        .layoutPriority(1)
    }

    private func fileDetails(_ job: PrintJob) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ui.file_details").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("table.file")
                    Text(job.fileName)
                }
                GridRow {
                    Text("table.total")
                    Text(job.totalPages.map(String.init) ?? "—")
                }
                GridRow {
                    Text("table.preprocessed")
                    Text(
                        job.preprocessedPDFURL.map {
                            FileManager.default.fileExists(atPath: $0.path)
                        } == true
                            ? localized("common.yes") : localized("common.no"))
                }
                GridRow {
                    Text("table.message")
                    Text(job.message.isEmpty ? "—" : job.message)
                }
                GridRow {
                    Text("table.printed_at")
                    if let date = job.printedAt { Text(date, style: .time) } else { Text("—") }
                }
                GridRow {
                    Text("table.path")
                    Text(job.fileURL.path).textSelection(.enabled)
                }
                GridRow {
                    Text("")
                    Button("table.reveal_in_finder") { viewModel.revealInFinder(job: job) }
                }
            }
            .font(.subheadline)
            .padding(.top, 8)
        }
    }

    private func logSection(minHeight: CGFloat, maxHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("logs.title").font(.headline)
                Spacer()
                Toggle("controls.show_only_failures", isOn: $viewModel.showOnlyFailures)
                    .toggleStyle(.checkbox)

                Button("controls.copy_logs") { viewModel.copyLogsToPasteboard() }
                    .disabled(viewModel.logStore.lines.isEmpty)
                Button("controls.clear_logs") { viewModel.clearLogs() }
                    .disabled(viewModel.logStore.lines.isEmpty)
            }

            ScrollView {
                Text(
                    viewModel.logStore.allText.isEmpty
                        ? L10n.tr("logs.empty") : viewModel.logStore.allText
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .font(.system(.caption, design: .monospaced))
                .padding(12)
            }
            .frame(minHeight: minHeight, maxHeight: maxHeight)
            .background(
                .thinMaterial,
                in: RoundedRectangle(cornerRadius: innerCornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: innerCornerRadius, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1)
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

extension View {
    fileprivate func glassCard(cornerRadius: CGFloat) -> some View {
        background(
            .regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.12), lineWidth: 1)
        }
    }
}
