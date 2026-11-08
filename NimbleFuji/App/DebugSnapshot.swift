// SPDX-License-Identifier: GPL-3.0-only

#if DEBUG
import AppKit

/// Debug builds only: when NIMBLE_FUJI_SNAPSHOT is set to a file path, the main window
/// renders itself to that PNG a few seconds after launch (no screen-recording permission needed).
enum DebugSnapshot {
    static func scheduleIfRequested() {
        guard let path = ProcessInfo.processInfo.environment["NIMBLE_FUJI_SNAPSHOT"] else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
                  let view = window.contentView?.superview ?? window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(filePath: path))
        }
    }
}
#endif
