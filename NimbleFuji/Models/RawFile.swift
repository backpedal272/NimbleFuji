import Foundation

nonisolated struct RawFile: Identifiable, Hashable, Sendable {
    var id: URL { url }
    let url: URL
    let byteCount: Int64
    let modified: Date?

    var name: String { url.lastPathComponent }
    var baseName: String { url.deletingPathExtension().lastPathComponent }
    var folder: String { url.deletingLastPathComponent().path(percentEncoded: false) }

    static let fileExtensions: Set<String> = ["raf"]

    init?(url: URL) {
        guard Self.fileExtensions.contains(url.pathExtension.lowercased()) else { return nil }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey])
        guard values?.isRegularFile ?? true else { return nil }
        self.url = url.standardizedFileURL
        self.byteCount = Int64(values?.fileSize ?? 0)
        self.modified = values?.contentModificationDate
    }
}
