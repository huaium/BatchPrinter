import AppKit
import Combine
import PDFKit
import XCTest

final class PageSelectionTests: XCTestCase {
    func testBlankRangeSelectsAllPages() throws {
        XCTAssertNil(try WordPrinter().parsePageRange(from: " \n "))
    }

    func testWhitespaceAndMixedSegments() throws {
        let range = try XCTUnwrap(WordPrinter().parsePageRange(from: " 4, 2 - 3, 1 "))
        XCTAssertEqual(range.displayText, "4,2-3,1")
    }

    func testInvalidRangesAreRejected() {
        for range in ["0", "-1", "3-1", "1,,2", "1-", "1-2-3", "abc", "1,"] {
            XCTAssertThrowsError(try WordPrinter().parsePageRange(from: range), range)
        }
    }

    func testSelectionPreservesOrderAndRepeatedPages() throws {
        try withTemporaryFolder { folder in
            let source = folder.appendingPathComponent("source.pdf")
            try makePDF(at: source, pages: 4)
            let output = folder.appendingPathComponent("selected.pdf")
            let printer = WordPrinter()
            _ = try printer.generatePDFOutputs(from: source, outputURL: output,
                pageRange: printer.parsePageRange(from: "4,2,2,1"), copies: 1)
            XCTAssertEqual(try pageWidths(at: output), [104, 102, 102, 101])
            XCTAssertEqual(try pageWidths(at: source), [101, 102, 103, 104])
        }
    }

    func testRangeClipsToDocumentAndUnavailableSelectionFails() throws {
        try withTemporaryFolder { folder in
            let source = folder.appendingPathComponent("source.pdf")
            try makePDF(at: source, pages: 3)
            let printer = WordPrinter()
            let output = folder.appendingPathComponent("clipped.pdf")
            _ = try printer.generatePDFOutputs(from: source, outputURL: output,
                pageRange: printer.parsePageRange(from: "2-99"), copies: 1)
            XCTAssertEqual(try pageWidths(at: output), [102, 103])
            XCTAssertThrowsError(try printer.generatePDFOutputs(from: source,
                outputURL: folder.appendingPathComponent("invalid.pdf"),
                pageRange: printer.parsePageRange(from: "4"), copies: 1))
        }
    }

    func testCopiesContainAllPagesAndPreserveExistingCopy() throws {
        try withTemporaryFolder { folder in
            let source = folder.appendingPathComponent("source.pdf")
            try makePDF(at: source, pages: 2)
            let existing = folder.appendingPathComponent("output (copy 2).pdf")
            try makePDF(at: existing, pages: 1)
            let output = folder.appendingPathComponent("output.pdf")
            _ = try WordPrinter().generatePDFOutputs(from: source, outputURL: output,
                pageRange: nil, copies: 2)
            XCTAssertEqual(try pageWidths(at: output), [101, 102])
            XCTAssertEqual(try pageWidths(at: existing), [101])
            XCTAssertEqual(try pageWidths(at: folder.appendingPathComponent("output (copy 2) (1).pdf")), [101, 102])
        }
    }
}

final class DuplicateFilenameTests: XCTestCase {
    func testSameBasenameFromDifferentFoldersPreservesBothDocuments() throws {
        try withTemporaryFolder { folder in
            let outputFolder = folder.appendingPathComponent("output")
            try FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)
            let printer = WordPrinter()
            for (index, parent) in ["first", "second"].enumerated() {
                let directory = folder.appendingPathComponent(parent)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let source = directory.appendingPathComponent("教学大纲.pdf")
                try makePDF(at: source, pages: index + 1)
                let output = MainViewModel.nextPDFOutputURL(for: source, in: outputFolder)
                _ = try printer.generatePDFOutputs(from: source, outputURL: output, pageRange: nil, copies: 1)
            }
            XCTAssertEqual(try pageWidths(at: outputFolder.appendingPathComponent("教学大纲.pdf")), [101])
            XCTAssertEqual(try pageWidths(at: outputFolder.appendingPathComponent("教学大纲 (1).pdf")), [101, 102])
        }
    }

    func testPreparationAndExportSkipExistingNumberedNames() throws {
        try withTemporaryFolder { folder in
            for name in ["Report.pdf", "Report (1).pdf"] {
                try Data("existing".utf8).write(to: folder.appendingPathComponent(name))
            }
            let source = folder.appendingPathComponent("Report.docx")
            XCTAssertEqual(MainViewModel.nextPreprocessedPDFURL(for: source, in: folder).lastPathComponent, "Report (2).pdf")
            XCTAssertEqual(MainViewModel.nextPDFOutputURL(for: source, in: folder).lastPathComponent, "Report (2).pdf")
            XCTAssertEqual(try String(contentsOf: folder.appendingPathComponent("Report.pdf"), encoding: .utf8), "existing")
        }
    }
}

final class PreparationTests: XCTestCase {
    @MainActor
    func testImmediateCancellationAndRetry() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source.pdf")
        try makePDF(at: source, pages: 2)
        let model = MainViewModel()
        model.jobs = [PrintJob(fileURL: source), PrintJob(fileURL: source)]
        model.preprocessAllToPDF(outputMode: .systemTemporary)
        model.cancelPreprocessing()
        try await waitForPreparation(model)
        XCTAssertEqual(model.jobs.map(\.status), [.cancelled, .cancelled])
        XCTAssertFalse(model.isCancelling)
        model.preprocessAllToPDF(outputMode: .systemTemporary)
        try await waitForPreparation(model)
        XCTAssertEqual(model.jobs.map(\.status), [.ready, .ready])
        XCTAssertEqual(model.jobs.map(\.totalPages), [2, 2])
    }

    @MainActor
    func testCancellationKeepsCompletedFileAndCancelsRemainingFiles() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source.pdf")
        try makePDF(at: source, pages: 1)
        let model = MainViewModel()
        model.jobs = (0..<3).map { _ in PrintJob(fileURL: source) }
        let subscription = model.$jobs.sink { jobs in
            if jobs.first?.status == .ready { model.cancelPreprocessing() }
        }
        defer { subscription.cancel() }
        model.preprocessAllToPDF(outputMode: .systemTemporary)
        try await waitForPreparation(model)
        XCTAssertEqual(model.jobs.map(\.status), [.ready, .cancelled, .cancelled])
        XCTAssertEqual(model.jobs.first?.preprocessedPDFURL, source)
        XCTAssertFalse(model.isCancelling)
    }

    @MainActor
    func testFailureDoesNotStopBatchAndRepairedFileRecovers() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let broken = folder.appendingPathComponent("broken.pdf")
        let valid = folder.appendingPathComponent("valid.pdf")
        try Data("not a PDF".utf8).write(to: broken)
        try makePDF(at: valid, pages: 2)
        let model = MainViewModel()
        model.jobs = [PrintJob(fileURL: broken), PrintJob(fileURL: valid)]
        model.preprocessAllToPDF(outputMode: .systemTemporary)
        try await waitForPreparation(model)
        XCTAssertEqual(model.jobs.map(\.status), [.failed, .ready])
        XCTAssertFalse(model.jobs[0].message.isEmpty)
        XCTAssertNil(model.jobs[0].preprocessedPDFURL)
        XCTAssertNil(model.jobs[0].totalPages)
        model.showOnlyFailures = true
        XCTAssertEqual(model.filteredJobs.map(\.fileURL), [broken])
        let failureMessage = model.jobs[0].message
        try makePDF(at: broken, pages: 3)
        model.preprocessAllToPDF(outputMode: .systemTemporary)
        try await waitForPreparation(model)
        XCTAssertEqual(model.jobs.map(\.status), [.ready, .ready])
        XCTAssertEqual(model.jobs[0].totalPages, 3)
        XCTAssertEqual(model.jobs[0].preprocessedPDFURL, broken)
        XCTAssertNotEqual(model.jobs[0].message, failureMessage)
        XCTAssertTrue(model.filteredJobs.isEmpty)
        XCTAssertFalse(model.isPreprocessing)
        XCTAssertFalse(model.isCancelling)
    }
}

private func temporaryFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("BatchPrinterTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

private func withTemporaryFolder(_ body: (URL) throws -> Void) throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    try body(folder)
}

// Distinct page widths identify pages without depending on fonts or text extraction.
private func makePDF(at url: URL, pages: Int) throws {
    let document = PDFDocument()
    for index in 1...pages {
        let page = PDFPage()
        page.setBounds(CGRect(x: 0, y: 0, width: 100 + index, height: 200), for: .mediaBox)
        document.insert(page, at: document.pageCount)
    }
    guard document.write(to: url) else { throw CocoaError(.fileWriteUnknown) }
}

private func pageWidths(at url: URL) throws -> [CGFloat] {
    let document = try XCTUnwrap(PDFDocument(url: url))
    return try (0..<document.pageCount).map { index in
        try XCTUnwrap(document.page(at: index)).bounds(for: .mediaBox).width
    }
}

@MainActor
private func waitForPreparation(_ model: MainViewModel) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while model.isPreprocessing {
        guard ContinuousClock.now < deadline else {
            model.cancelPreprocessing()
            XCTFail("Preparation did not finish within five seconds")
            throw CocoaError(.userCancelled)
        }
        await Task.yield()
    }
}
