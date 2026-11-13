// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation

/// TalkBack, Android's screen reader, in the guest. Andarium turns it on and
/// off over adb the way Android's own Accessibility page does: the service
/// joins or leaves the secure setting `enabled_accessibility_services`, and
/// `accessibility_enabled` follows whether any service is left. Every other
/// service the guest has turned on stays as it is. The system image carries
/// TalkBack and its voice; a guest whose system has none offers no switch.
public enum ScreenReader {
    /// The TalkBack builds Andarium recognises, by their service: the
    /// open-source build the system image carries, then Google's own.
    public static let services = [
        "com.android.talkback/com.google.android.marvin.talkback.TalkBackService",
        "com.google.android.marvin.talkback/com.google.android.marvin.talkback.TalkBackService",
    ]

    /// What to run in the guest's shell to read the state; `parse` reads its
    /// output. `pm list packages` filters by substring and prints
    /// `package:<name>` lines.
    public static let stateCommand =
        "pm list packages talkback; echo \"services=$(settings get secure enabled_accessibility_services)\""

    /// The state from the output of `stateCommand`; nil when the output is
    /// not what the command prints.
    public static func parse(_ output: String) -> ScreenReaderState? {
        var packages = Set<String>()
        var enabled: [String]?
        for raw in output.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("package:") {
                packages.insert(String(line.dropFirst("package:".count)))
            } else if line.hasPrefix("services=") {
                enabled = serviceList(String(line.dropFirst("services=".count)))
            }
        }
        guard let enabled else { return nil }
        let installed = services.first { packages.contains(package(of: $0)) }
        return ScreenReaderState(installedService: installed, enabledServices: enabled)
    }

    /// The state from a finished `stateCommand`: nil when it failed.
    public static func parse(_ result: ShellResult) -> ScreenReaderState? {
        guard result.exitCode == 0 else { return nil }
        return parse(result.text)
    }

    /// The services in the setting's value: colon-separated components, or
    /// `null` when the setting was never written.
    public static func serviceList(_ value: String) -> [String] {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != "null" else { return [] }
        return trimmed.split(separator: ":").map(String.init).filter { !$0.isEmpty }
    }

    /// The command that turns TalkBack on or off in `state`: it writes the
    /// whole list back, with `service` added at its end or every known
    /// TalkBack removed. Nil when the guest has no TalkBack to turn on.
    public static func command(turningOn on: Bool, in state: ScreenReaderState) -> String? {
        var list = state.enabledServices.filter { !services.contains($0) }
        if on {
            guard let service = state.installedService else { return nil }
            list.append(service)
        }
        guard !list.isEmpty else {
            return "settings delete secure enabled_accessibility_services >/dev/null; "
                + "settings put secure accessibility_enabled 0"
        }
        return "settings put secure enabled_accessibility_services \(shellQuoted(list.joined(separator: ":"))) && "
            + "settings put secure accessibility_enabled 1"
    }

    /// Opens Android's Accessibility page, where TalkBack's own settings and
    /// the other services are.
    public static let settingsCommand = "am start -a android.settings.ACCESSIBILITY_SETTINGS >/dev/null"

    /// Whether Andarium turns TalkBack on without being asked: at the first
    /// start of a guest while VoiceOver runs, so that Android's setup speaks
    /// from its first page, when the system has TalkBack and it is off. Later
    /// starts leave TalkBack as the person left it.
    public static func turnsOnByItself(firstStart: Bool, voiceOverRunning: Bool, offer: ScreenReaderOffer) -> Bool {
        firstStart && voiceOverRunning && offer == .off
    }

    /// The state `command(turningOn:in:)` leaves.
    public static func state(afterTurningOn on: Bool, _ state: ScreenReaderState) -> ScreenReaderState {
        var after = state
        after.enabledServices.removeAll { services.contains($0) }
        if on, let service = state.installedService { after.enabledServices.append(service) }
        return after
    }

    static func package(of service: String) -> String {
        String(service.prefix { $0 != "/" })
    }

    static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// TalkBack in the guest as Android last reported it.
public struct ScreenReaderState: Equatable, Sendable {
    /// The service of the TalkBack the guest has, from `ScreenReader.services`;
    /// nil when it has none.
    public var installedService: String?
    /// Every accessibility service the guest has turned on, in its order.
    public var enabledServices: [String]

    public init(installedService: String?, enabledServices: [String]) {
        self.installedService = installedService
        self.enabledServices = enabledServices
    }

    /// TalkBack is installed and on.
    public var isOn: Bool {
        guard let installedService else { return false }
        return enabledServices.contains(installedService)
    }

    public var isInstalled: Bool { installedService != nil }
}

/// What the TalkBack switch of the session's Settings offers.
public enum ScreenReaderOffer: Equatable, Sendable {
    /// Not read yet, or the guest cannot be asked now.
    case unknown
    case on
    case off
    /// The guest's system has no TalkBack.
    case unavailable

    public init(state: ScreenReaderState?) {
        guard let state else {
            self = .unknown
            return
        }
        if state.isInstalled {
            self = state.isOn ? .on : .off
        } else {
            self = .unavailable
        }
    }

    /// Whether the switch shows TalkBack on.
    public var isOn: Bool { self == .on }

    /// Whether the switch can be used.
    public var canChange: Bool {
        switch self {
        case .on, .off: true
        case .unknown, .unavailable: false
        }
    }

    /// The words under TalkBack's switch; nil when on and off say it all.
    public var detail: String? {
        switch self {
        case .unknown: "Checking\u{2026}"
        case .unavailable: "Not in this system image"
        case .on, .off: nil
        }
    }
}
