import SwiftUI

struct RenderProgressView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let renderer = model.renderer
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(renderer.isRunning ? "Rendering on Camera" : "Batch Finished")
                    .font(.title2.bold())
                Spacer()
                Text("\(renderer.finishedCount) of \(renderer.jobs.count)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            ProgressView(value: renderer.progress)
            if let current = renderer.currentJob {
                Text("\(current.raw.name) with \(current.recipe.name)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if !renderer.isRunning {
                Text(resultSummary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            List(renderer.jobs) { job in
                JobRow(job: job)
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .frame(minHeight: 260)

            HStack {
                if let folder = renderer.outputFolder {
                    Button("Show in Finder") {
                        let outputs = renderer.jobs.compactMap { job -> URL? in
                            if case let .done(url, _) = job.status { url } else { nil }
                        }
                        model.reveal(outputs.isEmpty ? [folder] : outputs)
                    }
                }
                Spacer()
                if renderer.isRunning {
                    Button("Cancel", role: .cancel) { renderer.cancel() }
                        .keyboardShortcut(.cancelAction)
                } else {
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 620)
        .interactiveDismissDisabled(renderer.isRunning)
    }

    private var resultSummary: String {
        let r = model.renderer
        var parts = ["\(r.succeededCount) rendered"]
        if r.failedCount > 0 { parts.append("\(r.failedCount) failed") }
        let cancelled = r.jobs.count - r.succeededCount - r.failedCount
        if cancelled > 0 { parts.append("\(cancelled) cancelled") }
        if let start = r.startedAt, let end = r.finishedAt {
            parts.append(Duration.seconds(end.timeIntervalSince(start)).formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated)))
        }
        return parts.joined(separator: " · ")
    }
}

private struct JobRow: View {
    let job: BatchRenderer.Job

    var body: some View {
        HStack(spacing: 10) {
            icon.frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(job.raw.name) → \(job.recipe.name)")
                    .lineLimit(1)
                if case let .failed(message) = job.status {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .lineLimit(4)
                } else if case let .done(url, seconds) = job.status {
                    Text("\(url.lastPathComponent) · \(seconds.formatted(.number.precision(.fractionLength(1))))s")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let note = job.note {
                    Label(note, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            if case let .done(url, _) = job.status {
                Button("Open") { NSWorkspace.shared.open(url) }
                    .buttonStyle(.link)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var icon: some View {
        switch job.status {
        case .pending:
            Image(systemName: "circle").foregroundStyle(.tertiary)
        case .running:
            ProgressView().controlSize(.small)
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
        case .cancelled:
            Image(systemName: "minus.circle").foregroundStyle(.secondary)
        }
    }
}
