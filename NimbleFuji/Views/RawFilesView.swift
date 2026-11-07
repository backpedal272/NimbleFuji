import QuickLook
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

struct RawFilesView: View {
    @Environment(AppModel.self) private var model
    @State private var importing = false
    @State private var isDropTargeted = false
    @State private var sortOrder = [KeyPathComparator(\RawFile.name)]
    /// File shown in the Quick Look panel (Space bar).
    @State private var previewURL: URL?

    private static let rafType = UTType(filenameExtension: "raf") ?? .rawImage

    var body: some View {
        @Bindable var model = model
        Table(sortedFiles, selection: $model.selectedRawIDs, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { file in
                HStack(spacing: 8) {
                    RawThumbnail(url: file.url)
                    Text(file.name)
                }
            }
            .width(min: 180, ideal: 240)
            TableColumn("Date", value: \.sortDate) { file in
                Text(file.modified?.formatted(date: .abbreviated, time: .shortened) ?? "—")
                    .foregroundStyle(.secondary)
            }
            .width(min: 120, ideal: 150)
            TableColumn("Size", value: \.byteCount) { file in
                Text(file.byteCount.formatted(.byteCount(style: .file)))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .width(min: 60, ideal: 80)
            TableColumn("Folder", value: \.folder) { file in
                Text(file.folder)
                    .foregroundStyle(.secondary)
                    .truncationMode(.head)
                    .lineLimit(1)
            }
        }
        .contextMenu(forSelectionType: RawFile.ID.self) { ids in
            if !ids.isEmpty {
                Button("Quick Look") { preview(ids) }
                Button("Show in Finder") { model.reveal(Array(ids)) }
                Button("Remove from List") {
                    model.library.remove(ids)
                    model.selectedRawIDs.subtract(ids)
                }
            }
        } primaryAction: { ids in
            for url in ids { NSWorkspace.shared.open(url) }
        }
        .onKeyPress(.space) {
            guard previewURL == nil, !model.selectedRawIDs.isEmpty else { return .ignored }
            preview(model.selectedRawIDs)
            return .handled
        }
        // Arrow keys in the panel step through the selected files, or all files if one is selected.
        .quickLookPreview($previewURL, in: previewItems)
        .onDeleteCommand {
            model.library.remove(model.selectedRawIDs)
            model.selectedRawIDs = []
        }
        .overlay {
            if model.library.files.isEmpty {
                ContentUnavailableView {
                    Label("No RAW Files", systemImage: "photo.stack")
                } description: {
                    Text("Drop Fujifilm RAF files or folders here.")
                } actions: {
                    Button("Add RAW Files…") { importing = true }
                }
            }
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            add(urls)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [Self.rafType, .folder],
                      allowsMultipleSelection: true) { result in
            if case let .success(urls) = result { add(urls) }
        }
        .navigationTitle("RAW Files")
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { importing = true } label: {
                    Label("Add RAW Files", systemImage: "plus")
                }
                .help("Add RAF files or folders")
                Button {
                    model.library.remove(model.selectedRawIDs)
                    model.selectedRawIDs = []
                } label: {
                    Label("Remove", systemImage: "minus")
                }
                .help("Remove the selected files from the list")
                .disabled(model.selectedRawIDs.isEmpty)
            }
        }
    }

    /// The selected files in list order, or every file when only one is selected.
    private var previewItems: [URL] {
        let selected = sortedFiles.filter { model.selectedRawIDs.contains($0.id) }
        return (selected.count > 1 ? selected : sortedFiles).map(\.url)
    }

    private func preview(_ ids: Set<RawFile.ID>) {
        previewURL = sortedFiles.first { ids.contains($0.id) }?.url
    }

    private var sortedFiles: [RawFile] {
        model.library.files.sorted(using: sortOrder)
    }

    private var subtitle: String {
        let total = model.library.files.count
        guard total > 0 else { return "" }
        return "\(model.selectedRawIDs.count) of \(total) selected"
    }

    private func add(_ urls: [URL]) {
        let before = Set(model.library.files.map(\.id))
        model.library.add(urls)
        let added = Set(model.library.files.map(\.id)).subtracting(before)
        // Newly added files are selected so they're ready to render.
        model.selectedRawIDs.formUnion(added)
    }
}

private extension RawFile {
    var sortDate: Date { modified ?? .distantPast }
}

/// Small Quick Look thumbnail of a RAF (macOS decodes Fujifilm RAW natively).
private struct RawThumbnail: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "photo").foregroundStyle(.tertiary)
            }
        }
        .frame(width: 36, height: 24)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .task(id: url) {
            let request = QLThumbnailGenerator.Request(
                fileAt: url, size: CGSize(width: 72, height: 48),
                scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
            if let thumbnail = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
                image = thumbnail.nsImage
            }
        }
    }
}
