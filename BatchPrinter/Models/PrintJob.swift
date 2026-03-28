import Foundation

enum PrintJobStatus: String, Codable, CaseIterable {
    case pending = "Pending"
    case printing = "Printing"
    case success = "Printed"
    case failed = "Failed"
    case skipped = "Skipped"
    case cancelled = "Cancelled"
}

struct PrintJob: Identifiable, Hashable {
    let id = UUID()
    let fileURL: URL
    var preprocessedPDFURL: URL?
    var totalPages: Int?
    var pageRange: String = ""
    var copies: Int = 1
    var status: PrintJobStatus = .pending
    var message: String = ""
    var printedAt: Date?

    var fileName: String {
        fileURL.lastPathComponent
    }

    var directoryName: String {
        fileURL.deletingLastPathComponent().lastPathComponent
    }

    var isPDFSource: Bool {
        fileURL.pathExtension.lowercased() == "pdf"
    }
}
