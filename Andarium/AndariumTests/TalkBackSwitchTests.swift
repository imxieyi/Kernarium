// SPDX-License-Identifier: GPL-2.0-or-later
import AndariumCore
import Foundation
import Testing
@testable import Andarium

/// The TalkBack switch of the session's Settings: it shows what Android
/// reports, turns TalkBack on and off through the driver, is unavailable where
/// the system has no TalkBack and absent from Recovery; and a guest's first
/// start under VoiceOver turns TalkBack on by itself, once.
@MainActor
struct TalkBackSwitchTests {
    private let host = HostDevice(
        name: "iPad", processorCount: 6, memory: MemoryPolicy(maximumsMiB: [4096]), freeStorageBytes: 40_000_000_000
    )
    private let system = SystemInfo(
        version: "17", release: "r2", kernel: "Linux 6.18", architecture: "arm64, 4 KiB pages", appVersion: "1")
    private let talkBack = ScreenReader.services[0]

    /// A guest that ran `plan`'s start to its end, with VoiceOver as given.
    private func started(
        plan: StartPlan = .normal, voiceOver: Bool = false, mode: StartMode = .normal,
        talkBack state: ScreenReaderState? = nil
    ) -> (AppModel, StubDriver) {
        let model = AppModel(
            guest: Guest.fresh(on: host), host: host, system: system, capabilities: .device, createRequirementBytes: 1)
        let driver = StubDriver(plan: plan)
        if let state { driver.screenReaderState = state }
        model.driver = driver
        model.voiceOverRunning = { voiceOver }
        model.refreshPlan()
        model.start(mode)
        model.finishBoot(model.bootKind(mode))
        return (model, driver)
    }

    /// Waits, within a bound, until `done` holds.
    private func settle(_ done: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !done(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func theSwitchShowsWhatAndroidReports() async throws {
        let (model, driver) = started()
        try await settle { model.session.screenReader != nil }
        #expect(model.screenReaderOffer == .off)
        // A change made in Android's own settings reaches the switch.
        driver.screenReaderState = ScreenReaderState(installedService: talkBack, enabledServices: [talkBack])
        await model.refreshScreenReader()
        #expect(model.screenReaderOffer == .on)
        // A reading that fails keeps the last one.
        driver.screenReaderState = nil
        await model.refreshScreenReader()
        #expect(model.screenReaderOffer == .on)
    }

    @Test func theSwitchTurnsTalkBackOnAndOff() async throws {
        let (model, driver) = started()
        try await settle { model.session.screenReader != nil }
        model.setScreenReader(true)
        try await settle { !model.session.screenReaderChanging && model.screenReaderOffer == .on }
        #expect(driver.screenReaderChanges == [true])
        // Asking for the state it is in already changes nothing.
        model.setScreenReader(true)
        #expect(driver.screenReaderChanges == [true])
        model.setScreenReader(false)
        try await settle { !model.session.screenReaderChanging && model.screenReaderOffer == .off }
        #expect(driver.screenReaderChanges == [true, false])
        #expect(model.alert == nil)
    }

    @Test func aSystemWithoutTalkBackOffersNoSwitchToTurn() async throws {
        let (model, driver) = started(talkBack: ScreenReaderState(installedService: nil, enabledServices: []))
        try await settle { model.session.screenReader != nil }
        #expect(model.screenReaderOffer == .unavailable)
        #expect(!model.screenReaderOffer.canChange)
        model.setScreenReader(true)
        try await Task.sleep(for: .milliseconds(50))
        #expect(driver.screenReaderChanges.isEmpty)
    }

    @Test func recoveryHasNoTalkBack() async throws {
        let (model, driver) = started(voiceOver: true, mode: .recovery)
        #expect(!model.offersScreenReader)
        await model.refreshScreenReader()
        model.setScreenReader(true)
        try await Task.sleep(for: .milliseconds(50))
        #expect(driver.screenReaderReads == 0 && driver.screenReaderChanges.isEmpty)
    }

    @Test func aChangeThatFailsSaysSo() async throws {
        let (model, driver) = started()
        try await settle { model.session.screenReader != nil }
        driver.screenReaderError = AdbFailure(message: "The guest couldn\u{2019}t change TalkBack.")
        model.setScreenReader(true)
        try await settle { model.alert != nil }
        #expect(model.alert?.title == ScreenReaderWords.changeFailure(turningOn: true))
        #expect(model.screenReaderOffer == .off)
        #expect(!model.session.screenReaderChanging)
    }

    @Test func settingsReadsTalkBackWhileItIsOpen() async throws {
        let (model, driver) = started()
        try await settle { model.session.screenReader != nil }
        let reads = driver.screenReaderReads
        let watcher = Task { await model.watchSettings() }
        defer { watcher.cancel() }
        try await settle { driver.screenReaderReads > reads }
        #expect(driver.screenReaderReads > reads)
    }

    @Test func aFirstStartUnderVoiceOverTurnsTalkBackOn() async throws {
        let (model, driver) = started(plan: .firstStart, voiceOver: true)
        try await settle { driver.screenReaderChanges == [true] && model.screenReaderOffer == .on }
        #expect(driver.screenReaderChanges == [true])
        #expect(model.screenReaderOffer == .on)
    }

    @Test func aFirstStartWithoutVoiceOverLeavesTalkBackOff() async throws {
        let (model, driver) = started(plan: .firstStart, voiceOver: false)
        try await settle { model.session.screenReader != nil }
        try await Task.sleep(for: .milliseconds(50))
        #expect(driver.screenReaderChanges.isEmpty)
        #expect(model.screenReaderOffer == .off)
    }

    @Test func aLaterStartLeavesTalkBackAsThePersonLeftIt() async throws {
        let (model, driver) = started(plan: .normal, voiceOver: true)
        try await settle { model.session.screenReader != nil }
        try await Task.sleep(for: .milliseconds(50))
        #expect(driver.screenReaderChanges.isEmpty)
        #expect(model.screenReaderOffer == .off)
    }
}
