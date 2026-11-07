// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// Carries settings over from the app's first bundle identifier (com.alain.NimbleFuji)
/// to pm.ad0.NimbleFuji. Runs once; existing values in the new domain are never overwritten.
enum LegacyDefaults {
    static let oldDomain = "com.alain.NimbleFuji"
    static let migratedKey = "migratedFromComAlainNimbleFuji"

    /// Returns the number of settings copied.
    @discardableResult
    static func migrate(into defaults: UserDefaults = .standard, from domain: String = oldDomain) -> Int {
        guard !defaults.bool(forKey: migratedKey) else { return 0 }
        defer { defaults.set(true, forKey: migratedKey) }
        guard let old = defaults.persistentDomain(forName: domain), !old.isEmpty else { return 0 }
        var copied = 0
        for (key, value) in old where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
            copied += 1
        }
        return copied
    }
}
