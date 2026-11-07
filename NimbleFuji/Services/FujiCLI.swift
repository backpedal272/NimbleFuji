import Foundation

nonisolated struct ProcessResult: Sendable {
    let status: Int32
    let stdout: String
    let stderr: String
}

/// Lets the caller terminate a running fujicli process (Cancel button).
nonisolated final class ProcessHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    /// Returns false when cancellation already happened, so the process must not start.
    fileprivate func attach(_ process: Process) -> Bool {
        lock.withLock {
            guard !cancelled else { return false }
            self.process = process
            return true
        }
    }

    func cancel() {
        lock.withLock {
            cancelled = true
            if let process, process.isRunning { process.terminate() }
        }
    }

    var isCancelled: Bool { lock.withLock { cancelled } }
}

private nonisolated final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    func append(_ chunk: Data) { lock.withLock { data.append(chunk) } }
    var text: String { lock.withLock { String(decoding: data, as: UTF8.self) } }
}

nonisolated enum FujiCLIError: LocalizedError {
    case notInstalled
    case cancelled
    case failed(command: String, message: String)

    /// fujicli refuses a Dynamic Range above the one the RAW was shot with.
    var isDynamicRangeTooHigh: Bool {
        guard case let .failed(_, message) = self else { return false }
        return message.localizedCaseInsensitiveContains("Dynamic Range cannot exceed")
    }

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            "fujicli wasn't found. Set its location in Settings."
        case .cancelled:
            "Cancelled."
        case let .failed(_, message):
            message
        }
    }
}

/// Thin async wrapper around the `fujicli` command-line tool.
nonisolated struct FujiCLI: Sendable {
    let executable: URL

    static var defaultSearchPaths: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        return [
            "\(home).local/bin/fujicli",
            "\(home).cargo/bin/fujicli",
            "/opt/homebrew/bin/fujicli",
            "/usr/local/bin/fujicli",
        ].map { $0.replacingOccurrences(of: "//", with: "/") }
    }

    /// Uses `preferredPath` when it points at an executable, otherwise searches the usual places.
    static func locate(preferredPath: String?) -> FujiCLI? {
        let fm = FileManager.default
        var candidates: [String] = []
        if let preferredPath, !preferredPath.isEmpty {
            candidates.append((preferredPath as NSString).expandingTildeInPath)
        }
        candidates += defaultSearchPaths
        for path in candidates where fm.isExecutableFile(atPath: path) {
            return FujiCLI(executable: URL(filePath: path))
        }
        return nil
    }

    // MARK: Commands

    func version() async -> String? {
        guard let result = try? await run(["--version"]), result.status == 0 else { return nil }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Names of connected supported cameras (empty when none).
    func connectedCameras() async throws -> [String] {
        let result = try await run(["device", "list"])
        guard result.status == 0 else {
            throw FujiCLIError.failed(command: "device list", message: Self.explain(result))
        }
        return result.stdout
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("- ") }
            .map { String($0.dropFirst(2)) }
    }

    /// Renders `input` on the camera with `recipe` applied over the as-shot settings.
    func render(input: URL, output: URL, recipe: Recipe, draft: Bool, handle: ProcessHandle?) async throws {
        let args = Self.renderArguments(input: input, output: output, recipe: recipe, draft: draft)
        let result = try await run(args, handle: handle)
        if handle?.isCancelled == true { throw FujiCLIError.cancelled }
        guard result.status == 0 else {
            throw FujiCLIError.failed(command: "image render", message: Self.explain(result))
        }
    }

    static func renderArguments(input: URL, output: URL, recipe: Recipe, draft: Bool) -> [String] {
        var args = ["image", "render", "--file-type=jpeg"]
        if draft { args.append("--draft") }
        args += recipe.fujicliFlags()
        args += [input.path(percentEncoded: false), output.path(percentEncoded: false)]
        return args
    }

    /// Turns fujicli's stderr into something actionable.
    static func explain(_ result: ProcessResult) -> String {
        let raw = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = raw.isEmpty ? "fujicli exited with status \(result.status)." : raw
        let lower = message.lowercased()
        if lower.contains("no supported camera") || lower.contains("no camera") || lower.contains("not found") && lower.contains("device") {
            return message + "\n\nConnect the X-T5 with a data cable and set MENU › NETWORK/USB SETTING › CONNECTION MODE to USB RAW CONV./BACKUP RESTORE."
        }
        if lower.contains("access") || lower.contains("busy") || lower.contains("permission") || lower.contains("claim") {
            return message + "\n\nmacOS may be holding the camera. Try “Release Camera from macOS” in Settings, then reconnect."
        }
        return message
    }

    // MARK: Process

    @concurrent
    func run(_ arguments: [String], handle: ProcessHandle? = nil) async throws -> ProcessResult {
        let executable = self.executable
        guard FileManager.default.isExecutableFile(atPath: executable.path(percentEncoded: false)) else {
            throw FujiCLIError.notInstalled
        }
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            var environment = ProcessInfo.processInfo.environment
            // fujicli shells out to exiftool for some commands; GUI apps get a minimal PATH.
            environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (environment["PATH"] ?? "")
            process.environment = environment

            let outPipe = Pipe(), errPipe = Pipe()
            let out = OutputBuffer(), err = OutputBuffer()
            process.standardOutput = outPipe
            process.standardError = errPipe
            outPipe.fileHandleForReading.readabilityHandler = { out.append($0.availableData) }
            errPipe.fileHandleForReading.readabilityHandler = { err.append($0.availableData) }

            process.terminationHandler = { process in
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                out.append(outPipe.fileHandleForReading.readDataToEndOfFile())
                err.append(errPipe.fileHandleForReading.readDataToEndOfFile())
                continuation.resume(returning: ProcessResult(
                    status: process.terminationStatus, stdout: out.text, stderr: err.text))
            }

            if let handle, !handle.attach(process) {
                continuation.resume(throwing: FujiCLIError.cancelled)
                return
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
