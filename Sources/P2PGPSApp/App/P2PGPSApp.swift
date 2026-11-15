//
//  P2PGPSApp.swift
//  P2PGPSApp
//
//  P2P GPS — app entry point.
//  Copyright (C) 2026 haruki0420 and contributors
//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  xtool links this SwiftPM library product into an executable; the `@main`
//  attribute here provides the entry point. XcodeGen's app target compiles the
//  same file directly, so both build paths share one entry point.
//
//  The type is named `P2PGPSiOSApp` rather than `P2PGPSApp` on purpose: a type
//  with the same name as its enclosing module (the product/module is
//  `P2PGPSApp`) makes module-qualified references ambiguous.
//

#if canImport(UIKit)
import Foundation
import SwiftUI
#if SWIFT_PACKAGE
import P2PGPSCore
import P2PGPSInjection
#endif

@main
struct P2PGPSiOSApp: App {
    init() {
        LogStore.shared.info("P2P GPS を起動しました")
        // Pick up a pairing file that iloader (or another tool) placed in the
        // app's Documents directory while the app was not running.
        if PairingFileStore.importFromDocumentsIfPresent() {
            LogStore.shared.info("Documents に置かれた pairing file を自動で取り込みました")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(P2PColor.pine)
        }
    }
}
#endif
