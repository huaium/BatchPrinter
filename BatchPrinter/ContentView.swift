import Foundation
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: MainViewModel
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
        .alert("Error", isPresented: Binding(
            get: { viewModel.lastErrorMessage != nil },
            set: { newValue in if !newValue { viewModel.lastErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.lastErrorMessage = nil }
        } message: {
            Text(viewModel.lastErrorMessage ?? "")
        }
        .confirmationDialog(
            "Preprocess Output Folder",
            isPresented: $showPreprocessOutputChoice,
            titleVisibility: .visible
        ) {
            Button("Use System Temporary Folder") {
                viewModel.preprocessAllToPDF(outputMode: .systemTemporary)
            }
            Button("Choose Output Folder...") {
                viewModel.preprocessAllToPDF(outputMode: .userSelected)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Before preprocessing, choose where generated temporary PDFs should be written.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BatchPrinter")
                .font(.system(size: 36, weight: .bold, design: .rounded))

            Text("Batch-print local Word and PDF files through native macOS printing and Word automation.")
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Folder")
                    .fontWeight(.semibold)
                Text(viewModel.selectedFolderURL?.path ?? "No folder selected")
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
                Button("Choose Folder") { viewModel.chooseFolder() }
                    .disabled(viewModel.isPrinting || viewModel.isPreprocessing)
                Toggle("Scan subfolders", isOn: $viewModel.recursiveScan)
                    .toggleStyle(.checkbox)
                Button("Refresh Files") { viewModel.scanFiles() }
                    .disabled(viewModel.isPrinting || viewModel.isPreprocessing)
                HStack(spacing: 6) {
                    Button(viewModel.isPreprocessing ? "Preprocessing..." : "Preprocess") {
                        showPreprocessOutputChoice = true
                    }
                    .disabled(viewModel.jobs.isEmpty || viewModel.isPrinting || viewModel.isPreprocessing)

                    Button {
                        showPreprocessInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("What happens when preprocessing starts")
                    .popover(isPresented: $showPreprocessInfo, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Preprocess Behavior")
                                .font(.headline)
                            Text("When you click Preprocess, the app asks where preprocessed PDFs should be written:")
                            Text("• Use System Temporary Folder: writes to a macOS temp folder managed by the system.")
                            Text("• Choose Output Folder...: lets you pick a folder and saves preprocessed PDFs there.")
                            Text("This choice is asked each time before preprocessing starts.")
                                .foregroundStyle(.secondary)
                        }
                        .padding(14)
                        .frame(width: 360)
                    }
                }
                Button("Clear") { viewModel.clearJobs() }
                    .disabled(viewModel.jobs.isEmpty || viewModel.isPrinting || viewModel.isPreprocessing)
                Spacer()
                Button("Copy Logs") { viewModel.copyLogsToPasteboard() }
                    .disabled(viewModel.logStore.lines.isEmpty)
                Button("Clear Logs") { viewModel.clearLogs() }
                    .disabled(viewModel.logStore.lines.isEmpty)
            }

            HStack(spacing: 12) {
                Text("Printer")
                    .fontWeight(.semibold)
                Picker("Printer", selection: $viewModel.selectedPrinterName) {
                    if viewModel.availablePrinters.isEmpty {
                        Text("No printer").tag("")
                    } else {
                        ForEach(viewModel.availablePrinters, id: \.self) { printer in
                            Text(printer).tag(printer)
                        }
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 280)

                Button("Refresh Printers") { viewModel.refreshPrinters() }

                Toggle("Show only failures", isOn: $viewModel.showOnlyFailures)
                    .toggleStyle(.checkbox)

                Spacer()
                Text(viewModel.summaryText)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button(viewModel.selectedJobIDs.isEmpty ? "Print All" : "Print Selected") {
                    viewModel.startPrintingSelectedOrAll()
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.jobs.isEmpty || viewModel.isPrinting || viewModel.isPreprocessing)

                Button(viewModel.isCancelling ? "Cancelling..." : "Cancel") {
                    viewModel.cancelPrinting()
                }
                .disabled(!viewModel.isPrinting)

                Spacer()
            }

            HStack(spacing: 6) {
                Text("Page range")
                    .font(.caption)
                    .fontWeight(.semibold)
                Button {
                    showPageRangeInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Page range format help")
                .popover(isPresented: $showPageRangeInfo, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Page Range Format")
                            .font(.headline)
                        Text("Supported formats:")
                        Text("• Single page: 3")
                        Text("• Range: 2-6")
                        Text("• Comma-separated pages: 1,2,5 or 4, 2, 1")
                        Text("Whitespace is ignored. Leave blank for all pages.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .frame(width: 320)
                }
                Spacer()
            }

            HStack {
                Text("Preprocess folder")
                    .font(.caption)
                    .fontWeight(.semibold)
                Text(viewModel.preprocessOutputFolderURL?.path ?? "Not selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
            }
        }
        .padding(14)
        .glassCard(cornerRadius: outerCornerRadius)
    }

    private func tableSection(minHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Print Queue")
                .font(.title3.bold())
                .padding(.horizontal, 2)

            Table(displayedJobs, selection: $viewModel.selectedJobIDs, sortOrder: $tableSortOrder) {
                TableColumn("File", value: \.fileName) { job in
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

                TableColumn("Status") { job in
                    Text(job.status.rawValue)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(statusColor(for: job.status).opacity(0.2), in: Capsule())
                }
                .width(106)

                TableColumn("Pages") { job in
                    TextField("All", text: viewModel.pageRangeBinding(for: job.id))
                        .textFieldStyle(.roundedBorder)
                        .disabled(viewModel.isPrinting)
                }
                .width(120)

                TableColumn("Total") { job in
                    if let totalPages = job.totalPages {
                        Text("\(totalPages)")
                    } else {
                        Text("—")
                            .foregroundStyle(.secondary)
                    }
                }
                .width(60)

                TableColumn("Preprocessed") { job in
                    if let preprocessedPDFURL = job.preprocessedPDFURL,
                       FileManager.default.fileExists(atPath: preprocessedPDFURL.path) {
                        Text("Yes")
                    } else {
                        Text("No")
                            .foregroundStyle(.secondary)
                    }
                }
                .width(100)

                TableColumn("Copies") { job in
                    Stepper(value: viewModel.copiesBinding(for: job.id), in: 1...99) {
                        Text("\(max(1, job.copies))")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .disabled(viewModel.isPrinting)
                }
                .width(90)

                TableColumn("Message") { job in
                    Text(job.message)
                        .lineLimit(2)
                }
                .width(min: 320)

                TableColumn("Printed At") { job in
                    if let printedAt = job.printedAt {
                        Text(printedAt, style: .time)
                    } else {
                        Text("—")
                    }
                }
                .width(100)

                TableColumn("Path") { job in
                    Text(job.fileURL.path)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
                .width(min: 380)
            }
            .contextMenu(forSelectionType: UUID.self) { selection in
                if let id = selection.first,
                   let job = viewModel.jobs.first(where: { $0.id == id }) {
                    Button("Reveal in Finder") {
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
            Text("Logs")
                .font(.title3.bold())
                .padding(.horizontal, 2)

            ScrollView {
                Text(viewModel.logStore.allText.isEmpty ? "No logs yet." : viewModel.logStore.allText)
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
