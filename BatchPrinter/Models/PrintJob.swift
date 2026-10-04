import Foundation

enum PrintJobStatus: String, Codable, CaseIterable {
  case pending = "Pending"
  case preparing = "Preparing"
  case ready = "Ready"
  case printing = "Printing"
  case submitted = "Submitted"
  case saved = "Saved"
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
    case .submitted:
      return L10n.tr("status.submitted")
    case .saved:
      return L10n.tr("status.saved")
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
  var completedAt: Date?
  var printJobID: String?

  var fileName: String {
    fileURL.lastPathComponent
  }

  var directoryName: String {
    fileURL.deletingLastPathComponent().lastPathComponent
  }

  var previewURL: URL? {
    if let preprocessedPDFURL, FileManager.default.fileExists(atPath: preprocessedPDFURL.path) {
      return preprocessedPDFURL
    }
    return FileManager.default.fileExists(atPath: fileURL.path) ? fileURL : nil
  }

  var isPDFSource: Bool {
    fileURL.pathExtension.lowercased() == "pdf"
  }
}
