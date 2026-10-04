import AppKit
import Foundation
import PDFKit

struct WordPrinterResult: Sendable {
    let success: Bool
    let message: String
    var printJobID: String? = nil
}

enum WordPrinterError: LocalizedError, Sendable {
    static let printerSelectionFailedErrorNumber = 27001
    static let documentAlreadyOpenErrorNumber = 27002

    case wordNotInstalled
    case noPrinterAvailable
    case printerNotFound(String)
    case printerSelectionFailed(String)
    case invalidPageRange(String)
    case invalidCopies(Int)
    case pdfGenerationFailed(String)
    case pageCountUnavailable(String)
    case pdfPrintFailed(String)
    case notAuthorizedToControlWord
    case documentAlreadyOpen(String)
    case appleScriptCompileFailed(String)
    case appleScriptExecutionFailed(String)

    var errorDescription: String? {
        switch self {
        case .wordNotInstalled:
            return L10n.tr("word.error.word_not_installed")
        case .noPrinterAvailable:
            return L10n.tr("word.error.no_printer_available")
        case .printerNotFound(let name):
            return L10n.tr("word.error.printer_not_found", name)
        case .printerSelectionFailed(let name):
            return L10n.tr("word.error.printer_selection_failed", name)
        case .invalidPageRange(let range):
            return L10n.tr("word.error.invalid_page_range", range)
        case .invalidCopies(let copies):
            return L10n.tr("word.error.invalid_copies", copies)
        case .pdfGenerationFailed(let details):
            return L10n.tr("word.error.pdf_generation_failed", details)
        case .pageCountUnavailable(let fileName):
            return L10n.tr("word.error.page_count_unavailable", fileName)
        case .pdfPrintFailed(let details):
            return L10n.tr("word.error.pdf_print_failed", details)
        case .notAuthorizedToControlWord:
            return L10n.tr("word.error.not_authorized")
        case .documentAlreadyOpen(let fileName):
            return L10n.tr("word.error.document_already_open", fileName)
        case .appleScriptCompileFailed(let details):
            return L10n.tr("word.error.applescript_compile_failed", details)
        case .appleScriptExecutionFailed(let details):
            return L10n.tr("word.error.applescript_execution_failed", details)
        }
    }
}

struct WordPrinter: Sendable {
    struct PageRange: Sendable {
        enum Segment: Sendable {
            case single(Int)
            case range(Int, Int)
        }

        let segments: [Segment]

        var displayText: String {
            segments
                .map { segment in
                    switch segment {
                    case .single(let page):
                        return "\(page)"
                    case .range(let start, let end):
                        return "\(start)-\(end)"
                    }
                }
                .joined(separator: ",")
        }
    }

    static let virtualPDFPrinterName = "Print to PDF"

    private let bundleIdentifier = "com.microsoft.Word"

    func isWordInstalled() -> Bool {
        !NSWorkspace.shared.urlsForApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    func availablePrinterNames() -> [String] {
        var names = NSPrinter.printerNames
        if !names.contains(Self.virtualPDFPrinterName) {
            names.append(Self.virtualPDFPrinterName)
        }
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func defaultPrinterName() -> String? {
        NSPrintInfo.shared.printer.name
    }

    func printDocument(at fileURL: URL, pageRange: PageRange?, copies: Int) throws -> WordPrinterResult {
        guard isWordInstalled() else {
            throw WordPrinterError.wordNotInstalled
        }
        guard copies >= 1 else {
            throw WordPrinterError.invalidCopies(copies)
        }

        let printCommands: String
        if let pageRange {
            let commands = pageRange.segments.map { segment in
                switch segment {
                case .single(let page):
                    return "print out openedDocument from \(page) to \(page)"
                case .range(let start, let end):
                    return "print out openedDocument from \(start) to \(end)"
                }
            }
            printCommands = commands.joined(separator: "\n                ")
        } else {
            printCommands = "print out openedDocument"
        }

        let scriptSource = Self.documentAutomationScript(at: fileURL, commands: """
            repeat \(copies) times
                \(printCommands)
                delay 0.3
            end repeat
            delay 2
        """)

        var compileError: NSDictionary?
        guard let script = NSAppleScript(source: scriptSource) else {
            throw WordPrinterError.appleScriptCompileFailed(L10n.tr("word.error.unable_create_applescript"))
        }

        if !script.compileAndReturnError(&compileError) {
            throw WordPrinterError.appleScriptCompileFailed(Self.describe(errorDict: compileError))
        }

        var executionError: NSDictionary?
        _ = script.executeAndReturnError(&executionError)
        if let executionError {
            if Self.appleScriptErrorNumber(from: executionError) == WordPrinterError.documentAlreadyOpenErrorNumber {
                throw WordPrinterError.documentAlreadyOpen(fileURL.lastPathComponent)
            }
            if Self.appleScriptErrorNumber(from: executionError) == -1743 {
                throw WordPrinterError.notAuthorizedToControlWord
            }
            throw WordPrinterError.appleScriptExecutionFailed(Self.describe(errorDict: executionError))
        }

        return WordPrinterResult(success: true, message: L10n.tr("word.message.submitted"))
    }

    func parsePageRange(from rawValue: String) throws -> PageRange? {
        let text = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            return nil
        }

        let compact = text.filter { !$0.isWhitespace }
        if compact.isEmpty {
            throw WordPrinterError.invalidPageRange(rawValue)
        }

        let tokens = compact.split(separator: ",", omittingEmptySubsequences: false)
        guard !tokens.isEmpty else {
            throw WordPrinterError.invalidPageRange(rawValue)
        }

        var segments: [PageRange.Segment] = []
        segments.reserveCapacity(tokens.count)

        for token in tokens {
            guard !token.isEmpty else {
                throw WordPrinterError.invalidPageRange(rawValue)
            }

            let parts = token.split(separator: "-", omittingEmptySubsequences: false)
            guard parts.count == 1 || parts.count == 2 else {
                throw WordPrinterError.invalidPageRange(rawValue)
            }

            guard let start = Int(parts[0]), start > 0 else {
                throw WordPrinterError.invalidPageRange(rawValue)
            }

            if parts.count == 1 {
                segments.append(.single(start))
                continue
            }

            guard let end = Int(parts[1]), end >= start else {
                throw WordPrinterError.invalidPageRange(rawValue)
            }
            segments.append(.range(start, end))
        }

        return PageRange(segments: segments)
    }

    func pageCountForPDF(at pdfURL: URL) throws -> Int {
        guard let document = PDFDocument(url: pdfURL) else {
            throw WordPrinterError.pageCountUnavailable(pdfURL.lastPathComponent)
        }
        let count = document.pageCount
        guard count > 0 else {
            throw WordPrinterError.pageCountUnavailable(pdfURL.lastPathComponent)
        }
        return count
    }

    func generatePDFOutputs(
        from sourcePDFURL: URL,
        outputURL: URL,
        pageRange: PageRange?,
        copies: Int
    ) throws -> WordPrinterResult {
        guard copies >= 1 else {
            throw WordPrinterError.invalidCopies(copies)
        }
        try FileManager.default.copyItem(at: sourcePDFURL, to: outputURL)
        try postProcessExportedPDF(at: outputURL, pageRange: pageRange, copies: copies)
        return WordPrinterResult(success: true, message: L10n.tr("word.message.saved_pdf_path", outputURL.path))
    }

    func printPDF(
        at pdfURL: URL,
        printerName: String,
        pageRange: PageRange?,
        copies: Int
    ) throws -> WordPrinterResult {
        guard copies >= 1 else {
            throw WordPrinterError.invalidCopies(copies)
        }

        var printablePDFURL = pdfURL
        var temporaryPDFURL: URL?
        if let pageRange {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("BatchPrinter-Print-\(UUID().uuidString)")
                .appendingPathExtension("pdf")
            try FileManager.default.copyItem(at: pdfURL, to: tempURL)
            try postProcessExportedPDF(at: tempURL, pageRange: pageRange, copies: 1)
            printablePDFURL = tempURL
            temporaryPDFURL = tempURL
        }
        defer {
            if let temporaryPDFURL {
                try? FileManager.default.removeItem(at: temporaryPDFURL)
            }
        }

        let arguments: [String] = ["-d", printerName, "-n", "\(copies)", printablePDFURL.path]

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/lp")
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C"
        process.environment = environment

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errorOutput = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            let details = errorOutput.isEmpty ? output : errorOutput
            throw WordPrinterError.pdfPrintFailed(details.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let message = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return WordPrinterResult(
            success: true,
            message: message.isEmpty ? L10n.tr("word.message.submitted") : message,
            printJobID: Self.printJobID(from: message)
        )
    }

    static func printJobID(from output: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: #"(?m)^request id is (\S+-[0-9]+)(?:\s|$)"#),
              let match = expression.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let range = Range(match.range(at: 1), in: output) else { return nil }
        return String(output[range])
    }

    func exportDocumentAsPDF(
        at fileURL: URL,
        outputURL: URL,
        pageRange: PageRange?,
        copies: Int
    ) throws -> WordPrinterResult {
        guard isWordInstalled() else {
            throw WordPrinterError.wordNotInstalled
        }
        guard copies >= 1 else {
            throw WordPrinterError.invalidCopies(copies)
        }

        let escapedOutputPath = outputURL.path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let scriptSource = Self.documentAutomationScript(at: fileURL, commands: """
            save as openedDocument file name "\(escapedOutputPath)" file format format PDF
        """)

        var compileError: NSDictionary?
        guard let script = NSAppleScript(source: scriptSource) else {
            throw WordPrinterError.appleScriptCompileFailed(L10n.tr("word.error.unable_create_applescript"))
        }

        if !script.compileAndReturnError(&compileError) {
            throw WordPrinterError.appleScriptCompileFailed(Self.describe(errorDict: compileError))
        }

        var executionError: NSDictionary?
        _ = script.executeAndReturnError(&executionError)
        if let executionError {
            if Self.appleScriptErrorNumber(from: executionError) == WordPrinterError.documentAlreadyOpenErrorNumber {
                throw WordPrinterError.documentAlreadyOpen(fileURL.lastPathComponent)
            }
            if Self.appleScriptErrorNumber(from: executionError) == -1743 {
                throw WordPrinterError.notAuthorizedToControlWord
            }
            throw WordPrinterError.appleScriptExecutionFailed(Self.describe(errorDict: executionError))
        }

        try postProcessExportedPDF(at: outputURL, pageRange: pageRange, copies: copies)
        return WordPrinterResult(success: true, message: L10n.tr("word.message.saved_pdf_path", outputURL.path))
    }

    /// Refuse user-owned documents before opening, and resolve the input by its
    /// full path rather than following whichever window becomes active.
    private static func documentAutomationScript(at fileURL: URL, commands: String) -> String {
        let escapedPath = fileURL.resolvingSymlinksInPath().path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return """
        set targetFile to (POSIX file "\(escapedPath)") as alias
        tell application "Microsoft Word"
            activate
            set existingDocuments to get documents
            repeat with candidateDocument in existingDocuments
                set candidateFile to missing value
                try
                    set candidateFile to (full name of candidateDocument) as alias
                end try
                if candidateFile is targetFile then
                    error "Document is already open in Word" number \(WordPrinterError.documentAlreadyOpenErrorNumber)
                end if
            end repeat
            set openedDocument to missing value
            try
                open targetFile read only true revert false
                set currentDocuments to get documents
                repeat with candidateDocument in currentDocuments
                    set candidateFile to missing value
                    try
                        set candidateFile to (full name of candidateDocument) as alias
                    end try
                    if candidateFile is targetFile then
                        set openedDocument to contents of candidateDocument
                        exit repeat
                    end if
                end repeat
                if openedDocument is missing value then
                    error "Unable to locate the opened Word document" number -1728
                end if
                delay 0.8
                \(commands)
                close openedDocument saving no
            on error errorText number errorNumber
                if openedDocument is not missing value then
                    try
                        close openedDocument saving no
                    end try
                end if
                error errorText number errorNumber
            end try
        end tell
        """
    }

    private func postProcessExportedPDF(at outputURL: URL, pageRange: PageRange?, copies: Int) throws {
        guard let sourceDocument = PDFDocument(url: outputURL) else {
            throw WordPrinterError.pdfGenerationFailed(L10n.tr("word.error.cannot_read_exported_pdf"))
        }
        let sourcePageCount = sourceDocument.pageCount
        guard sourcePageCount > 0 else {
            throw WordPrinterError.pdfGenerationFailed(L10n.tr("word.error.exported_pdf_no_pages"))
        }

        let processedDocument: PDFDocument
        if let pageRange {
            let rangedDocument = PDFDocument()

            for segment in pageRange.segments {
                switch segment {
                case .single(let pageNumber):
                    guard pageNumber <= sourcePageCount else {
                        throw WordPrinterError.invalidPageRange(pageRange.displayText)
                    }
                    guard let page = sourceDocument.page(at: pageNumber - 1),
                          let copiedPage = page.copy() as? PDFPage else {
                        throw WordPrinterError.pdfGenerationFailed(L10n.tr("word.error.unable_copy_page", pageNumber))
                    }
                    rangedDocument.insert(copiedPage, at: rangedDocument.pageCount)

                case .range(let start, let end):
                    guard start <= sourcePageCount else {
                        throw WordPrinterError.invalidPageRange(pageRange.displayText)
                    }
                    let lastPage = min(end, sourcePageCount)
                    var pageNumber = start
                    while pageNumber <= lastPage {
                        guard let page = sourceDocument.page(at: pageNumber - 1),
                              let copiedPage = page.copy() as? PDFPage else {
                            throw WordPrinterError.pdfGenerationFailed(L10n.tr("word.error.unable_copy_page", pageNumber))
                        }
                        rangedDocument.insert(copiedPage, at: rangedDocument.pageCount)
                        pageNumber += 1
                    }
                }
            }
            processedDocument = rangedDocument
        } else {
            processedDocument = sourceDocument
        }

        guard processedDocument.write(to: outputURL) else {
            throw WordPrinterError.pdfGenerationFailed(L10n.tr("word.error.unable_write_pdf", outputURL.path))
        }

        if copies <= 1 {
            return
        }

        let baseName = outputURL.deletingPathExtension().lastPathComponent
        let directory = outputURL.deletingLastPathComponent()
        var copyIndex = 2
        while copyIndex <= copies {
            let copyURL = Self.nextAvailablePDFURL(
                baseName: "\(baseName) (copy \(copyIndex))",
                directory: directory
            )
            guard processedDocument.write(to: copyURL) else {
                throw WordPrinterError.pdfGenerationFailed(L10n.tr("word.error.unable_write_copy", copyURL.path))
            }
            copyIndex += 1
        }
    }

    func requestAutomationAuthorization() throws {
        guard isWordInstalled() else {
            throw WordPrinterError.wordNotInstalled
        }

        // This benign call asks macOS for Apple Events permission before the print loop starts.
        let scriptSource = """
        tell application \"Microsoft Word\"
            get name
        end tell
        """

        var compileError: NSDictionary?
        guard let script = NSAppleScript(source: scriptSource) else {
            throw WordPrinterError.appleScriptCompileFailed(L10n.tr("word.error.unable_create_applescript"))
        }

        if !script.compileAndReturnError(&compileError) {
            throw WordPrinterError.appleScriptCompileFailed(Self.describe(errorDict: compileError))
        }

        var executionError: NSDictionary?
        _ = script.executeAndReturnError(&executionError)
        if let executionError {
            if Self.appleScriptErrorNumber(from: executionError) == -1743 {
                throw WordPrinterError.notAuthorizedToControlWord
            }
            throw WordPrinterError.appleScriptExecutionFailed(Self.describe(errorDict: executionError))
        }
    }

    func configureActivePrinter(named printerName: String) throws {
        let availablePrinters = availablePrinterNames()
        guard !availablePrinters.isEmpty else {
            throw WordPrinterError.noPrinterAvailable
        }
        guard availablePrinters.contains(printerName) else {
            throw WordPrinterError.printerNotFound(printerName)
        }

        let escapedPrinterName = printerName
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let scriptSource = """
        set targetPrinter to \"\(escapedPrinterName)\"
        tell application \"Microsoft Word\"
            activate
            set active printer to targetPrinter
            if active printer is not targetPrinter then
                error "Failed to select printer" number \(WordPrinterError.printerSelectionFailedErrorNumber)
            end if
        end tell
        """

        var compileError: NSDictionary?
        guard let script = NSAppleScript(source: scriptSource) else {
            throw WordPrinterError.appleScriptCompileFailed(L10n.tr("word.error.unable_create_applescript"))
        }

        if !script.compileAndReturnError(&compileError) {
            throw WordPrinterError.appleScriptCompileFailed(Self.describe(errorDict: compileError))
        }

        var executionError: NSDictionary?
        _ = script.executeAndReturnError(&executionError)
        if let executionError {
            if Self.appleScriptErrorNumber(from: executionError) == WordPrinterError.printerSelectionFailedErrorNumber {
                throw WordPrinterError.printerSelectionFailed(printerName)
            }
            if Self.appleScriptErrorNumber(from: executionError) == -1743 {
                throw WordPrinterError.notAuthorizedToControlWord
            }
            throw WordPrinterError.appleScriptExecutionFailed(Self.describe(errorDict: executionError))
        }
    }

    static func appleScriptErrorNumber(from errorDict: NSDictionary?) -> Int? {
        guard let errorDict else { return nil }
        if let number = errorDict[NSAppleScript.errorNumber] as? Int {
            return number
        }
        if let number = errorDict[NSAppleScript.errorNumber] as? NSNumber {
            return number.intValue
        }
        if let number = errorDict["NSAppleScriptErrorNumber"] as? Int {
            return number
        }
        if let number = errorDict["NSAppleScriptErrorNumber"] as? NSNumber {
            return number.intValue
        }
        return nil
    }

    static func describe(errorDict: NSDictionary?) -> String {
        guard let errorDict else { return L10n.tr("word.error.unknown_applescript") }
        let items = errorDict.compactMap { key, value in
            "\(key): \(value)"
        }
        return items.joined(separator: ", ")
    }

    private static func nextAvailablePDFURL(baseName: String, directory: URL) -> URL {
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
}
