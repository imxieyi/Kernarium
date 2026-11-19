// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import Testing
@testable import AndariumCore

struct SideKeysPreferenceTests {
    private func defaults() -> UserDefaults {
        let name = "SideKeysPreferenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func aFreshInstallFadesTheKeysToSixtyPercent() {
        #expect(SideKeysPreference(defaults: defaults()).idleOpacity == 0.6)
    }

    @Test func whatThePersonSetsIsKept() {
        let store = defaults()
        SideKeysPreference(defaults: store).keep(0.4)
        #expect(SideKeysPreference(defaults: store).idleOpacity == 0.4)
    }

    @Test func theKeysFadeAsFarAsOutOfSightAndNeverAboveOpaque() {
        let store = defaults()
        let preference = SideKeysPreference(defaults: store)
        preference.keep(0)
        #expect(preference.idleOpacity == 0)
        preference.keep(-1)
        #expect(preference.idleOpacity == 0)
        preference.keep(3)
        #expect(preference.idleOpacity == 1)
        #expect(SideKeysPreference.clampedIdleOpacity(.nan) == 1)
        store.set(-0.5, forKey: SideKeysPreference.key)
        #expect(preference.idleOpacity == 0)
    }
}
