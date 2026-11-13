// SPDX-License-Identifier: GPL-2.0-or-later

import UIKit

/// What Andarium tells VoiceOver of its own accord: a new screen, an operation
/// that began or ended, TalkBack turning on or off. Each call does nothing
/// while VoiceOver is off.
enum VoiceOver {
    /// Speaks `text`. A queued announcement waits for what VoiceOver is
    /// saying; otherwise it interrupts it.
    static func announce(_ text: String, queued: Bool = false) {
        guard UIAccessibility.isVoiceOverRunning else { return }
        let words = NSAttributedString(
            string: text, attributes: [.accessibilitySpeechQueueAnnouncement: queued])
        UIAccessibility.post(notification: .announcement, argument: words)
    }

    /// The screen changed as a whole: VoiceOver moves to its first element,
    /// and says `text` instead when it is given.
    static func screenChanged(_ text: String? = nil) {
        guard UIAccessibility.isVoiceOverRunning else { return }
        UIAccessibility.post(notification: .screenChanged, argument: text)
    }
}

/// The words of TalkBack in the session's Settings and on the guest's display.
nonisolated enum ScreenReaderWords {
    static let section = "Accessibility"
    static let name = "TalkBack"
    static let settings = "Accessibility settings"
    static let footer = "TalkBack, Android\u{2019}s screen reader, speaks what you touch. While it is on, touches reach Android with VoiceOver on too."
    static let footerUnavailable = "This system image has no TalkBack."
    static let turningOnForVoiceOver = "VoiceOver is on, so Andarium is turning on TalkBack, Android\u{2019}s screen reader."
    static let missing = "Android has no TalkBack to turn on."

    static func changeFailure(turningOn on: Bool) -> String {
        on ? "TalkBack didn\u{2019}t turn on" : "TalkBack didn\u{2019}t turn off"
    }

    static func announcement(on: Bool) -> String { on ? "TalkBack on" : "TalkBack off" }

    /// What VoiceOver calls Android's screen, and what it says of it.
    static let displayLabel = "Android screen"
    static let displayHintDirect = "TalkBack is on. Touches go straight to Android, and TalkBack speaks."
    static let displayHint = "Turn on TalkBack in Settings, under the side keys, to use Android with a screen reader."
}
