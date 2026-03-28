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
        let total = jobs.count
        let printed = jobs.filter { $0.status == .success }.count
        let failed = jobs.filter { $0.status == .failed }.count
        let skipped = jobs.filter { $0.status == .skipped }.count
        let cancelled = jobs.filter { $0.status == .cancelled }.count
        return "Total: \(total)  Printed: \(printed)  Failed: \(failed)  Skipped: \(skipped)  Cancelled: \(cancelled)"
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Select a folder that contains Word or PDF files."

        if panel.runModal() == .OK, let url = panel.url {
            selectedFolderURL = url
            logStore.add("Selected folder: \(url.path)")
            if !isPrinting && !isPreprocessing {
                scanFiles()
            } else {
                logStore.add("Folder updated. Refresh files after current task finishes.")
            }
        }
    }

    func scanFiles() {
        guard !isPrinting && !isPreprocessing else {
            lastErrorMessage = "Cannot refresh files while printing or preprocessing is running."
            return
        }
        guard let selectedFolderURL else {
            lastErrorMessage = "Select a folder first."
            return
        }

        logStore.add("Scanning files (scan subfolders: \(recursiveScan ? "On" : "Off")).")

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
            logStore.add("Scanned \(urls.count) printable document(s) (.doc/.docx/.pdf).")
            if urls.isEmpty {
                logStore.add("No matching files were found. Hidden files and Word lock files (~$...) are skipped.")
            }
        } catch {
            lastErrorMessage = error.localizedDescription
            logStore.add("Scan failed: \(error.localizedDescription)")
        }
    }

    func clearJobs() {
        guard !isPrinting && !isPreprocessing else {
            lastErrorMessage = "Cannot clear while printing or preprocessing is running."
            return
        }
        jobs.removeAll()
        selectedJobIDs.removeAll()
        logStore.add("Cleared job list.")
    }

    func choosePreprocessOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Select output folder for preprocessed PDF files."

        if panel.runModal() == .OK, let url = panel.url {
            preprocessOutputFolderURL = url
            logStore.add("Preprocess output folder: \(url.path)")
        }
    }

    func choosePrintPDFOutputFolder() {
        // Force explicit confirmation for each Print-to-PDF run.
        printPDFOutputFolderURL = nil

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Select output folder for Print to PDF files."

        if panel.runModal() == .OK, let url = panel.url {
            printPDFOutputFolderURL = url
            logStore.add("Print-to-PDF output folder: \(url.path)")
        }
    }

    func preprocessAllToPDF(outputMode: PreprocessOutputMode) {
        guard !isPrinting else { return }
        guard !isPreprocessing else { return }
        guard !jobs.isEmpty else {
            lastErrorMessage = "No jobs to preprocess."
            return
        }
        let hasWordInputs = jobs.contains { !$0.isPDFSource }
        guard !hasWordInputs || printer.isWordInstalled() else {
            lastErrorMessage = "Microsoft Word was not found. Install Word first."
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
                    lastErrorMessage = "Unable to prepare temporary folder: \(error.localizedDescription)"
                    logStore.add("Preprocess failed to prepare temporary folder: \(error.localizedDescription)")
                    return
                }
                outputFolder = tempFolder
                logStore.add("Using temporary preprocess folder: \(tempFolder.path)")

            case .userSelected:
                if preprocessOutputFolderURL == nil {
                    choosePreprocessOutputFolder()
                }
                guard let selectedFolder = preprocessOutputFolderURL else {
                    lastErrorMessage = "Select a preprocess output folder first."
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
                logStore.add("Preprocess failed to start: \(error.localizedDescription)")
                return
            }
        }

        isPreprocessing = true
        logStore.add("Preprocessing \(jobs.count) file(s) to PDF...")

        Task { [weak self] in
            guard let self else { return }
            for index in jobs.indices {
                if Task.isCancelled { break }
                let sourceURL = jobs[index].fileURL
                if jobs[index].isPDFSource {
                    do {
                        let totalPages = try printer.pageCountForPDF(at: sourceURL)
                        jobs[index].preprocessedPDFURL = sourceURL
                        jobs[index].totalPages = totalPages
                        logStore.add("Preprocess skipped (PDF source): \(sourceURL.lastPathComponent) (\(totalPages) pages)")
                    } catch {
                        jobs[index].preprocessedPDFURL = sourceURL
                        jobs[index].totalPages = nil
                        logStore.add("Page count unavailable for source PDF: \(sourceURL.lastPathComponent)")
                    }
                    continue
                }

                guard let outputFolder else {
                    jobs[index].preprocessedPDFURL = nil
                    jobs[index].totalPages = nil
                    logStore.add("Preprocess failed: missing output folder for \(sourceURL.lastPathComponent)")
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
                    logStore.add("Preprocessed: \(sourceURL.lastPathComponent) -> \(outputURL.lastPathComponent) (\(totalPages) pages)")
                } catch {
                    jobs[index].preprocessedPDFURL = nil
                    jobs[index].totalPages = nil
                    logStore.add("Preprocess failed: \(sourceURL.lastPathComponent) — \(error.localizedDescription)")
                }
            }
            isPreprocessing = false
            logStore.add("Preprocess finished.")
        }
    }

    func refreshPrinters() {
        let names = printer.availablePrinterNames()
        availablePrinters = names

        if names.isEmpty {
            selectedPrinterName = ""
            logStore.add("No printer found on this Mac.")
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
            lastErrorMessage = "Preprocess is still running. Wait for it to finish before printing."
            return
        }
        if availablePrinters.isEmpty {
            refreshPrinters()
        }
        guard !selectedPrinterName.isEmpty else {
            lastErrorMessage = "No printer selected. Add/select a printer first."
            return
        }
        let exportAsPDF = selectedPrinterName == WordPrinter.virtualPDFPrinterName

        let targetIDs = selectedJobIDs.isEmpty ? Set(jobs.map(\.id)) : selectedJobIDs
        guard !targetIDs.isEmpty else {
            lastErrorMessage = "No jobs selected."
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
                lastErrorMessage = "Preprocess required before printing to a physical printer."
                logStore.add("Cannot print: preprocess missing for \(missing.count) file(s).")
                for fileName in missing {
                    logStore.add("Preprocess required: \(fileName)")
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
                lastErrorMessage = "Select an output folder for Print to PDF."
                return
            }
            logStore.add("Using Print-to-PDF output folder: \(printPDFOutputFolderURL.path)")
            if needsWordFallback {
                guard printer.isWordInstalled() else {
                    lastErrorMessage = "Microsoft Word was not found. Install Word or preprocess all files first."
                    return
                }
                do {
                    try printer.requestAutomationAuthorization()
                } catch {
                    lastErrorMessage = error.localizedDescription
                    logStore.add("Printer setup failed: \(error.localizedDescription)")
                    return
                }
            }
        }

        shouldCancel = false
        isCancelling = false
        isPrinting = true
        logStore.add("Using printer: \(selectedPrinterName)")
        logStore.add("Starting print run for \(targetIDs.count) job(s).")

        printTask = Task { [weak self] in
            guard let self else { return }
            defer {
                isPrinting = false
                isCancelling = false
                printTask = nil
                logStore.add("Print run finished.")
            }

            for index in jobs.indices {
                guard targetIDs.contains(jobs[index].id) else {
                    continue
                }

                if Task.isCancelled || shouldCancel {
                    if jobs[index].status == .pending || jobs[index].status == .printing {
                        jobs[index].status = .cancelled
                        jobs[index].message = "Cancelled before printing."
                    }
                    continue
                }

                jobs[index].status = .printing
                let preprocessedPDFURL = jobs[index].preprocessedPDFURL
                let hasPreprocessedPDF = preprocessedPDFURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
                jobs[index].message = hasPreprocessedPDF
                    ? (exportAsPDF ? "Generating output from preprocessed PDF..." : "Printing preprocessed PDF...")
                    : (exportAsPDF ? "Exporting to PDF in Microsoft Word..." : "Sending to Microsoft Word...")
                logStore.add("Printing: \(jobs[index].fileURL.lastPathComponent)")

                do {
                    let fileURL = jobs[index].fileURL
                    let pageRange = try printer.parsePageRange(from: jobs[index].pageRange)
                    let copies = max(1, jobs[index].copies)
                    let selectedPrinter = selectedPrinterName
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
                    jobs[index].status = .success
                    jobs[index].message = result.message
                    jobs[index].printedAt = Date()
                    logStore.add("Printed successfully: \(jobs[index].fileURL.lastPathComponent)")
                } catch {
                    jobs[index].status = .failed
                    jobs[index].message = error.localizedDescription
                    logStore.add("Print failed: \(jobs[index].fileURL.lastPathComponent) — \(error.localizedDescription)")

                    if case WordPrinterError.notAuthorizedToControlWord = error {
                        shouldCancel = true
                        isCancelling = true
                        logStore.add("Stopping run because Word automation permission is not granted.")
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
        logStore.add("Cancellation requested. Current document may still finish first.")
    }

    func copyLogsToPasteboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(logStore.allText, forType: .string)
        logStore.add("Copied logs to clipboard.")
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
