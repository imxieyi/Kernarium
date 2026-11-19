// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation

/// Settings' "Side keys opacity when idle": how far the closed side keys fade
/// once they have been left alone, kept for the install across launches.
///
/// It is a stored value of its own, so it never rewrites the stored display
/// options (`DisplayOptions`).
public struct SideKeysPreference {
    /// The stored value's key in the defaults database.
    public static let key = "andarium.sideKeysIdleOpacity"

    /// The faintest the closed keys go: out of sight. They still take their
    /// touches where they are (`ClosedKeys` fades what it draws, not the place
    /// it takes touches in).
    public static let minimumIdleOpacity = 0.0
    /// A fresh install's: faded enough to leave the guest in front, still in
    /// sight.
    public static let defaultIdleOpacity = 0.6
    /// The slider's steps.
    public static let idleOpacityStep = 0.1

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The last value kept; 60 percent until one is.
    public var idleOpacity: Double {
        Self.clampedIdleOpacity(defaults.object(forKey: Self.key) as? Double ?? Self.defaultIdleOpacity)
    }

    public func keep(_ opacity: Double) {
        defaults.set(Self.clampedIdleOpacity(opacity), forKey: Self.key)
    }

    /// Between out of sight and fully opaque; a value that is no number is
    /// fully opaque.
    public static func clampedIdleOpacity(_ opacity: Double) -> Double {
        guard opacity.isFinite else { return 1 }
        return min(max(opacity, minimumIdleOpacity), 1)
    }
}
