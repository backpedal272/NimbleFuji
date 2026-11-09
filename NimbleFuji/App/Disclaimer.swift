// SPDX-License-Identifier: GPL-3.0-only

import AppKit

/// First-launch warning about the reverse-engineered camera protocol.
/// Nothing talks to the camera until the user accepts it. Bump `version`
/// when the text changes materially so everyone sees it again.
enum Disclaimer {
    static let version = 1
    static let acceptedKey = "acceptedDisclaimerVersion"

    static var isAccepted: Bool {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return true }
        return UserDefaults.standard.integer(forKey: acceptedKey) >= version
    }

    /// Shows the warning (as a sheet on `window`, if given) unless it was already accepted.
    /// Calls `onAccept` once the user goes on; quits the app when they choose Quit,
    /// which is the default button.
    static func confirmOrQuit(in window: NSWindow?, onAccept: @escaping () -> Void) {
        guard !isAccepted else { onAccept(); return }

        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Use at your own risk"
        alert.informativeText = """
        Nimble Fuji talks to your camera over USB using a protocol that Fujifilm has never \
        documented. Everything it knows about that protocol was worked out by reverse \
        engineering, and some of it is guesswork.

        Sending the camera commands it doesn't expect can change settings you didn't mean \
        to change, corrupt its custom settings or memory card, crash its firmware, or leave \
        it permanently unusable ("bricked"). Such damage may not be covered by your warranty.

        This program is an unofficial hobby project, provided for illustration and \
        educational purposes only. It is not affiliated with, endorsed by or supported by \
        FUJIFILM Corporation. It comes with ABSOLUTELY NO WARRANTY, to the extent permitted \
        by law (see the GNU GPL v3). The authors accept no liability for any damage to your \
        camera, your files or anything else.

        If you are not willing to accept these risks, quit now and do not connect your camera.
        """

        // The first button is the default (Return); make that the safe choice.
        let quit = alert.addButton(withTitle: "Quit")
        quit.keyEquivalent = "\r"
        let accept = alert.addButton(withTitle: "I Understand the Risks")
        accept.keyEquivalent = ""

        let finish: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .alertSecondButtonReturn else {
                NSApp.terminate(nil)
                return
            }
            UserDefaults.standard.set(version, forKey: acceptedKey)
            onAccept()
        }

        NSApp.activate()
        if let window {
            window.makeKeyAndOrderFront(nil)
            alert.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(alert.runModal())
        }
    }
}
