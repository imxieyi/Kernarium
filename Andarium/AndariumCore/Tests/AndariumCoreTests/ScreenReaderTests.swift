// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import Testing

@testable import AndariumCore

struct ScreenReaderTests {
    private let talkBack = ScreenReader.services[0]
    private let googleTalkBack = ScreenReader.services[1]
    private let switchAccess = "com.example.switch/.SwitchService"

    // MARK: Reading

    @Test func readsAGuestWithTalkBackOn() throws {
        let output = """
            package:com.android.talkback
            services=\(switchAccess):\(talkBack)
            """
        let state = try #require(ScreenReader.parse(output))
        #expect(state.installedService == talkBack)
        #expect(state.enabledServices == [switchAccess, talkBack])
        #expect(state.isOn)
    }

    @Test func readsAGuestThatNeverHadAService() throws {
        let state = try #require(ScreenReader.parse("services=null\n"))
        #expect(state.installedService == nil)
        #expect(state.enabledServices.isEmpty)
        #expect(!state.isOn && !state.isInstalled)
    }

    @Test func recognisesGooglesTalkBack() throws {
        let state = try #require(ScreenReader.parse("package:com.google.android.marvin.talkback\nservices=\n"))
        #expect(state.installedService == googleTalkBack)
        #expect(!state.isOn)
    }

    @Test func prefersTheSystemBuildWhenBothAreInstalled() throws {
        let output = "package:com.google.android.marvin.talkback\npackage:com.android.talkback\nservices=\(googleTalkBack)"
        let state = try #require(ScreenReader.parse(output))
        #expect(state.installedService == talkBack)
        // The Google build is on, not the one the switch drives.
        #expect(!state.isOn)
    }

    @Test func anotherPackageNamedLikeTalkBackIsNotTalkBack() throws {
        let state = try #require(ScreenReader.parse("package:com.example.talkbackhelper\nservices=null"))
        #expect(!state.isInstalled)
    }

    @Test func outputWithoutTheSettingIsNotAState() {
        #expect(ScreenReader.parse("") == nil)
        #expect(ScreenReader.parse("package:com.android.talkback\n") == nil)
        #expect(ScreenReader.parse(ShellResult(stdout: Data("services=null".utf8), exitCode: 1)) == nil)
        #expect(ScreenReader.parse(ShellResult(stdout: Data("services=null".utf8), exitCode: 0)) != nil)
    }

    @Test func theListIgnoresEmptyEntries() {
        #expect(ScreenReader.serviceList(" null \n") == [])
        #expect(ScreenReader.serviceList("a/.A::b/.B:") == ["a/.A", "b/.B"])
    }

    // MARK: Turning on and off

    @Test func turningOnAddsTalkBackAfterTheOtherServices() throws {
        let state = ScreenReaderState(installedService: talkBack, enabledServices: [switchAccess])
        let command = try #require(ScreenReader.command(turningOn: true, in: state))
        #expect(command == "settings put secure enabled_accessibility_services '\(switchAccess):\(talkBack)' && settings put secure accessibility_enabled 1")
        #expect(ScreenReader.state(afterTurningOn: true, state).enabledServices == [switchAccess, talkBack])
    }

    @Test func turningOnTwiceDoesNotListTalkBackTwice() throws {
        let state = ScreenReaderState(installedService: talkBack, enabledServices: [talkBack])
        let command = try #require(ScreenReader.command(turningOn: true, in: state))
        #expect(command.contains("'\(talkBack)'"))
        #expect(ScreenReader.state(afterTurningOn: true, state).enabledServices == [talkBack])
    }

    @Test func turningOffKeepsTheOtherServicesOn() throws {
        let state = ScreenReaderState(installedService: talkBack, enabledServices: [talkBack, switchAccess])
        let command = try #require(ScreenReader.command(turningOn: false, in: state))
        #expect(command == "settings put secure enabled_accessibility_services '\(switchAccess)' && settings put secure accessibility_enabled 1")
        #expect(!ScreenReader.state(afterTurningOn: false, state).isOn)
    }

    @Test func turningOffTheLastServiceTurnsAccessibilityOff() throws {
        let state = ScreenReaderState(installedService: talkBack, enabledServices: [talkBack, googleTalkBack])
        let command = try #require(ScreenReader.command(turningOn: false, in: state))
        #expect(command == "settings delete secure enabled_accessibility_services >/dev/null; settings put secure accessibility_enabled 0")
        #expect(ScreenReader.state(afterTurningOn: false, state).enabledServices.isEmpty)
    }

    @Test func thereIsNothingToTurnOnWithoutTalkBack() {
        let state = ScreenReaderState(installedService: nil, enabledServices: [])
        #expect(ScreenReader.command(turningOn: true, in: state) == nil)
    }

    @Test func aServiceNameCannotBreakOutOfTheCommand() throws {
        let hostile = "x/.Y';reboot;'"
        let state = ScreenReaderState(installedService: talkBack, enabledServices: [hostile])
        let command = try #require(ScreenReader.command(turningOn: true, in: state))
        #expect(command.contains("'x/.Y'\\'';reboot;'\\''"))
    }

    // MARK: The switch

    @Test func theSwitchOffersWhatTheGuestHas() {
        let off = ScreenReaderState(installedService: talkBack, enabledServices: [])
        let on = ScreenReaderState(installedService: talkBack, enabledServices: [talkBack])
        let none = ScreenReaderState(installedService: nil, enabledServices: [switchAccess])
        #expect(ScreenReaderOffer(state: nil) == .unknown)
        #expect(ScreenReaderOffer(state: on) == .on)
        #expect(ScreenReaderOffer(state: off) == .off)
        #expect(ScreenReaderOffer(state: none) == .unavailable)
    }

    @Test func aFirstStartUnderVoiceOverTurnsTalkBackOn() {
        #expect(ScreenReader.turnsOnByItself(firstStart: true, voiceOverRunning: true, offer: .off))
        // Already on, not in the system, or not known yet: nothing to do.
        #expect(!ScreenReader.turnsOnByItself(firstStart: true, voiceOverRunning: true, offer: .on))
        #expect(!ScreenReader.turnsOnByItself(firstStart: true, voiceOverRunning: true, offer: .unavailable))
        #expect(!ScreenReader.turnsOnByItself(firstStart: true, voiceOverRunning: true, offer: .unknown))
        // Without VoiceOver, or on a later start, the person decides.
        #expect(!ScreenReader.turnsOnByItself(firstStart: true, voiceOverRunning: false, offer: .off))
        #expect(!ScreenReader.turnsOnByItself(firstStart: false, voiceOverRunning: true, offer: .off))
    }

    @Test func onlyAKnownStateCanBeChanged() {
        #expect(ScreenReaderOffer.on.canChange && ScreenReaderOffer.off.canChange)
        #expect(!ScreenReaderOffer.unknown.canChange && !ScreenReaderOffer.unavailable.canChange)
        #expect(ScreenReaderOffer.on.isOn && !ScreenReaderOffer.off.isOn)
        #expect(ScreenReaderOffer.on.detail == nil && ScreenReaderOffer.unavailable.detail != nil)
    }
}
