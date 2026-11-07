import Foundation
import Observation

/// Reads and writes the camera's C1–C7 custom setting slots.
@Observable
final class CameraSlots {
    struct Slot: Identifiable {
        let number: Int
        var id: Int { number }
        var title: String { "C\(number)" }
        var recipe: Recipe?
        var error: String?
        var isWriting = false

        var name: String { recipe?.name ?? "" }
    }

    static let slotNumbers = Array(1...7)

    private(set) var slots: [Slot] = slotNumbers.map { Slot(number: $0) }
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var lastError: String?
    private(set) var busyMessage: String?
    /// Backup made before this session's first slot write.
    private(set) var sessionBackup: URL?

    var isBusy: Bool { isLoading || busyMessage != nil }

    static var backupFolder: URL {
        URL.applicationSupportDirectory
            .appending(path: "Nimble Fuji", directoryHint: .isDirectory)
            .appending(path: "Backups", directoryHint: .isDirectory)
    }

    // MARK: Reading

    func load(using cli: any CameraEngine) async {
        guard !isBusy else { return }
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        for number in Self.slotNumbers {
            await reload(number, using: cli)
            if lastError != nil, slots.allSatisfy({ $0.recipe == nil }) { break }
        }
        hasLoaded = true
    }

    private func reload(_ number: Int, using cli: any CameraEngine) async {
        let index = number - 1
        do {
            let data = try await cli.readSlot(number)
            slots[index].recipe = try Recipe(fujicliJSON: data)
            slots[index].error = nil
        } catch {
            slots[index].recipe = nil
            slots[index].error = error.localizedDescription
            lastError = error.localizedDescription
        }
    }

    // MARK: Writing

    /// Writes `recipe` into slot `number`, backing up the camera first if this
    /// session hasn't made a backup yet. Returns the backup made, if any.
    @discardableResult
    func write(_ recipe: Recipe, to number: Int, using cli: any CameraEngine) async throws -> URL? {
        guard !isBusy else { return nil }
        let index = number - 1
        lastError = nil
        var newBackup: URL?
        if sessionBackup == nil {
            busyMessage = "Backing up camera settings…"
            defer { busyMessage = nil }
            newBackup = try await backup(using: cli)
            sessionBackup = newBackup
        }
        busyMessage = "Writing \(recipe.name) to C\(number)…"
        slots[index].isWriting = true
        defer {
            busyMessage = nil
            slots[index].isWriting = false
        }
        do {
            try await cli.writeSlot(number, recipe: recipe)
        } catch {
            lastError = error.localizedDescription
            await reload(number, using: cli)
            throw error
        }
        await reload(number, using: cli)
        return newBackup
    }

    /// Exports a full camera backup into the Backups folder.
    func backup(using cli: any CameraEngine) async throws -> URL {
        let folder = Self.backupFolder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HHmmss"
        let stamp = formatter.string(from: .now)
        let url = folder.appending(path: "X-T5 \(stamp).bak")
        try await cli.exportBackup(to: url)
        return url
    }

    func backUpNow(using cli: any CameraEngine) async throws -> URL {
        busyMessage = "Backing up camera settings…"
        defer { busyMessage = nil }
        let url = try await backup(using: cli)
        sessionBackup = url
        return url
    }

    func restore(from url: URL, using cli: any CameraEngine) async throws {
        busyMessage = "Restoring \(url.lastPathComponent)…"
        do {
            try await cli.importBackup(from: url)
        } catch {
            busyMessage = nil
            throw error
        }
        busyMessage = nil
        await load(using: cli)
    }
}
