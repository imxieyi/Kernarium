// SPDX-License-Identifier: GPL-2.0-or-later

import AndariumCore
import SwiftUI

/// The guest's display, kept under the boot and the run so it is one view
/// from the first frame to the last. The runtime draws into it; the boot
/// screen covers it until the guest has something to show.
struct GuestLayer: View {
    @Environment(AppModel.self) private var model
    /// Whether the window scene fills the screen. Until the view is in a
    /// scene, it is taken to be a window, which is the system's own default.
    @State private var coversScreen = false

    var body: some View {
        if showsGuest {
            ZStack {
                Color.black.ignoresSafeArea()
                GuestDisplayView(
                    keyboardVisible: .constant(false), retinaMode: model.retina,
                    accessibility: accessibility,
                    // A touch beside the side keys reaches the guest, and
                    // puts the keys away.
                    touchDidBegin: { model.session.closeSideKeys() }
                ) { view, geometry in
                    (model.driver as? LiveRuntime)?.viewDidLayout(view, geometry)
                }
                // In a window, iPadOS draws its window controls over the
                // top-left corner of the content, which would cover the
                // guest's status bar; the system knows where they are. A
                // scene that covers the screen has none.
                .containerCornerOffset(SceneCoverage.cornerOffsetEdges(coversScreen: coversScreen), sizeToFit: true)
            }
            .background {
                SceneCoverageReader { coversScreen = $0 }
            }
        }
    }

    /// Android's screen for VoiceOver while the session shows it; the boot
    /// screen covers it before. Touches go straight through while TalkBack
    /// is on, which then speaks instead of VoiceOver.
    private var accessibility: GuestDisplayAccessibility? {
        guard case .running = model.phase else { return nil }
        let talkBack = model.screenReaderOffer.isOn
        return GuestDisplayAccessibility(
            label: ScreenReaderWords.displayLabel,
            hint: talkBack ? ScreenReaderWords.displayHintDirect
                : (model.offersScreenReader ? ScreenReaderWords.displayHint : nil),
            directTouch: talkBack)
    }

    private var showsGuest: Bool {
        switch model.phase {
        case .booting, .running: true
        case .home, .failed: false
        }
    }
}
