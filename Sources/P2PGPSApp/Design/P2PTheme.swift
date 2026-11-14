//
//  P2PTheme.swift
//  P2PGPSApp
//
//  P2P GPS — design tokens for the "測量標（benchmark）" visual world.
//  Copyright (C) 2026 haruki0420 and contributors
//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  The authoritative design document is the repository-root `DESIGN.md`
//  (DESIGN.md). This file is the iOS implementation of its color, type and
//  spacing tokens. Rules that matter:
//
//    * No gradients, no shadows, no glass. Hierarchy comes from `line` hairlines
//      and the `paper` / `surface` difference.
//    * No default blue tint: the brand color is `pine`.
//    * Numbers are monospaced / tabular; coordinates are the largest numerals
//      on screen.
//    * Every state is icon + text + shape, never color alone.
//
//  Tokens are defined in code (not an Asset Catalog) because xtool packages a
//  SwiftPM library product, where asset catalogs would need extra resource
//  plumbing.
//

#if canImport(UIKit)
import Foundation
import SwiftUI
import UIKit

// MARK: - Colors

/// Semantic color tokens, light and dark (DESIGN.md "Color tokens").
enum P2PColor {
    static let paper = Color(p2pLight: 0xF2F4F2, p2pDark: 0x0F1A1E)
    static let surface = Color(p2pLight: 0xFBFCFB, p2pDark: 0x16252A)
    static let ink = Color(p2pLight: 0x17252A, p2pDark: 0xE8EEEC)
    static let inkSecondary = Color(p2pLight: 0x55666A, p2pDark: 0x9FB0B2)
    static let line = Color(p2pLight: 0xC9D3CE, p2pDark: 0x2A3B40)
    static let pine = Color(p2pLight: 0x1E6B5A, p2pDark: 0x6FBFA8)
    static let live = Color(p2pLight: 0xA8502E, p2pDark: 0xE08A5F)
    static let liveFill = Color(p2pLight: 0xB85C38, p2pDark: 0xC96A42)
    static let amber = Color(p2pLight: 0x8A5A12, p2pDark: 0xE0B25C)
    static let danger = Color(p2pLight: 0xA32E24, p2pDark: 0xE0705F)

    /// Foreground on a `pine` fill (primary actions). `paper` gives
    /// 5.75:1 (Light) / 8.17:1 (Dark), both above WCAG AA 4.5:1.
    static let onPrimary = P2PColor.paper

    /// Foreground on a `liveFill` fill (injection toggle ON). `paper` is only
    /// 4.11:1 on the Light `liveFill`, so Light uses white (4.54:1) and Dark
    /// keeps `paper` (4.74:1). Never hard-code `Color.white` on `pine` — the
    /// Dark `pine` is light and white would drop to 2.17:1.
    static let onLiveFill = Color(p2pLight: 0xFFFFFF, p2pDark: 0x0F1A1E)
}

extension Color {
    /// A color that resolves per interface style without an Asset Catalog.
    init(p2pLight: UInt32, p2pDark: UInt32) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? p2pDark : p2pLight
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255.0,
                green: CGFloat((hex >> 8) & 0xFF) / 255.0,
                blue: CGFloat(hex & 0xFF) / 255.0,
                alpha: 1.0
            )
        })
    }
}

// MARK: - Typography

/// Type ramp (DESIGN.md "Typography"). System fonts only, Dynamic Type aware.
enum P2PFont {
    /// Screen title: `.title2` semibold.
    static let screenTitle = Font.system(.title2, design: .default).weight(.semibold)
    /// Role-row title on Home.
    static let rowTitle = Font.system(.title3, design: .default).weight(.semibold)
    /// Coordinates: `.title3` monospaced semibold — the largest numerals.
    static let coordinate = Font.system(.title3, design: .monospaced).weight(.semibold)
    /// Secondary metrics (altitude / accuracy / speed): `.footnote` monospaced.
    static let metric = Font.system(.footnote, design: .monospaced)
    /// Labels and body copy.
    static let body = Font.body
    static let label = Font.subheadline
    static let labelEmphasis = Font.system(.subheadline, design: .default).weight(.semibold)
    /// Hex dumps and log lines.
    static let monoCaption = Font.system(.caption, design: .monospaced)
    static let caption = Font.caption
}

// MARK: - Layout

/// Spacing and sizing constants (DESIGN.md "Layout" / "Components").
enum P2PSpacing {
    static let hairline: CGFloat = 1
    static let gutter: CGFloat = 16
    static let railHeight: CGFloat = 52
    static let primaryHeight: CGFloat = 52
    static let plateCorner: CGFloat = 16
    static let controlCorner: CGFloat = 10
    static let minimumTapTarget: CGFloat = 44
    static let signalBarWidth: CGFloat = 3
    static let signalBarHeight: CGFloat = 10
    static let signalBarSpacing: CGFloat = 2
    static let ledDiameter: CGFloat = 8
}

// MARK: - Formatters

/// Shared number formatting so every screen renders values identically.
enum P2PFormat {
    static func coordinate(_ value: Double, decimalPlaces: Int = 7) -> String {
        String(format: "%.\(decimalPlaces)f", value)
    }

    /// "0.8 秒前" / "12 秒前" / "3 分前" — relative receive age.
    static func relativeAge(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "—" }
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 10 {
            return String(format: "%.1f 秒前", seconds)
        }
        if seconds < 60 {
            return "\(Int(seconds)) 秒前"
        }
        return "\(Int(seconds / 60)) 分前"
    }

    /// "±5 m" / "±—"
    static func accuracy(_ meters: Double?) -> String {
        guard let meters, meters >= 0 else { return "±—" }
        return String(format: "±%.0f m", meters)
    }

    /// "3 m" / "—"
    static func altitude(_ meters: Double?) -> String {
        guard let meters else { return "—" }
        return String(format: "%.0f m", meters)
    }

    /// "0.0 m/s" / "—"
    static func speed(_ metersPerSecond: Double?) -> String {
        guard let metersPerSecond else { return "—" }
        return String(format: "%.1f m/s", metersPerSecond)
    }

    /// "1.0 秒" interval text.
    static func interval(_ milliseconds: UInt16) -> String {
        String(format: "%.1f 秒", Double(milliseconds) / 1000.0)
    }

    /// VoiceOver coordinate sentence: "北緯 35.681236、東経 139.767125".
    static func spokenCoordinate(latitude: Double, longitude: Double, decimalPlaces: Int = 6) -> String {
        let northSouth = latitude >= 0 ? "北緯" : "南緯"
        let eastWest = longitude >= 0 ? "東経" : "西経"
        let lat = String(format: "%.\(decimalPlaces)f", abs(latitude))
        let lon = String(format: "%.\(decimalPlaces)f", abs(longitude))
        return "\(northSouth) \(lat)、\(eastWest) \(lon)"
    }
}

// MARK: - Shared modifiers

extension View {
    /// A 1px hairline in the `line` token.
    func p2pHairline() -> some View {
        overlay(alignment: .bottom) {
            Rectangle()
                .fill(P2PColor.line)
                .frame(height: P2PSpacing.hairline)
        }
    }

    /// Applies the app's paper background and pine tint.
    func p2pScreenBackground() -> some View {
        background(P2PColor.paper.ignoresSafeArea())
    }
}
#endif
