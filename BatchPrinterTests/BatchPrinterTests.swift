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
      _ = try printer.generatePDFOutputs(
        from: source, outputURL: output,
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
      _ = try printer.generatePDFOutputs(
        from: source, outputURL: output,
        pageRange: printer.parsePageRange(from: "2-99"), copies: 1)
      XCTAssertEqual(try pageWidths(at: output), [102, 103])
      XCTAssertThrowsError(
        try printer.generatePDFOutputs(
          from: source,
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
      _ = try WordPrinter().generatePDFOutputs(
        from: source, outputURL: output,
        pageRange: nil, copies: 2)
      XCTAssertEqual(try pageWidths(at: output), [101, 102])
      XCTAssertEqual(try pageWidths(at: existing), [101])
      XCTAssertEqual(
        try pageWidths(at: folder.appendingPathComponent("output (copy 2) (1).pdf")), [101, 102])
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
        _ = try printer.generatePDFOutputs(
          from: source, outputURL: output, pageRange: nil, copies: 1)
      }
      XCTAssertEqual(try pageWidths(at: outputFolder.appendingPathComponent("教学大纲.pdf")), [101])
      XCTAssertEqual(
        try pageWidths(at: outputFolder.appendingPathComponent("教学大纲 (1).pdf")), [101, 102])
    }
  }

  func testPreparationAndExportSkipExistingNumberedNames() throws {
    try withTemporaryFolder { folder in
      for name in ["Report.pdf", "Report (1).pdf"] {
        try Data("existing".utf8).write(to: folder.appendingPathComponent(name))
      }
      let source = folder.appendingPathComponent("Report.docx")
      XCTAssertEqual(
        MainViewModel.nextPreprocessedPDFURL(for: source, in: folder).lastPathComponent,
        "Report (2).pdf")
      XCTAssertEqual(
        MainViewModel.nextPDFOutputURL(for: source, in: folder).lastPathComponent, "Report (2).pdf")
      XCTAssertEqual(
        try String(contentsOf: folder.appendingPathComponent("Report.pdf"), encoding: .utf8),
        "existing")
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

final class PreviewAndRetryTests: XCTestCase {
  func testPreviewPrefersPreparedPDFAndFallsBackToSource() throws {
    try withTemporaryFolder { folder in
      let source = folder.appendingPathComponent("source.docx")
      let prepared = folder.appendingPathComponent("prepared.pdf")
      try Data().write(to: source)
      try makePDF(at: prepared, pages: 1)
      var job = PrintJob(fileURL: source)
      XCTAssertEqual(job.previewURL, source)
      job.preprocessedPDFURL = prepared
      XCTAssertEqual(job.previewURL, prepared)
      job.preprocessedPDFURL = folder.appendingPathComponent("missing.pdf")
      XCTAssertEqual(job.previewURL, source)
      XCTAssertNil(PrintJob(fileURL: folder.appendingPathComponent("missing.docx")).previewURL)
    }
  }

  @MainActor
  func testRetryPreparationOnlyTouchesFailedJobsAndPreservesSettings() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let source = folder.appendingPathComponent("repaired.pdf")
    try makePDF(at: source, pages: 3)
    let model = MainViewModel()
    var failed = PrintJob(fileURL: source)
    failed.status = .failed
    failed.pageRange = "3,1"
    failed.copies = 2
    failed.message = "Previous error"
    var submitted = PrintJob(fileURL: source)
    submitted.status = .submitted
    submitted.printJobID = "printer-42"
    submitted.message = "Submitted"
    let cancelled = PrintJob(fileURL: source, status: .cancelled)
    model.jobs = [failed, submitted, cancelled]
    XCTAssertEqual(model.failedJobIDs, [failed.id])
    model.retryFailed()
    try await waitForPreparation(model)
    XCTAssertEqual(model.jobs[0].status, .ready)
    XCTAssertEqual(model.jobs[0].pageRange, "3,1")
    XCTAssertEqual(model.jobs[0].copies, 2)
    XCTAssertEqual(model.jobs[0].totalPages, 3)
    XCTAssertEqual(model.jobs[1], submitted)
    XCTAssertEqual(model.jobs[2], cancelled)
    XCTAssertEqual(model.selectedJobIDs, [failed.id])
    XCTAssertTrue(model.failedJobIDs.isEmpty)
    model.retryFailed()
    XCTAssertFalse(model.isPreprocessing)
    XCTAssertFalse(model.isPrinting)
  }
}

final class RefreshTests: XCTestCase {
  @MainActor
  func testRefreshPreservesSettingsAndSelectionWhileAddingAndRemovingFiles() throws {
    try withTemporaryFolder { folder in
      let retained = folder.appendingPathComponent("retained.pdf")
      let removed = folder.appendingPathComponent("removed.pdf")
      let added = folder.appendingPathComponent("added.pdf")
      try makePDF(at: retained, pages: 2)
      try makePDF(at: removed, pages: 1)
      let model = MainViewModel()
      model.selectedFolderURL = folder
      model.scanFiles()
      XCTAssertEqual(
        model.jobs.count, 2,
        "Folder: \(folder.path), error: \(model.lastErrorMessage ?? "none"), jobs: \(model.jobs.map { $0.fileURL.path })"
      )
      let retainedIndex = try XCTUnwrap(
        model.jobs.firstIndex { $0.fileURL.resolvingSymlinksInPath().path == retained.path })
      let removedJob = try XCTUnwrap(
        model.jobs.first { $0.fileURL.resolvingSymlinksInPath().path == removed.path })
      model.jobs[retainedIndex].pageRange = "2,1"
      model.jobs[retainedIndex].copies = 3
      model.jobs[retainedIndex].status = .submitted
      model.jobs[retainedIndex].message = "Previous submission"
      model.jobs[retainedIndex].completedAt = Date()
      model.jobs[retainedIndex].printJobID = "printer-123"
      let retainedID = model.jobs[retainedIndex].id
      model.selectedJobIDs = [retainedID, removedJob.id]
      try FileManager.default.removeItem(at: removed)
      try makePDF(at: retained, pages: 4)
      try makePDF(at: added, pages: 1)

      model.scanFiles()

      let job = try XCTUnwrap(
        model.jobs.first { $0.fileURL.resolvingSymlinksInPath().path == retained.path })
      XCTAssertEqual(job.id, retainedID)
      XCTAssertEqual(job.pageRange, "2,1")
      XCTAssertEqual(job.copies, 3)
      XCTAssertEqual(job.totalPages, 4)
      XCTAssertEqual(job.status, .pending)
      XCTAssertTrue(job.message.isEmpty)
      XCTAssertNil(job.completedAt)
      XCTAssertNil(job.printJobID)
      XCTAssertEqual(model.selectedJobIDs, [retainedID])
      XCTAssertFalse(
        model.jobs.contains { $0.fileURL.resolvingSymlinksInPath().path == removed.path })
      let newJob = try XCTUnwrap(
        model.jobs.first { $0.fileURL.resolvingSymlinksInPath().path == added.path })
      XCTAssertEqual(newJob.pageRange, "")
      XCTAssertEqual(newJob.copies, 1)
    }
  }

  @MainActor
  func testRefreshMatchesFullPathsForDuplicateNamesAndRecursiveScan() throws {
    try withTemporaryFolder { folder in
      let nested = folder.appendingPathComponent("nested")
      try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
      let rootFile = folder.appendingPathComponent("Report.docx")
      let nestedFile = nested.appendingPathComponent("Report.docx")
      try Data().write(to: rootFile)
      try Data().write(to: nestedFile)
      let model = MainViewModel()
      model.selectedFolderURL = folder
      model.recursiveScan = true
      model.scanFiles()
      XCTAssertEqual(
        model.jobs.count, 2,
        "Folder: \(folder.path), error: \(model.lastErrorMessage ?? "none"), jobs: \(model.jobs.map { $0.fileURL.path })"
      )
      for index in model.jobs.indices {
        model.jobs[index].pageRange =
          model.jobs[index].fileURL.resolvingSymlinksInPath().path == rootFile.path ? "1" : "2-3"
        model.jobs[index].copies =
          model.jobs[index].fileURL.resolvingSymlinksInPath().path == rootFile.path ? 2 : 5
      }
      model.scanFiles()
      let rootJob = try XCTUnwrap(
        model.jobs.first { $0.fileURL.resolvingSymlinksInPath().path == rootFile.path })
      let nestedJob = try XCTUnwrap(
        model.jobs.first { $0.fileURL.resolvingSymlinksInPath().path == nestedFile.path })
      XCTAssertEqual(rootJob.pageRange, "1")
      XCTAssertEqual(rootJob.copies, 2)
      XCTAssertEqual(nestedJob.pageRange, "2-3")
      XCTAssertEqual(nestedJob.copies, 5)
      model.recursiveScan = false
      model.scanFiles()
      XCTAssertEqual(model.jobs.count, 1)
      XCTAssertEqual(model.jobs.first?.id, rootJob.id)
      XCTAssertEqual(model.jobs.first?.copies, 2)
    }
  }
}

private func temporaryFolder() throws -> URL {
  let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
    "BatchPrinterTests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  return folder.resolvingSymlinksInPath()
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
