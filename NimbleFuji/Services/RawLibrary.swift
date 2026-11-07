import Foundation
import Observation

/// The RAF files the user has added for processing.
@Observable
final class RawLibrary {
    private(set) var files: [RawFile] = []

    /// Adds files, and every RAF inside folders, skipping duplicates.
    @discardableResult
    func add(_ urls: [URL]) -> Int {
        var known = Set(files.map(\.url))
        var added: [RawFile] = []
        for url in urls {
            for candidate in Self.expand(url) {
                guard let raw = RawFile(url: candidate), !known.contains(raw.url) else { continue }
                known.insert(raw.url)
                added.append(raw)
            }
        }
        files += added
        files.sort { $0.url.path().localizedStandardCompare($1.url.path()) == .orderedAscending }
        return added.count
    }

    func remove(_ ids: Set<RawFile.ID>) {
        files.removeAll { ids.contains($0.id) }
    }

    func removeAll() { files.removeAll() }

    private static func expand(_ url: URL) -> [URL] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory) else { return [] }
        guard isDirectory.boolValue else { return [url] }
        let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants])
        var result: [URL] = []
        while let next = enumerator?.nextObject() as? URL {
            if RawFile.fileExtensions.contains(next.pathExtension.lowercased()) { result.append(next) }
        }
        return result
    }
}
