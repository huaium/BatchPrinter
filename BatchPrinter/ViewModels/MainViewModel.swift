import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class MainViewModel: ObservableObject {
    enum PreprocessOutputMode {
        case systemTemporary
        case userSelected
    }

    @Published var selectedFolderURL: URL?
    @Published var recursiveScan = false
    @Published var availablePrinters: [String] = []
    @Published var selectedPrinterName = ""
    @Published var preprocessOutputFolderURL: URL?
    @Published var printPDFOutputFolderURL: URL?
    @Published var jobs: [PrintJob] = []
    @Published var isPreprocessing = false
    @Published var isPrinting = false
    @Published var isCancelling = false
    @Published var selectedJobIDs = Set<UUID>()
    @Published var showOnlyFailures = false
    @Published var lastErrorMessage: String?

    let logStore = LogStore()

    private let scanner = FileScanner()
    private let printer = WordPrinter()
    private var printTask: Task<Void, Never>?
    private var preprocessTask: Task<Void, Never>?
    private var shouldCancel = false
    private var cancellables = Set<AnyCancellable>()

    init() {
        logStore.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        refreshPrinters()
    }

    var filteredJobs: [PrintJob] {
        if showOnlyFailures {
            return jobs.filter { $0.status == .failed || $0.status == .cancelled }
        }
        return jobs
    }

    var summaryText: String {
        let counts = summaryCounts
        return L10n.tr(
            "summary.format",
            counts.total,
            counts.submitted,
            counts.saved,
            counts.failed,
            counts.skipped,
            counts.cancelled
        )
    }

    var summaryCounts: (total: Int, submitted: Int, saved: Int, failed: Int, skipped: Int, cancelled: Int) {
        let total = jobs.count
        let submitted = jobs.filter { $0.status == .submitted }.count
        let saved = jobs.filter { $0.status == .saved }.count
        let failed = jobs.filter { $0.status == .failed }.count
        let skipped = jobs.filter { $0.status == .skipped }.count
        let cancelled = jobs.filter { $0.status == .cancelled }.count
        return (total, submitted, saved, failed, skipped, cancelled)
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = L10n.tr("panel.choose")
        panel.message = L10n.tr("panel.choose_folder.message")

        if panel.runModal() == .OK, let url = panel.url {
            selectedFolderURL = url
            logStore.add(L10n.tr("log.selected_folder", url.path))
            if !isPrinting && !isPreprocessing {
                scanFiles()
            } else {
                logStore.add(L10n.tr("log.folder_updated_refresh_later"))
            }
        }
    }

    func scanFiles() {
        guard !isPrinting && !isPreprocessing else {
            lastErrorMessage = L10n.tr("error.cannot_refresh_while_busy")
            return
        }
        guard let selectedFolderURL else {
            lastErrorMessage = L10n.tr("error.select_folder_first")
            return
        }

        let recursiveState = recursiveScan ? L10n.tr("common.on") : L10n.tr("common.off")
        logStore.add(L10n.tr("log.scanning_files", recursiveState))

        do {
            let urls = try scanner.scan(folderURL: selectedFolderURL, recursive: recursiveScan)
            jobs = urls.map { PrintJob(fileURL: $0) }
            for index in jobs.indices {
                guard jobs[index].isPDFSource else { continue }
                jobs[index].preprocessedPDFURL = jobs[index].fileURL
                if let pageCount = try? printer.pageCountForPDF(at: jobs[index].fileURL) {
                    jobs[index].totalPages = pageCount
                }
            }
            selectedJobIDs.removeAll()
            logStore.add(L10n.tr("log.scanned_printable_docs", urls.count))
            if urls.isEmpty {
                logStore.add(L10n.tr("log.no_matching_files"))
            }
        } catch {
            lastErrorMessage = error.localizedDescription
            logStore.add(L10n.tr("log.scan_failed", error.localizedDescription))
        }
    }

    func clearJobs() {
        guard !isPrinting && !isPreprocessing else {
            lastErrorMessage = L10n.tr("error.cannot_clear_while_busy")
            return
        }
        jobs.removeAll()
        selectedJobIDs.removeAll()
        logStore.add(L10n.tr("log.cleared_job_list"))
    }

    func choosePreprocessOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = L10n.tr("panel.choose")
        panel.message = L10n.tr("panel.preprocess_output.message")

        if panel.runModal() == .OK, let url = panel.url {
            preprocessOutputFolderURL = url
            logStore.add(L10n.tr("log.preprocess_output_folder", url.path))
        }
    }

    func choosePrintPDFOutputFolder() {
        // Force explicit confirmation for each Print-to-PDF run.
        printPDFOutputFolderURL = nil

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = L10n.tr("panel.choose")
        panel.message = L10n.tr("panel.print_pdf_output.message")

        if panel.runModal() == .OK, let url = panel.url {
            printPDFOutputFolderURL = url
            logStore.add(L10n.tr("log.print_pdf_output_folder", url.path))
        }
    }

    func preprocessAllToPDF(outputMode: PreprocessOutputMode) {
        guard !isPrinting else { return }
        guard !isPreprocessing else { return }
        guard !jobs.isEmpty else {
            lastErrorMessage = L10n.tr("error.no_jobs_to_preprocess")
            return
        }
        let hasWordInputs = jobs.contains { !$0.isPDFSource }
        guard !hasWordInputs || printer.isWordInstalled() else {
            lastErrorMessage = L10n.tr("error.word_not_found_install_first")
            return
        }
        let outputFolder: URL?
        if hasWordInputs {
            switch outputMode {
            case .systemTemporary:
                let tempFolder = FileManager.default.temporaryDirectory
                    .appendingPathComponent("BatchPrinter-PreprocessedPDFs", isDirectory: true)
                do {
                    try FileManager.default.createDirectory(
                        at: tempFolder,
                        withIntermediateDirectories: true,
                        attributes: nil
                    )
                } catch {
                    lastErrorMessage = L10n.tr("error.unable_prepare_temp_folder", error.localizedDescription)
                    logStore.add(L10n.tr("log.preprocess_prepare_temp_failed", error.localizedDescription))
                    return
                }
                outputFolder = tempFolder
                logStore.add(L10n.tr("log.using_temp_preprocess_folder", tempFolder.path))

            case .userSelected:
                if preprocessOutputFolderURL == nil {
                    choosePreprocessOutputFolder()
                }
                guard let selectedFolder = preprocessOutputFolderURL else {
                    lastErrorMessage = L10n.tr("error.select_preprocess_output_first")
                    return
                }
                outputFolder = selectedFolder
            }
        } else {
            outputFolder = nil
        }

        if hasWordInputs {
            do {
                try printer.requestAutomationAuthorization()
            } catch {
                lastErrorMessage = error.localizedDescription
                logStore.add(L10n.tr("log.preprocess_start_failed", error.localizedDescription))
                return
            }
        }

        isPreprocessing = true
        isCancelling = false
        for index in jobs.indices {
            jobs[index].status = .pending
            jobs[index].message = ""
            jobs[index].completedAt = nil
            jobs[index].printJobID = nil
        }
        logStore.add(L10n.tr("log.preprocessing_files", jobs.count))

        preprocessTask = Task { [weak self] in
            guard let self else { return }
            defer {
                isPreprocessing = false
                isCancelling = false
                preprocessTask = nil
                logStore.add(L10n.tr("log.preprocess_finished"))
            }
            for index in jobs.indices {
                await Task.yield()
                if Task.isCancelled {
                    jobs[index].status = .cancelled
                    jobs[index].message = L10n.tr("message.cancelled_before_preparing")
                    continue
                }
                jobs[index].status = .preparing
                jobs[index].message = L10n.tr("message.preparing_pdf")
                let sourceURL = jobs[index].fileURL
                if jobs[index].isPDFSource {
                    do {
                        let totalPages = try printer.pageCountForPDF(at: sourceURL)
                        jobs[index].preprocessedPDFURL = sourceURL
                        jobs[index].totalPages = totalPages
                        jobs[index].status = .ready
                        jobs[index].message = L10n.tr("message.pdf_ready")
                        logStore.add(L10n.tr("log.preprocess_skipped_pdf_source", sourceURL.lastPathComponent, totalPages))
                    } catch {
                        jobs[index].preprocessedPDFURL = nil
                        jobs[index].totalPages = nil
                        jobs[index].status = .failed
                        jobs[index].message = error.localizedDescription
                        logStore.add(L10n.tr("log.page_count_unavailable_source_pdf", sourceURL.lastPathComponent))
                    }
                    continue
                }

                guard let outputFolder else {
                    jobs[index].preprocessedPDFURL = nil
                    jobs[index].totalPages = nil
                    jobs[index].status = .failed
                    jobs[index].message = L10n.tr("error.select_preprocess_output_first")
                    logStore.add(L10n.tr("log.preprocess_missing_output_folder", sourceURL.lastPathComponent))
                    continue
                }

                let outputURL = Self.nextPreprocessedPDFURL(for: sourceURL, in: outputFolder)
                do {
                    _ = try await Task.detached(priority: .userInitiated) { [printer] in
                        try printer.exportDocumentAsPDF(
                            at: sourceURL,
                            outputURL: outputURL,
                            pageRange: nil,
                            copies: 1
                        )
                    }.value
                    let totalPages = try printer.pageCountForPDF(at: outputURL)
                    jobs[index].preprocessedPDFURL = outputURL
                    jobs[index].totalPages = totalPages
                    jobs[index].status = .ready
                    jobs[index].message = L10n.tr("message.pdf_ready")
                    logStore.add(
                        L10n.tr(
                            "log.preprocessed_success",
                            sourceURL.lastPathComponent,
                            outputURL.lastPathComponent,
                            totalPages
                        )
                    )
                } catch {
                    jobs[index].preprocessedPDFURL = nil
                    jobs[index].totalPages = nil
                    jobs[index].status = .failed
                    jobs[index].message = error.localizedDescription
                    logStore.add(L10n.tr("log.preprocess_failed", sourceURL.lastPathComponent, error.localizedDescription))
                }
            }
        }
    }

    func refreshPrinters() {
        let names = printer.availablePrinterNames()
        availablePrinters = names

        if names.isEmpty {
            selectedPrinterName = ""
            logStore.add(L10n.tr("log.no_printer_found"))
            return
        }

        if names.contains(selectedPrinterName) {
            return
        }

        if let defaultPrinter = printer.defaultPrinterName(), names.contains(defaultPrinter) {
            selectedPrinterName = defaultPrinter
        } else if let first = names.first {
            selectedPrinterName = first
        }
    }

    func pageRangeBinding(for jobID: UUID) -> Binding<String> {
        Binding(
            get: { [weak self] in
                self?.jobs.first(where: { $0.id == jobID })?.pageRange ?? ""
            },
            set: { [weak self] newValue in
                guard let self, let index = self.jobs.firstIndex(where: { $0.id == jobID }) else { return }
                self.jobs[index].pageRange = newValue
            }
        )
    }

    func copiesBinding(for jobID: UUID) -> Binding<Int> {
        Binding(
            get: { [weak self] in
                self?.jobs.first(where: { $0.id == jobID })?.copies ?? 1
            },
            set: { [weak self] newValue in
                guard let self, let index = self.jobs.firstIndex(where: { $0.id == jobID }) else { return }
                self.jobs[index].copies = max(1, newValue)
            }
        )
    }

    func startPrintingSelectedOrAll() {
        guard !isPrinting else { return }
        guard !isPreprocessing else {
            lastErrorMessage = L10n.tr("error.preprocess_still_running")
            return
        }
        if availablePrinters.isEmpty {
            refreshPrinters()
        }
        guard !selectedPrinterName.isEmpty else {
            lastErrorMessage = L10n.tr("error.no_printer_selected")
            return
        }
        let selectedPrinter = selectedPrinterName
        let exportAsPDF = selectedPrinter == WordPrinter.virtualPDFPrinterName

        let targetIDs = selectedJobIDs.isEmpty ? Set(jobs.map(\.id)) : selectedJobIDs
        guard !targetIDs.isEmpty else {
            lastErrorMessage = L10n.tr("error.no_jobs_selected")
            return
        }

        if !exportAsPDF {
            let missing = jobs
                .filter { targetIDs.contains($0.id) }
                .filter { job in
                    guard let pdfURL = job.preprocessedPDFURL else { return true }
                    return !FileManager.default.fileExists(atPath: pdfURL.path)
                }
                .map(\.fileName)

            if !missing.isEmpty {
                lastErrorMessage = L10n.tr("error.preprocess_required_physical_printer")
                logStore.add(L10n.tr("log.cannot_print_preprocess_missing_count", missing.count))
                for fileName in missing {
                    logStore.add(L10n.tr("log.preprocess_required_file", fileName))
                }
                return
            }
        }

        if exportAsPDF {
            let needsWordFallback = jobs
                .filter { targetIDs.contains($0.id) }
                .contains { job in
                    guard let pdfURL = job.preprocessedPDFURL else { return true }
                    return !FileManager.default.fileExists(atPath: pdfURL.path)
                }

            choosePrintPDFOutputFolder()
            guard let printPDFOutputFolderURL else {
                lastErrorMessage = L10n.tr("error.select_print_pdf_output_folder")
                return
            }
            logStore.add(L10n.tr("log.using_print_pdf_output_folder", printPDFOutputFolderURL.path))
            if needsWordFallback {
                guard printer.isWordInstalled() else {
                    lastErrorMessage = L10n.tr("error.word_not_found_or_preprocess_first")
                    return
                }
                do {
                    try printer.requestAutomationAuthorization()
                } catch {
                    lastErrorMessage = error.localizedDescription
                    logStore.add(L10n.tr("log.printer_setup_failed", error.localizedDescription))
                    return
                }
            }
        }

        shouldCancel = false
        isCancelling = false
        isPrinting = true
        let selectedPrinterLabel = exportAsPDF
            ? L10n.tr("printer.virtual_pdf")
            : selectedPrinter
        logStore.add(L10n.tr("log.using_printer", selectedPrinterLabel))
        logStore.add(L10n.tr("log.starting_print_run", targetIDs.count))

        printTask = Task { [weak self] in
            guard let self else { return }
            defer {
                isPrinting = false
                isCancelling = false
                printTask = nil
                logStore.add(L10n.tr("log.print_run_finished"))
            }

            for index in jobs.indices {
                guard targetIDs.contains(jobs[index].id) else {
                    continue
                }

                if Task.isCancelled || shouldCancel {
                    if jobs[index].status == .pending || jobs[index].status == .ready || jobs[index].status == .printing {
                        jobs[index].status = .cancelled
                        jobs[index].message = L10n.tr("message.cancelled_before_printing")
                    }
                    continue
                }

                jobs[index].status = .printing
                jobs[index].completedAt = nil
                jobs[index].printJobID = nil
                let preprocessedPDFURL = jobs[index].preprocessedPDFURL
                let hasPreprocessedPDF = preprocessedPDFURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
                jobs[index].message = hasPreprocessedPDF
                    ? (exportAsPDF ? L10n.tr("message.generating_from_preprocessed_pdf") : L10n.tr("message.printing_preprocessed_pdf"))
                    : (exportAsPDF ? L10n.tr("message.exporting_to_pdf_in_word") : L10n.tr("message.sending_to_word"))
                logStore.add(L10n.tr("log.printing_file", jobs[index].fileURL.lastPathComponent))

                do {
                    let fileURL = jobs[index].fileURL
                    let pageRange = try printer.parsePageRange(from: jobs[index].pageRange)
                    let copies = max(1, jobs[index].copies)
                    let pdfOutputFolder = printPDFOutputFolderURL
                    let result = try await Task.detached(priority: .userInitiated) { [printer] in
                        if hasPreprocessedPDF, let preprocessedPDFURL {
                            if exportAsPDF {
                                let outputURL = Self.nextPDFOutputURL(for: fileURL, in: pdfOutputFolder)
                                return try printer.generatePDFOutputs(
                                    from: preprocessedPDFURL,
                                    outputURL: outputURL,
                                    pageRange: pageRange,
                                    copies: copies
                                )
                            }
                            return try printer.printPDF(
                                at: preprocessedPDFURL,
                                printerName: selectedPrinter,
                                pageRange: pageRange,
                                copies: copies
                            )
                        }

                        if exportAsPDF {
                            let outputURL = Self.nextPDFOutputURL(for: fileURL, in: pdfOutputFolder)
                            return try printer.exportDocumentAsPDF(
                                at: fileURL,
                                outputURL: outputURL,
                                pageRange: pageRange,
                                copies: copies
                            )
                        }
                        return try printer.printDocument(at: fileURL, pageRange: pageRange, copies: copies)
                    }.value
                    jobs[index].status = exportAsPDF ? .saved : .submitted
                    jobs[index].message = result.message
                    jobs[index].completedAt = Date()
                    jobs[index].printJobID = result.printJobID
                    logStore.add(L10n.tr(exportAsPDF ? "log.pdf_saved" : "log.print_submitted", jobs[index].fileURL.lastPathComponent))
                } catch {
                    jobs[index].status = .failed
                    jobs[index].message = error.localizedDescription
                    logStore.add(L10n.tr("log.print_failed", jobs[index].fileURL.lastPathComponent, error.localizedDescription))

                    if case WordPrinterError.notAuthorizedToControlWord = error {
                        shouldCancel = true
                        isCancelling = true
                        logStore.add(L10n.tr("log.stopping_run_word_permission"))
                    }
                }
            }
        }
    }

    func cancelPrinting() {
        guard isPrinting else { return }
        shouldCancel = true
        isCancelling = true
        printTask?.cancel()
        logStore.add(L10n.tr("log.cancellation_requested"))
    }

    func cancelPreprocessing() {
        guard isPreprocessing, !isCancelling else { return }
        isCancelling = true
        preprocessTask?.cancel()
        logStore.add(L10n.tr("log.preprocess_cancellation_requested"))
    }

    func copyLogsToPasteboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(logStore.allText, forType: .string)
        logStore.add(L10n.tr("log.copied_logs"))
    }

    func clearLogs() {
        logStore.clear()
    }

    func revealInFinder(job: PrintJob) {
        NSWorkspace.shared.activateFileViewerSelecting([job.fileURL])
    }

    nonisolated private static func nextPDFOutputURL(for sourceURL: URL, in outputFolder: URL?) -> URL {
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let directory = outputFolder ?? sourceURL.deletingLastPathComponent()
        let initialURL = directory.appendingPathComponent(baseName).appendingPathExtension("pdf")

        if !FileManager.default.fileExists(atPath: initialURL.path) {
            return initialURL
        }

        var index = 1
        while true {
            let candidate = directory
                .appendingPathComponent("\(baseName) (\(index))")
                .appendingPathExtension("pdf")
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }

    nonisolated private static func nextPreprocessedPDFURL(for sourceURL: URL, in outputFolder: URL) -> URL {
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let initialURL = outputFolder.appendingPathComponent(baseName).appendingPathExtension("pdf")

        if !FileManager.default.fileExists(atPath: initialURL.path) {
            return initialURL
        }

        var index = 1
        while true {
            let candidate = outputFolder
                .appendingPathComponent("\(baseName) (\(index))")
                .appendingPathExtension("pdf")
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }
}
