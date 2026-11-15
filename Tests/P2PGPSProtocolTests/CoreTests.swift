//
//  CoreTests.swift
//  P2PGPSProtocolTests
//
//  P2P GPS — Core layer tests (filter, settings, logging).
//  Copyright (C) 2026 haruki0420 and contributors
//  SPDX-License-Identifier: AGPL-3.0-or-later
//

import Foundation
import XCTest
@testable import P2PGPSProtocol
import P2PGPSCore

final class FixFilterTests: XCTestCase {
    private func makeFix(
        latitude: Double,
        longitude: Double,
        accuracy: Double = 5,
        timestamp: Date = Date(),
        speed: Double? = nil,
        isSimulated: Bool = false
    ) -> GPSFix {
        GPSFix(
            latitude: latitude,
            longitude: longitude,
            horizontalAccuracyMeters: accuracy,
            speedMetersPerSecond: speed,
            timestamp: timestamp,
            receivedAt: timestamp,
            isSimulated: isSimulated
        )
    }

    func testFirstFixIsAccepted() {
        var filter = FixFilter()
        let fix = makeFix(latitude: 35.681236, longitude: 139.767125)
        guard case .accepted(let accepted) = filter.process(fix) else {
            XCTFail("最初の fix は受理されるべき")
            return
        }
        XCTAssertEqual(accepted.latitude, 35.681236, accuracy: 1e-9)
        XCTAssertEqual(filter.acceptedCount, 1)
        XCTAssertNotNil(filter.lastAccepted)
    }

    func testInvalidCoordinateIsRejected() {
        var filter = FixFilter()
        let nullIsland = makeFix(latitude: 0, longitude: 0)
        guard case .rejected(.invalidCoordinate) = filter.process(nullIsland) else {
            XCTFail("Null Island は拒否されるべき")
            return
        }
        XCTAssertEqual(filter.rejectedCount, 1)
    }

    func testPoorAccuracyIsRejected() {
        var filter = FixFilter()
        let fix = makeFix(latitude: 35.0, longitude: 139.0, accuracy: 500)
        guard case .rejected(.poorAccuracy(let accuracy)) = filter.process(fix) else {
            XCTFail("精度の悪い fix は拒否されるべき")
            return
        }
        XCTAssertEqual(accuracy, 500)
    }

    func testTeleportIsRejected() {
        var filter = FixFilter()
        let now = Date()
        let first = makeFix(latitude: 35.0, longitude: 139.0, timestamp: now)
        guard case .accepted = filter.process(first) else {
            XCTFail("最初の fix は受理されるべき")
            return
        }
        // ~1 km in one second is far above the 120 m/s limit.
        let jump = makeFix(latitude: 35.01, longitude: 139.0, timestamp: now.addingTimeInterval(1))
        guard case .rejected(.implausibleJump) = filter.process(jump) else {
            XCTFail("瞬間移動は拒否されるべき")
            return
        }
    }

    func testSimulatedTeleportIsAcceptedWithoutSmoothing() {
        var filter = FixFilter()
        let now = Date()
        _ = filter.process(makeFix(latitude: 35.0, longitude: 139.0, timestamp: now))
        // Debug simulate can move to another city; it must not be rejected as
        // an implausible jump, and must not be smoothed towards the old anchor.
        let jump = makeFix(
            latitude: 51.5,
            longitude: -0.12,
            timestamp: now.addingTimeInterval(1),
            isSimulated: true
        )
        guard case .accepted(let accepted) = filter.process(jump) else {
            XCTFail("シミュレート位置の移動は受理されるべき")
            return
        }
        XCTAssertEqual(accepted.latitude, 51.5, accuracy: 1e-9)
        XCTAssertEqual(accepted.longitude, -0.12, accuracy: 1e-9)
    }

    func testStaleFixIsAcceptedButFlagged() {        var filter = FixFilter()
        let old = Date().addingTimeInterval(-25 * 60 * 60)
        let fix = makeFix(latitude: 35.0, longitude: 139.0, timestamp: old)
        guard case .accepted(let accepted) = filter.process(fix) else {
            XCTFail("stale は破棄せず受理し、表示側で警告する（仕様 §3.3-7）")
            return
        }
        XCTAssertTrue(accepted.isStale(now: Date()))
    }

    func testSmoothingMovesTowardsNewFix() {
        var filter = FixFilter(configuration: .init(smoothingFactor: 0.5))
        let now = Date()
        let first = makeFix(latitude: 35.0, longitude: 139.0, timestamp: now)
        _ = filter.process(first)
        let second = makeFix(latitude: 35.001, longitude: 139.0, timestamp: now.addingTimeInterval(1))
        guard case .accepted(let smoothed) = filter.process(second) else {
            XCTFail("2 つ目の fix は受理されるべき")
            return
        }
        XCTAssertGreaterThan(smoothed.latitude, 35.0)
        XCTAssertLessThan(smoothed.latitude, 35.001)
    }

    func testResetForgetsAnchor() {
        var filter = FixFilter()
        _ = filter.process(makeFix(latitude: 35.0, longitude: 139.0))
        filter.reset()
        XCTAssertNil(filter.lastAccepted)
    }
}

final class AppSettingsTests: XCTestCase {
    func testDefaultsMatchSpec() {
        let settings = AppSettings()
        // Spec §8: injection is off by default.
        XCTAssertFalse(settings.injectionEnabled)
        XCTAssertTrue(settings.autoReconnect)
        XCTAssertEqual(settings.logCoordinateDecimalPlaces, 5)
        XCTAssertEqual(settings.targetDeviceIPAddress, "10.7.0.1")
        XCTAssertFalse(settings.useTLocationURLSchemeFallback)
        XCTAssertEqual(settings.senderIntervalMilliseconds, 1_000)
        XCTAssertTrue(settings.keepAliveLocationUpdates)
        XCTAssertFalse(settings.extendedLocationEnabled)
    }

    func testSettingsStoreRoundTrip() {
        let suiteName = "p2pgps.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("UserDefaults suite を作成できません")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)
        XCTAssertFalse(store.injectionEnabled)
        store.injectionEnabled = true
        store.targetDeviceIPAddress = "10.0.0.2"
        store.senderIntervalMilliseconds = 2_000

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertTrue(reloaded.injectionEnabled)
        XCTAssertEqual(reloaded.targetDeviceIPAddress, "10.0.0.2")
        XCTAssertEqual(reloaded.senderIntervalMilliseconds, 2_000)
    }
}

final class LogStoreTests: XCTestCase {
    func testCoordinateRounding() {
        let text = LogStore.roundedCoordinate(latitude: 35.681236, longitude: 139.767126, decimalPlaces: 5)
        XCTAssertEqual(text, "35.68124, 139.76713")
    }

    func testLogIsMemoryOnlyAndBounded() {
        let store = LogStore(maximumEntries: 3)
        store.info("one")
        store.warning("two")
        store.error("three")
        store.debug("four")
        let snapshot = store.snapshot()
        XCTAssertEqual(snapshot.count, 3)
        XCTAssertEqual(snapshot.last?.message, "four")
        XCTAssertEqual(store.exportText().split(separator: "\n").count, 3)
    }

    func testClear() {
        let store = LogStore()
        store.info("hello")
        store.clear()
        XCTAssertTrue(store.snapshot().isEmpty)
    }
}

final class AppRoleTests: XCTestCase {
    func testDefaultRoleByDevice() {
        XCTAssertEqual(AppRole.default(isPad: true), .receiver)
        XCTAssertEqual(AppRole.default(isPad: false), .sender)
    }

    func testRoleMetadata() {
        XCTAssertEqual(AppRole.sender.title, "送信する")
        XCTAssertEqual(AppRole.receiver.title, "受信する")
        XCTAssertFalse(AppRole.sender.subtitle.isEmpty)
    }
}

final class GPSFixTests: XCTestCase {
    func testDistance() {
        // Tokyo Station to Shinjuku Station is roughly 6.4 km.
        let distance = GPSFix.distance(
            fromLatitude: 35.681236,
            fromLongitude: 139.767125,
            toLatitude: 35.689487,
            toLongitude: 139.691711
        )
        XCTAssertGreaterThan(distance, 6_000)
        XCTAssertLessThan(distance, 7_000)
    }

    func testUsable() {
        XCTAssertTrue(GPSFix(latitude: 35, longitude: 139).isUsable)
        XCTAssertFalse(GPSFix(latitude: 0, longitude: 0).isUsable)
        XCTAssertFalse(GPSFix(latitude: 91, longitude: 0).isUsable)
    }

    func testStaleness() {
        let now = Date()
        XCTAssertFalse(GPSFix(latitude: 1, longitude: 1, timestamp: now).isStale(now: now))
        let old = now.addingTimeInterval(-25 * 60 * 60)
        XCTAssertTrue(GPSFix(latitude: 1, longitude: 1, timestamp: old).isStale(now: now))
    }
}
