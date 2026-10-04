import Foundation

@MainActor
final class LogStore: ObservableObject {
  @Published private(set) var lines: [String] = []

  func add(_ line: String) {
    let timestamp = Self.formatter.string(from: Date())
    lines.append("[\(timestamp)] \(line)")
  }

  func clear() {
    lines.removeAll()
  }

  var allText: String {
    lines.joined(separator: "\n")
  }

  private static let formatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter
  }()
}
