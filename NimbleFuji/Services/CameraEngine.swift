// SPDX-License-Identifier: GPL-3.0-only

import FujiKit
import Foundation

/// Something that can talk to the camera: the native FujiKit engine or the fujicli tool.
nonisolated protocol CameraEngine: Sendable {
    /// Shown in Settings and the camera popover.
    func version() async -> String?
    /// Names of connected supported cameras.
    func connectedCameras() async throws -> [String]
    /// Renders `input` with `recipe` applied over the as-shot settings.
    /// Returns a note for the job when something noteworthy happened (e.g. a fallback).
    func renderImage(input: URL, output: URL, recipe: Recipe, draft: Bool, handle: ProcessHandle?) async throws -> String?
    /// A slot as fujicli-style simulation JSON.
    func readSlot(_ slot: Int) async throws -> Data
    func writeSlot(_ slot: Int, recipe: Recipe) async throws
    func exportBackup(to url: URL) async throws
    func importBackup(from url: URL) async throws
}

/// Which engine the app uses (Settings › Camera engine).
enum EngineChoice: String, CaseIterable, Identifiable {
    case automatic, native, fujicli
    var id: String { rawValue }
    var label: String {
        switch self {
        case .automatic: "Native, with fujicli as fallback"
        case .native: "Native (FujiKit) only"
        case .fujicli: "fujicli only"
        }
    }
}

/// An engine error with a readable message. Recipe-rule errors are the recipe's fault,
/// so they are never retried with another engine.
nonisolated struct EngineError: LocalizedError {
    let message: String
    let isRecipeRule: Bool
    var errorDescription: String? { message }
}

nonisolated extension Error {
    /// The camera refuses a Dynamic Range above the one the RAW was shot with.
    var isDynamicRangeTooHigh: Bool {
        localizedDescription.localizedCaseInsensitiveContains("Dynamic Range cannot exceed")
    }
}

// MARK: - fujicli

nonisolated extension FujiCLI: CameraEngine {
    func renderImage(input: URL, output: URL, recipe: Recipe, draft: Bool, handle: ProcessHandle?) async throws -> String? {
        try await render(input: input, output: output, recipe: recipe, draft: draft, handle: handle)
        return nil
    }
}

// MARK: - Native (FujiKit)

/// Drives the camera directly over USB with FujiKit. Each call opens its own PTP session
/// on a private serial queue, so the camera is free for other tools between operations.
nonisolated final class NativeEngine: CameraEngine, @unchecked Sendable {
    static let shared = NativeEngine()
    private let queue = DispatchQueue(label: "NimbleFuji.FujiKit", qos: .userInitiated)

    func version() async -> String? { "FujiKit (native USB)" }

    func connectedCameras() async throws -> [String] {
        FujiCamera.connected().compactMap(\.model?.name)
    }

    func renderImage(input: URL, output: URL, recipe: Recipe, draft: Bool, handle: ProcessHandle?) async throws -> String? {
        if handle?.isCancelled == true { throw FujiCLIError.cancelled }
        let changes = recipe.cameraSettings()
        try await perform { camera in
            let raf = try Data(contentsOf: input)
            let image = try camera.render(raf: raf, changes: changes, draft: draft)
            try image.write(to: output)
        }
        if handle?.isCancelled == true { throw FujiCLIError.cancelled }
        return nil
    }

    func readSlot(_ slot: Int) async throws -> Data {
        try await perform { camera in
            let encoder = JSONEncoder()
            return try encoder.encode(try camera.readSlot(slot))
        }
    }

    func writeSlot(_ slot: Int, recipe: Recipe) async throws {
        var slotSettings = recipe.forSlot().cameraSettings()
        slotSettings.customSettingName = Recipe.slotName(for: recipe.name)
        slotSettings.exposureOffset = nil
        slotSettings.fileType = nil
        let settings = slotSettings
        try await perform { try $0.writeSlot(slot, settings) }
    }

    func exportBackup(to url: URL) async throws {
        try await perform { try $0.exportBackup().write(to: url) }
    }

    func importBackup(from url: URL) async throws {
        let data = try Data(contentsOf: url)
        try await perform { try $0.importBackup(data) }
    }

    private func perform<T: Sendable>(_ body: @escaping @Sendable (FujiCamera) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let camera = try FujiCamera()
                    continuation.resume(returning: try body(camera))
                } catch {
                    continuation.resume(throwing: Self.translate(error))
                }
            }
        }
    }

    private static func translate(_ error: Error) -> Error {
        let hint = "\n\nConnect the X-T5 with a data cable and set MENU › NETWORK/USB SETTING › CONNECTION MODE to USB RAW CONV./BACKUP RESTORE."
        switch error {
        case let e as FujiKitError:
            switch e {
            case .rule, .unsupportedValue, .invalidSlot:
                return EngineError(message: e.description, isRecipeRule: true)
            default:
                return EngineError(message: e.description, isRecipeRule: false)
            }
        case let e as FujiUSBError:
            switch e {
            case .noCamera, .noImagingInterface:
                return EngineError(message: e.description + hint, isRecipeRule: false)
            default:
                return EngineError(message: e.description, isRecipeRule: false)
            }
        case let e as PTPError:
            return EngineError(message: e.description, isRecipeRule: false)
        case let e as PTPCodecError:
            return EngineError(message: e.description, isRecipeRule: false)
        default:
            return error
        }
    }
}

// MARK: - Native with fujicli fallback

/// Tries FujiKit first; if it fails for a reason other than the recipe itself,
/// retries the same operation with fujicli (when installed).
nonisolated struct FallbackEngine: CameraEngine {
    let primary: NativeEngine
    let fallback: FujiCLI?

    func version() async -> String? {
        let native = await primary.version() ?? "FujiKit"
        guard let fallback, let cli = await fallback.version() else { return native }
        return "\(native), \(cli) as fallback"
    }

    func connectedCameras() async throws -> [String] {
        try await attempt { try await $0.connectedCameras() }.value
    }

    func renderImage(input: URL, output: URL, recipe: Recipe, draft: Bool, handle: ProcessHandle?) async throws -> String? {
        let (note, reason) = try await attempt {
            try await $0.renderImage(input: input, output: output, recipe: recipe, draft: draft, handle: handle)
        }
        if let reason { return "Rendered with fujicli because the native engine failed: \(reason)" }
        return note
    }

    func readSlot(_ slot: Int) async throws -> Data { try await attempt { try await $0.readSlot(slot) }.value }
    func writeSlot(_ slot: Int, recipe: Recipe) async throws { try await attempt { try await $0.writeSlot(slot, recipe: recipe) } }
    func exportBackup(to url: URL) async throws { try await attempt { try await $0.exportBackup(to: url) } }
    func importBackup(from url: URL) async throws { try await attempt { try await $0.importBackup(from: url) } }

    /// Returns the result and, if fujicli had to step in, why.
    @discardableResult
    private func attempt<T: Sendable>(_ operation: @Sendable (any CameraEngine) async throws -> T) async throws -> (value: T, fallbackReason: String?) {
        do {
            return (try await operation(primary), nil)
        } catch let error as EngineError where !error.isRecipeRule {
            guard let fallback else { throw error }
            let reason = error.message.components(separatedBy: "\n").first ?? error.message
            do {
                return (try await operation(fallback), reason)
            } catch {
                throw EngineError(message: "\(error.localizedDescription)\n\n(The native engine also failed: \(reason))", isRecipeRule: false)
            }
        }
    }
}

// MARK: - Recipe → FujiKit settings

nonisolated extension Recipe {
    /// The recipe in FujiKit's (fujicli's) setting names. Unset settings stay unset,
    /// so a render keeps the photo's as-shot values for them.
    func cameraSettings() -> CameraSettings {
        var s = CameraSettings()
        s.fileType = "jpeg"
        s.filmSimulation = filmSimulation?.rawValue
        s.monochromaticColorTemperature = monochromaticColorWarmCool
        s.monochromaticColorTint = monochromaticColorMagentaGreen
        s.grainEffect = grainEffect?.rawValue
        s.colorChromeEffect = colorChromeEffect?.rawValue
        s.colorChromeFxBlue = colorChromeFXBlue?.rawValue
        s.whiteBalance = whiteBalance?.rawValue
        if whiteBalance == .temperature { s.whiteBalanceTemperature = whiteBalanceTemperature }
        s.whiteBalanceShiftRed = whiteBalanceShiftRed
        s.whiteBalanceShiftBlue = whiteBalanceShiftBlue
        s.dynamicRange = dynamicRange?.rawValue
        s.dynamicRangePriority = dynamicRangePriority?.rawValue
        s.highlightTone = highlightTone
        s.shadowTone = shadowTone
        s.color = color
        s.sharpness = sharpness
        s.noiseReduction = noiseReduction
        s.clarity = clarity
        s.smoothSkinEffect = smoothSkinEffect?.rawValue
        s.exposureOffset = exposureOffset
        return s
    }
}
