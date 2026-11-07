import Foundation
import Observation

/// Renders every selected RAW with every selected recipe, one at a time
/// (the camera processes one image at a time).
@Observable
final class BatchRenderer {
    enum Status: Equatable {
        case pending
        case running
        case done(URL, TimeInterval)
        case failed(String)
        case cancelled

        var isFinished: Bool {
            switch self {
            case .pending, .running: false
            default: true
            }
        }
    }

    struct Job: Identifiable {
        let id = UUID()
        let raw: RawFile
        let recipe: Recipe
        var status: Status = .pending
        /// Set when the recipe had to be adjusted to fit the RAW, e.g. Dynamic Range capped.
        var note: String?
    }

    private(set) var jobs: [Job] = []
    private(set) var isRunning = false
    private(set) var startedAt: Date?
    private(set) var finishedAt: Date?
    private var handle: ProcessHandle?
    private var task: Task<Void, Never>?

    var finishedCount: Int { jobs.count { $0.status.isFinished } }
    var succeededCount: Int { jobs.count { if case .done = $0.status { true } else { false } } }
    var failedCount: Int { jobs.count { if case .failed = $0.status { true } else { false } } }
    var progress: Double { jobs.isEmpty ? 0 : Double(finishedCount) / Double(jobs.count) }
    var currentJob: Job? { jobs.first { $0.status == .running } }
    var outputFolder: URL?

    func start(raws: [RawFile], recipes: [Recipe], outputFolder: URL, cli: any CameraEngine, draft: Bool, overwrite: Bool) {
        guard !isRunning else { return }
        jobs = raws.flatMap { raw in recipes.map { Job(raw: raw, recipe: $0) } }
        self.outputFolder = outputFolder
        isRunning = true
        startedAt = .now
        finishedAt = nil
        let handle = ProcessHandle()
        self.handle = handle

        task = Task {
            defer {
                isRunning = false
                finishedAt = .now
                self.handle = nil
            }
            do {
                try FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)
            } catch {
                for index in jobs.indices { jobs[index].status = .failed(error.localizedDescription) }
                return
            }
            var reserved = Set<URL>()
            for index in jobs.indices {
                if handle.isCancelled {
                    jobs[index].status = .cancelled
                    continue
                }
                let job = jobs[index]
                let destination = Self.outputURL(
                    for: job.raw, recipe: job.recipe, in: outputFolder, overwrite: overwrite, reserved: reserved)
                reserved.insert(destination)
                jobs[index].status = .running
                let began = Date.now
                do {
                    do {
                        jobs[index].note = try await Self.render(raw: job.raw, recipe: job.recipe, to: destination, cli: cli, draft: draft, handle: handle)
                    } catch let error where error.isDynamicRangeTooHigh && job.recipe.dynamicRange != nil {
                        // The camera can't raise DR above what the RAW was shot with
                        // (e.g. DR400 on a DR200 shot). Fall back to the as-shot DR,
                        // which is the highest it allows.
                        var capped = job.recipe
                        capped.dynamicRange = nil
                        _ = try await Self.render(raw: job.raw, recipe: capped, to: destination, cli: cli, draft: draft, handle: handle)
                        jobs[index].note = "\(job.recipe.dynamicRange?.label ?? "DR") is higher than the photo was shot with; used the as-shot dynamic range."
                    }
                    jobs[index].status = .done(destination, Date.now.timeIntervalSince(began))
                } catch FujiCLIError.cancelled {
                    jobs[index].status = .cancelled
                } catch {
                    jobs[index].status = .failed(error.localizedDescription)
                }
            }
        }
    }

    func cancel() {
        handle?.cancel()
    }

    func clear() {
        guard !isRunning else { return }
        jobs = []
        startedAt = nil
        finishedAt = nil
    }

    /// Renders into a temporary file first so a failed render never leaves a
    /// half-written JPG in the output folder.
    private static func render(raw: RawFile, recipe: Recipe, to destination: URL, cli: any CameraEngine, draft: Bool, handle: ProcessHandle) async throws -> String? {
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appending(path: "NimbleFuji-\(UUID().uuidString).jpg")
        defer { try? fm.removeItem(at: temp) }
        let note = try await cli.renderImage(input: raw.url, output: temp, recipe: recipe, draft: draft, handle: handle)
        guard fm.fileExists(atPath: temp.path(percentEncoded: false)) else {
            throw FujiCLIError.failed(command: "image render", message: "The camera finished but no image was written.")
        }
        if fm.fileExists(atPath: destination.path(percentEncoded: false)) {
            _ = try fm.replaceItemAt(destination, withItemAt: temp)
        } else {
            try fm.moveItem(at: temp, to: destination)
        }
        return note
    }

    /// `<output>/<RAW name>_<Recipe>.jpg`, adding `-2`, `-3`… unless overwriting.
    static func outputURL(for raw: RawFile, recipe: Recipe, in folder: URL, overwrite: Bool, reserved: Set<URL> = []) -> URL {
        let base = "\(raw.baseName)_\(recipe.slug)"
        var candidate = folder.appending(path: base + ".jpg")
        func taken(_ url: URL) -> Bool {
            reserved.contains(url) || (!overwrite && FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
        }
        var n = 2
        while taken(candidate) {
            candidate = folder.appending(path: "\(base)-\(n).jpg")
            n += 1
        }
        return candidate
    }
}
