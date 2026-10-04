import Foundation

enum PrintJobStatus: String, Codable, CaseIterable {
    case pending = "Pending"
    case preparing = "Preparing"
    case ready = "Ready"
    case printing = "Printing"
    case success = "Printed"
    case failed = "Failed"
    case skipped = "Skipped"
    case cancelled = "Cancelled"

    var localizedLabel: String {
        switch self {
        case .pending:
            return L10n.tr("status.pending")
        case .preparing:
            return L10n.tr("status.preparing")
        case .ready:
            return L10n.tr("status.ready")
        case .printing:
            return L10n.tr("status.printing")
        case .success:
            return L10n.tr("status.success")
        case .failed:
            return L10n.tr("status.failed")
        case .skipped:
            return L10n.tr("status.skipped")
        case .cancelled:
            return L10n.tr("status.cancelled")
        }
    }
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
