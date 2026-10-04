import Foundation

struct FileScanner {
  private let supportedExtensions: Set<String> = [
    "doc", "docx", "docm", "dot", "dotx", "dotm", "pdf",
  ]

  func scan(folderURL: URL, recursive: Bool) throws -> [URL] {
    let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .nameKey, .isHiddenKey]
    let options: FileManager.DirectoryEnumerationOptions =
      recursive
      ? [.skipsPackageDescendants]
      : [.skipsSubdirectoryDescendants, .skipsPackageDescendants]

    guard
      let enumerator = FileManager.default.enumerator(
        at: folderURL,
        includingPropertiesForKeys: keys,
        options: options
      )
    else {
      return []
    }

    var results: [URL] = []

    for case let fileURL as URL in enumerator {
      let values = try fileURL.resourceValues(forKeys: Set(keys))
      guard values.isRegularFile == true else { continue }
      guard values.isHidden != true else { continue }

      let name = values.name ?? fileURL.lastPathComponent
      guard shouldInclude(fileName: name) else { continue }
      results.append(fileURL)
    }

    return results.sorted { a, b in
      a.lastPathComponent.localizedCaseInsensitiveCompare(b.lastPathComponent) == .orderedAscending
    }
  }

  private func shouldInclude(fileName: String) -> Bool {
    guard !fileName.hasPrefix("~$") else { return false }
    guard !fileName.hasPrefix(".") else { return false }
    let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
    return supportedExtensions.contains(ext)
  }
}
