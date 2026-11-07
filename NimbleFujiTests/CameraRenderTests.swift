import Foundation
import Testing
@testable import Nimble_Fuji

/// Renders on a real camera. Runs only when NIMBLE_FUJI_TEST_RAF points at a RAF file:
///   TEST_RUNNER_NIMBLE_FUJI_TEST_RAF=/path/to/DSCF0001.RAF xcodebuild test …
@MainActor
struct CameraRenderTests {
    nonisolated static let rafPath = ProcessInfo.processInfo.environment["NIMBLE_FUJI_TEST_RAF"]

    @Test(.enabled(if: rafPath != nil), .timeLimit(.minutes(2)))
    func rendersBatchOnCamera() async throws {
        let cli = try #require(FujiCLI.locate(preferredPath: nil))
        let path = try #require(Self.rafPath)
        let raw = try #require(RawFile(url: URL(filePath: path)))
        let output = FileManager.default.temporaryDirectory.appending(path: "NimbleFujiCamera-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: output) }

        let recipes = try SampleRecipes.yaml.map(Recipe.fromYAML)
        let renderer = BatchRenderer()
        renderer.start(raws: [raw], recipes: recipes, outputFolder: output, cli: cli, draft: false, overwrite: false)
        while renderer.isRunning { try await Task.sleep(for: .milliseconds(200)) }

        for job in renderer.jobs {
            guard case let .done(url, seconds) = job.status else {
                Issue.record("\(job.recipe.name): \(job.status)")
                continue
            }
            let size = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))[.size] as? Int ?? 0
            print("✓ \(url.lastPathComponent) \(size / 1_000_000) MB in \(String(format: "%.1f", seconds))s \(job.note ?? "")")
            #expect(size > 1_000_000)
        }
    }
}
