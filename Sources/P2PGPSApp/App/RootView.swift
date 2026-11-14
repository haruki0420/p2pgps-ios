//
//  RootView.swift
//  P2PGPSApp
//
//  P2P GPS — root navigation and long-lived controllers.
//  Copyright (C) 2026 haruki0420 and contributors
//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  One `NavigationStack` for the whole app (DESIGN.md "Layout"). The Receiver
//  and Sender controllers live here so switching screens never drops a BLE
//  connection or a streaming session.
//

#if canImport(UIKit)
import SwiftUI
#if SWIFT_PACKAGE
import P2PGPSCore
#endif

struct RootView: View {
    @StateObject private var receiver = ReceiverController()
    @StateObject private var sender = SenderController()

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            HomeView(receiver: receiver, sender: sender)
        }
        .tint(P2PColor.pine)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                sender.refreshAuthorization()
            }
        }
    }
}
#endif
