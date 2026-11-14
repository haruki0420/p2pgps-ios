//
//  HomeView.swift
//  P2PGPSApp
//
//  P2P GPS — role selection.
//  Copyright (C) 2026 haruki0420 and contributors
//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  DESIGN.md "Home": two large rows separated by hairlines, not cards, no icon
//  tiles. Settings and Diagnostics are reachable from here as well as from the
//  role screens.
//

#if canImport(UIKit)
import SwiftUI
#if SWIFT_PACKAGE
import P2PGPSCore
import P2PGPSBLE
#endif

struct HomeView: View {
    @ObservedObject var receiver: ReceiverController
    @ObservedObject var sender: SenderController

    @State private var isShowingSettings = false
    @State private var isShowingDiagnostics = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("iPhone の位置を BLE で iPad に届け、iPad の位置として反映します。")
                    .font(P2PFont.label)
                    .foregroundStyle(P2PColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 24)

                VStack(spacing: 0) {
                    NavigationLink {
                        ReceiverView(controller: receiver)
                    } label: {
                        RoleRow(role: .receiver)
                    }
                    .buttonStyle(.plain)

                    Rectangle()
                        .fill(P2PColor.line)
                        .frame(height: P2PSpacing.hairline)

                    NavigationLink {
                        SenderView(controller: sender)
                    } label: {
                        RoleRow(role: .sender)
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 24) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Label("設定", systemImage: "gearshape")
                            .font(P2PFont.label)
                            .foregroundStyle(P2PColor.ink)
                            .frame(minHeight: P2PSpacing.minimumTapTarget)
                    }
                    .buttonStyle(.plain)

                    Button {
                        isShowingDiagnostics = true
                    } label: {
                        Label("診断", systemImage: "waveform.path.ecg")
                            .font(P2PFont.label)
                            .foregroundStyle(P2PColor.ink)
                            .frame(minHeight: P2PSpacing.minimumTapTarget)
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
                .padding(.top, 28)

                Text("v1.0.0 · AGPL-3.0 · 座標は端末外に送りません")
                    .font(P2PFont.caption)
                    .foregroundStyle(P2PColor.inkSecondary)
                    .padding(.top, 8)
            }
            .padding(P2PSpacing.gutter)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(P2PColor.paper.ignoresSafeArea())
        .navigationTitle("P2P GPS")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $isShowingDiagnostics) {
            DiagnosticsView(
                central: receiver.central,
                engine: receiver.engine,
                senderPeripheral: sender.peripheral
            )
        }
    }
}
#endif
