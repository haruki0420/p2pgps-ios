//
//  ProtocolVectorTests.swift
//  P2PGPSProtocolTests
//
//  P2P GPS — spec §10 test vectors.
//  Copyright (C) 2026 haruki0420 and contributors
//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  The normative source is `p2pgps/https://github.com/haruki0420/p2pgps-protocol/blob/main/spec/protocol-v1.md` §10. The expected
//  byte arrays below are derived from the spec's decimal field values
//  (latitude × 10^7 etc.); spec §3.2 was corrected on 2026-11-15 to match them.
//
//  Validation bounds are ±900_000_000 / ±1_800_000_000 (degrees × 10^7); the
//  earlier ±90_000_000 / ±180_000_000 in spec §3.3 was a factor-of-ten typo
//  and is covered by the boundary tests below.
//

import Foundation
import XCTest
@testable import P2PGPSProtocol
import P2PGPSCore

final class LocationPacketVectorTests: XCTestCase {
    // MARK: - 東京駅（有効 fix、altitude/speed 有効）

    func testTokyoStationEncode() {
        let packet = LocationPacket(
            flags: [.validFix, .altitudeValid],
            sequence: 42,
            latitudeE7: 356_812_360,
            longitudeE7: 1_397_671_250,
            altitudeMeters: 3,
            accuracyMeters: 5,
            speedMetersPerSecond: 0,
            timestamp: 1_763_136_000
        )

        let expected: [UInt8] = [
            0x01,             // version
            0x03,             // flags: VALID_FIX | ALTITUDE_VALID
            0x2A, 0x00,       // sequence 42
            0x48, 0x86, 0x44, 0x15, // latitude  356812360
            0x52, 0xC5, 0x4E, 0x53, // longitude 1397671250
            0x03, 0x00,       // altitude 3 m
            0x05,             // accuracy 5 m
            0x00,             // speed 0 m/s
            0x00, 0x52, 0x17, 0x69, // timestamp 1763136000
        ]
        XCTAssertEqual(Array(packet.encoded()), expected)
        XCTAssertEqual(packet.encoded().count, LocationPacket.byteCount)
    }

    func testTokyoStationDecode() throws {
        let bytes: [UInt8] = [
            0x01, 0x03, 0x2A, 0x00,
            0x48, 0x86, 0x44, 0x15,
            0x52, 0xC5, 0x4E, 0x53,
            0x03, 0x00, 0x05, 0x00,
            0x00, 0x52, 0x17, 0x69,
        ]
        let packet = try LocationPacket.decode(Data(bytes))
        XCTAssertEqual(packet.version, 0x01)
        XCTAssertEqual(packet.flags, [.validFix, .altitudeValid])
        XCTAssertEqual(packet.sequence, 42)
        XCTAssertEqual(packet.latitudeE7, 356_812_360)
        XCTAssertEqual(packet.longitudeE7, 1_397_671_250)
        XCTAssertEqual(packet.altitudeMeters, 3)
        XCTAssertEqual(packet.accuracyMeters, 5)
        XCTAssertEqual(packet.speedMetersPerSecond, 0)
        XCTAssertEqual(packet.timestamp, 1_763_136_000)
        XCTAssertEqual(packet.latitude, 35.681236, accuracy: 1e-9)
        XCTAssertEqual(packet.longitude, 139.7671250, accuracy: 1e-9)
        XCTAssertTrue(packet.isUsableFix)
        XCTAssertFalse(packet.isNullIsland)
        XCTAssertFalse(packet.isStale(now: Date(timeIntervalSince1970: 1_763_136_000)))
    }

    // MARK: - 南極（負の緯度・経度、altitude 負）

    func testSouthPoleEncode() {
        let packet = LocationPacket(
            flags: [.validFix, .altitudeValid],
            sequence: 7,
            latitudeE7: -900_000_000,
            longitudeE7: -1_800_000_000,
            altitudeMeters: -30,
            accuracyMeters: 12,
            speedMetersPerSecond: 0,
            timestamp: 1_763_136_000
        )
        let expected: [UInt8] = [
            0x01, 0x03, 0x07, 0x00,
            0x00, 0x17, 0x5B, 0xCA, // -900000000
            0x00, 0x2E, 0xB6, 0x94, // -1800000000
            0xE2, 0xFF,             // -30
            0x0C, 0x00,
            0x00, 0x52, 0x17, 0x69,
        ]
        XCTAssertEqual(Array(packet.encoded()), expected)
    }

    func testSouthPoleDecode() throws {
        let bytes: [UInt8] = [
            0x01, 0x03, 0x07, 0x00,
            0x00, 0x17, 0x5B, 0xCA,
            0x00, 0x2E, 0xB6, 0x94,
            0xE2, 0xFF, 0x0C, 0x00,
            0x00, 0x52, 0x17, 0x69,
        ]
        let packet = try LocationPacket.decode(Data(bytes))
        XCTAssertEqual(packet.latitude, -90.0, accuracy: 1e-9)
        XCTAssertEqual(packet.longitude, -180.0, accuracy: 1e-9)
        XCTAssertEqual(packet.altitudeMeters, -30)
        XCTAssertTrue(packet.isUsableFix)
    }

    // MARK: - Null Island（無効扱い）

    func testNullIslandIsDecodedButNotUsable() throws {
        let packet = LocationPacket(
            flags: [.validFix],
            sequence: 1,
            latitudeE7: 0,
            longitudeE7: 0,
            altitudeMeters: nil,
            accuracyMeters: 5,
            speedMetersPerSecond: 0,
            timestamp: 1_763_136_000
        )
        let decoded = try LocationPacket.decode(packet.encoded())
        XCTAssertTrue(decoded.isNullIsland)
        XCTAssertFalse(decoded.isUsableFix)
        XCTAssertTrue(decoded.hasValidFixFlag)

        // Also just inside the ±0.0001° tolerance.
        let nearNull = LocationPacket(
            flags: [.validFix],
            sequence: 2,
            latitudeE7: 1_000,
            longitudeE7: -1_000,
            altitudeMeters: nil,
            accuracyMeters: 5,
            speedMetersPerSecond: 0,
            timestamp: 1_763_136_000
        )
        XCTAssertTrue(try LocationPacket.decode(nearNull.encoded()).isNullIsland)

        // …and just outside it.
        let offNull = LocationPacket(
            flags: [.validFix],
            sequence: 3,
            latitudeE7: 1_001,
            longitudeE7: 0,
            altitudeMeters: nil,
            accuracyMeters: 5,
            speedMetersPerSecond: 0,
            timestamp: 1_763_136_000
        )
        XCTAssertFalse(try LocationPacket.decode(offNull.encoded()).isNullIsland)
    }

    // MARK: - 範囲外緯度（破棄）

    func testOutOfRangeLatitudeIsRejected() {
        var bytes = Array(LocationPacket.invalid.encoded())
        // latitude = 910000000 (91.0°), little-endian.
        let lat = Int32(910_000_000).littleEndian
        withUnsafeBytes(of: lat) { raw in
            for (index, byte) in raw.enumerated() {
                bytes[4 + index] = byte
            }
        }
        XCTAssertThrowsError(try LocationPacket.decode(Data(bytes))) { error in
            XCTAssertEqual(error as? LocationPacketError, LocationPacketError.latitudeOutOfRange(910_000_000))
        }
    }

    func testOutOfRangeLongitudeIsRejected() {
        var bytes = Array(LocationPacket.invalid.encoded())
        let lon = Int32(-1_800_000_001).littleEndian
        withUnsafeBytes(of: lon) { raw in
            for (index, byte) in raw.enumerated() {
                bytes[8 + index] = byte
            }
        }
        XCTAssertThrowsError(try LocationPacket.decode(Data(bytes))) { error in
            XCTAssertEqual(error as? LocationPacketError, LocationPacketError.longitudeOutOfRange(-1_800_000_001))
        }
    }

    /// Spec §3.3 rule 4: the bounds are degrees × 10^7, i.e. ±900_000_000 and
    /// ±1_800_000_000, and they are inclusive.
    func testCoordinateBoundsAreInclusive() throws {
        let extremes: [(Int32, Int32)] = [
            (900_000_000, 1_800_000_000),
            (-900_000_000, -1_800_000_000),
            (900_000_000, -1_800_000_000),
            (-900_000_000, 1_800_000_000),
            (0, 0),
        ]
        for (latitude, longitude) in extremes {
            let packet = LocationPacket(
                flags: [.validFix],
                sequence: 0,
                latitudeE7: latitude,
                longitudeE7: longitude,
                altitudeMeters: nil,
                accuracyMeters: 5,
                speedMetersPerSecond: 0,
                timestamp: 1_763_136_000
            )
            let decoded = try LocationPacket.decode(packet.encoded())
            XCTAssertEqual(decoded.latitudeE7, latitude)
            XCTAssertEqual(decoded.longitudeE7, longitude)
        }
    }

    func testJustOutsideCoordinateBoundsIsRejected() {
        let cases: [(Int32, Int32)] = [
            (900_000_001, 0),
            (-900_000_001, 0),
            (0, 1_800_000_001),
            (0, -1_800_000_001),
        ]
        for (latitude, longitude) in cases {
            let packet = LocationPacket(
                flags: [.validFix],
                sequence: 0,
                latitudeE7: latitude,
                longitudeE7: longitude,
                altitudeMeters: nil,
                accuracyMeters: 5,
                speedMetersPerSecond: 0,
                timestamp: 1_763_136_000
            )
            XCTAssertThrowsError(try LocationPacket.decode(packet.encoded())) { error in
                if latitude != 0 {
                    XCTAssertEqual(error as? LocationPacketError, LocationPacketError.latitudeOutOfRange(latitude))
                } else {
                    XCTAssertEqual(error as? LocationPacketError, LocationPacketError.longitudeOutOfRange(longitude))
                }
            }
        }
    }

    func testConvenienceInitClampsToBounds() throws {
        let packet = LocationPacket(
            flags: [.validFix],
            sequence: 0,
            latitude: 123.0,
            longitude: -200.0,
            altitudeMeters: nil,
            accuracyMeters: 5,
            speedMetersPerSecond: 0,
            timestamp: 1_763_136_000
        )
        XCTAssertEqual(packet.latitudeE7, LocationPacket.maximumLatitudeE7)
        XCTAssertEqual(packet.longitudeE7, -LocationPacket.maximumLongitudeE7)
        XCTAssertNoThrow(try LocationPacket.decode(packet.encoded()))
    }

    // MARK: - 未知バージョン（破棄）

    func testUnknownVersionIsRejected() {
        var bytes = Array(LocationPacket.invalid.encoded())
        bytes[0] = 0x02
        XCTAssertThrowsError(try LocationPacket.decode(Data(bytes))) { error in
            XCTAssertEqual(error as? LocationPacketError, LocationPacketError.unsupportedVersion(0x02))
        }
    }

    func testReservedFlagIsRejected() {
        var bytes = Array(LocationPacket.invalid.encoded())
        bytes[1] = 0x80
        XCTAssertThrowsError(try LocationPacket.decode(Data(bytes))) { error in
            XCTAssertEqual(error as? LocationPacketError, LocationPacketError.reservedFlagSet(0x80))
        }
    }

    func testInvalidLengthIsRejected() {
        XCTAssertThrowsError(try LocationPacket.decode(Data(repeating: 0, count: 19))) { error in
            XCTAssertEqual(error as? LocationPacketError, LocationPacketError.invalidLength(actual: 19))
        }
        XCTAssertThrowsError(try LocationPacket.decode(Data(repeating: 0, count: 21))) { error in
            XCTAssertEqual(error as? LocationPacketError, LocationPacketError.invalidLength(actual: 21))
        }
    }

    // MARK: - flags

    func testFlagRawValuesMatchSpec() {
        XCTAssertEqual(LocationFlags.validFix.rawValue, 0x01)
        XCTAssertEqual(LocationFlags.altitudeValid.rawValue, 0x02)
        XCTAssertEqual(LocationFlags.speedValid.rawValue, 0x04)
        XCTAssertEqual(LocationFlags.simulated.rawValue, 0x08)
        XCTAssertEqual(LocationFlags.charging.rawValue, 0x10)
        XCTAssertEqual(LocationFlags.lowBattery.rawValue, 0x20)
        XCTAssertEqual(LocationFlags.moving.rawValue, 0x40)
        XCTAssertEqual(LocationFlags.reservedMask, 0x80)
    }

    func testInvalidPacketIsAllZeroExceptVersion() throws {
        let bytes = Array(LocationPacket.invalid.encoded())
        XCTAssertEqual(bytes.count, 20)
        XCTAssertEqual(bytes[0], 0x01)
        XCTAssertEqual(bytes[1], 0x00)
        XCTAssertTrue(bytes.dropFirst(2).allSatisfy { $0 == 0 })
        // flags = 0 is valid on the wire; the packet decodes but is unusable.
        let decoded = try LocationPacket.decode(Data(bytes))
        XCTAssertFalse(decoded.isUsableFix)
        XCTAssertFalse(decoded.hasValidFixFlag)
    }

    // MARK: - timestamp staleness

    func testStalenessWindow() {
        let now = Date(timeIntervalSince1970: 1_763_136_000)
        let fresh = LocationPacket(
            flags: [.validFix], sequence: 0, latitudeE7: 1, longitudeE7: 1,
            altitudeMeters: nil, accuracyMeters: 5, speedMetersPerSecond: 0,
            timestamp: UInt32(now.timeIntervalSince1970) - 60
        )
        let stale = LocationPacket(
            flags: [.validFix], sequence: 0, latitudeE7: 1, longitudeE7: 1,
            altitudeMeters: nil, accuracyMeters: 5, speedMetersPerSecond: 0,
            timestamp: UInt32(now.timeIntervalSince1970) - 25 * 60 * 60
        )
        XCTAssertFalse(fresh.isStale(now: now))
        XCTAssertTrue(stale.isStale(now: now))
    }
}

final class SequenceTrackerTests: XCTestCase {
    func testFirstPacket() {
        var tracker = SequenceTracker()
        XCTAssertEqual(tracker.observe(100), .first)
        XCTAssertEqual(tracker.lastSequence, 100)
        XCTAssertEqual(tracker.observedCount, 1)
    }

    func testInOrder() {
        var tracker = SequenceTracker()
        tracker.observe(1)
        XCTAssertEqual(tracker.observe(2), .inOrder)
        XCTAssertEqual(tracker.observe(3), .inOrder)
    }

    func testWraparoundIsInOrder() {
        var tracker = SequenceTracker()
        tracker.observe(65_535)
        XCTAssertEqual(tracker.observe(0), .inOrder)
        XCTAssertEqual(tracker.observe(1), .inOrder)
    }

    func testRewindIsDetectedButNotRejected() {
        var tracker = SequenceTracker()
        tracker.observe(100)
        XCTAssertEqual(tracker.observe(99), .rewound(by: 1))
        XCTAssertEqual(tracker.rewindCount, 1)
        // The packet itself is still accepted by the protocol layer; only the
        // tracker classifies it.
        XCTAssertEqual(tracker.lastSequence, 99)
    }

    func testGap() {
        var tracker = SequenceTracker()
        tracker.observe(10)
        XCTAssertEqual(tracker.observe(14), .jumpedForward(by: 3))
        XCTAssertEqual(tracker.gapCount, 1)
    }

    func testDuplicate() {
        var tracker = SequenceTracker()
        tracker.observe(5)
        XCTAssertEqual(tracker.observe(5), .duplicate)
    }

    func testReset() {
        var tracker = SequenceTracker()
        tracker.observe(42)
        tracker.reset()
        XCTAssertEqual(tracker.observe(1), .first)
    }
}

final class ExtendedLocationPacketTests: XCTestCase {
    func testEncode() {
        let packet = ExtendedLocationPacket(
            provider: .gps,
            batteryPercentage: 87,
            satellites: 12,
            courseCentidegrees: 12_345,
            verticalAccuracyMeters: 8
        )
        let expected: [UInt8] = [0x01, 0x01, 0x57, 0x0C, 0x39, 0x30, 0x08, 0x00]
        XCTAssertEqual(Array(packet.encoded()), expected)
    }

    func testDecode() throws {
        let bytes: [UInt8] = [0x01, 0x01, 0x57, 0x0C, 0x39, 0x30, 0x08, 0x00]
        let packet = try ExtendedLocationPacket.decode(Data(bytes))
        XCTAssertEqual(packet.provider, .gps)
        XCTAssertEqual(packet.batteryPercentage, 87)
        XCTAssertEqual(packet.batteryPercentValue, 87)
        XCTAssertEqual(packet.satellites, 12)
        XCTAssertEqual(packet.courseCentidegrees, 12_345)
        XCTAssertEqual(packet.courseDegrees, 123.45)
        XCTAssertEqual(packet.verticalAccuracyMeters, 8)
        XCTAssertEqual(packet.reserved, 0)
    }

    func testUnknownValues() throws {
        let packet = ExtendedLocationPacket(
            provider: .network,
            batteryPercentage: 255,
            satellites: 255,
            courseCentidegrees: 65_535,
            verticalAccuracyMeters: 255
        )
        let decoded = try ExtendedLocationPacket.decode(packet.encoded())
        XCTAssertEqual(decoded.provider, .network)
        XCTAssertNil(decoded.batteryPercentValue)
        XCTAssertNil(decoded.courseDegrees)
    }

    func testUnknownProviderRawValueMapsToUnknown() throws {
        let bytes: [UInt8] = [0x01, 0x7F, 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0x00]
        let packet = try ExtendedLocationPacket.decode(Data(bytes))
        XCTAssertEqual(packet.provider, .unknown)
    }

    func testInvalidLengthAndVersion() {
        XCTAssertThrowsError(try ExtendedLocationPacket.decode(Data(repeating: 1, count: 7))) { error in
            XCTAssertEqual(error as? ExtendedLocationPacketError, ExtendedLocationPacketError.invalidLength(actual: 7))
        }
        var bytes = Array(ExtendedLocationPacket.invalid.encoded())
        bytes[0] = 0x02
        XCTAssertThrowsError(try ExtendedLocationPacket.decode(Data(bytes))) { error in
            XCTAssertEqual(error as? ExtendedLocationPacketError, ExtendedLocationPacketError.unsupportedVersion(0x02))
        }
    }
}

final class ControlCommandTests: XCTestCase {
    func testStartEncode() {
        XCTAssertEqual(Array(ControlCommand.start(intervalMilliseconds: 1_000).encoded()), [0x01, 0xE8, 0x03])
        XCTAssertEqual(ControlCommand.start(intervalMilliseconds: 1_000).opcode, 0x01)
    }

    func testStopEncode() {
        XCTAssertEqual(Array(ControlCommand.stop.encoded()), [0x02])
    }

    func testSetIntervalEncode() {
        XCTAssertEqual(Array(ControlCommand.setInterval(intervalMilliseconds: 500).encoded()), [0x03, 0xF4, 0x01])
    }

    func testRequestFixEncode() {
        XCTAssertEqual(Array(ControlCommand.requestFix.encoded()), [0x04])
    }

    func testSetExtendedEncode() {
        XCTAssertEqual(Array(ControlCommand.setExtended(enabled: true).encoded()), [0x05, 0x01])
        XCTAssertEqual(Array(ControlCommand.setExtended(enabled: false).encoded()), [0x05, 0x00])
    }

    func testResetEncode() {
        XCTAssertEqual(Array(ControlCommand.reset.encoded()), [0x7F])
    }

    func testDecodeAllOpcodes() throws {
        XCTAssertEqual(try ControlCommand.decode(Data([0x01, 0xE8, 0x03])), .start(intervalMilliseconds: 1_000))
        XCTAssertEqual(try ControlCommand.decode(Data([0x02])), .stop)
        XCTAssertEqual(try ControlCommand.decode(Data([0x03, 0xF4, 0x01])), .setInterval(intervalMilliseconds: 500))
        XCTAssertEqual(try ControlCommand.decode(Data([0x04])), .requestFix)
        XCTAssertEqual(try ControlCommand.decode(Data([0x05, 0x01])), .setExtended(enabled: true))
        XCTAssertEqual(try ControlCommand.decode(Data([0x05, 0x00])), .setExtended(enabled: false))
        XCTAssertEqual(try ControlCommand.decode(Data([0x7F])), .reset)
    }

    func testUnknownOpcode() {
        XCTAssertThrowsError(try ControlCommand.decode(Data([0x10]))) { error in
            XCTAssertEqual(error as? ControlCommandError, ControlCommandError.unknownOpcode(0x10))
        }
        XCTAssertThrowsError(try ControlCommand.decode(Data([0x42, 0x00]))) { error in
            XCTAssertEqual(error as? ControlCommandError, ControlCommandError.unknownOpcode(0x42))
        }
    }

    func testBadLength() {
        XCTAssertThrowsError(try ControlCommand.decode(Data([0x01, 0xE8]))) { error in
            XCTAssertEqual(error as? ControlCommandError, ControlCommandError.badLength(opcode: 0x01, expected: 3, actual: 2))
        }
        XCTAssertThrowsError(try ControlCommand.decode(Data([0x02, 0x00]))) { error in
            XCTAssertEqual(error as? ControlCommandError, ControlCommandError.badLength(opcode: 0x02, expected: 1, actual: 2))
        }
        XCTAssertThrowsError(try ControlCommand.decode(Data([0x05]))) { error in
            XCTAssertEqual(error as? ControlCommandError, ControlCommandError.badLength(opcode: 0x05, expected: 2, actual: 1))
        }
    }

    func testEmptyWrite() {
        XCTAssertThrowsError(try ControlCommand.decode(Data())) { error in
            XCTAssertEqual(error as? ControlCommandError, ControlCommandError.empty)
        }
    }

    /// Spec §5.1 (v1.0.1): 0 → 1000, 1–99 → 100, 100–60000 → unchanged,
    /// 60001–65535 → 60000. This is the boundary-clamp decision shared by all
    /// three implementations.
    func testIntervalNormalisation() {
        XCTAssertEqual(ControlCommand.normalizedInterval(0), 1_000)
        XCTAssertEqual(ControlCommand.normalizedInterval(1), 100)
        XCTAssertEqual(ControlCommand.normalizedInterval(50), 100)
        XCTAssertEqual(ControlCommand.normalizedInterval(99), 100)
        XCTAssertEqual(ControlCommand.normalizedInterval(100), 100)
        XCTAssertEqual(ControlCommand.normalizedInterval(1_000), 1_000)
        XCTAssertEqual(ControlCommand.normalizedInterval(60_000), 60_000)
        XCTAssertEqual(ControlCommand.normalizedInterval(60_001), 60_000)
        XCTAssertEqual(ControlCommand.normalizedInterval(65_000), 60_000)
        XCTAssertEqual(ControlCommand.normalizedInterval(65_535), 60_000)

        XCTAssertEqual(ControlCommand.start(intervalMilliseconds: 0).resolvedIntervalMilliseconds, 1_000)
        XCTAssertEqual(ControlCommand.start(intervalMilliseconds: 50).resolvedIntervalMilliseconds, 100)
        XCTAssertEqual(ControlCommand.start(intervalMilliseconds: 100).resolvedIntervalMilliseconds, 100)
        XCTAssertEqual(ControlCommand.setInterval(intervalMilliseconds: 60_000).resolvedIntervalMilliseconds, 60_000)
        XCTAssertEqual(ControlCommand.setInterval(intervalMilliseconds: 65_000).resolvedIntervalMilliseconds, 60_000)
        XCTAssertNil(ControlCommand.stop.resolvedIntervalMilliseconds)
    }

    /// Spec §5.1: the Control characteristic carries the **raw** value; the
    /// sender normalises when it applies it. `encoded()` must not clamp.
    func testRawIntervalIsEncodedVerbatim() {
        XCTAssertEqual(Array(ControlCommand.start(intervalMilliseconds: 0).encoded()), [0x01, 0x00, 0x00])
        XCTAssertEqual(Array(ControlCommand.start(intervalMilliseconds: 50).encoded()), [0x01, 0x32, 0x00])
        XCTAssertEqual(Array(ControlCommand.start(intervalMilliseconds: 60_001).encoded()), [0x01, 0x61, 0xEA])
        XCTAssertEqual(Array(ControlCommand.start(intervalMilliseconds: 65_535).encoded()), [0x01, 0xFF, 0xFF])
        XCTAssertEqual(Array(ControlCommand.setInterval(intervalMilliseconds: 0).encoded()), [0x03, 0x00, 0x00])
        XCTAssertEqual(Array(ControlCommand.setInterval(intervalMilliseconds: 60_001).encoded()), [0x03, 0x61, 0xEA])
    }

    /// Decoding preserves the raw value; the normalised value is only applied
    /// through `resolvedIntervalMilliseconds` (spec §5.1).
    func testDecodePreservesRawIntervalAndNormalisesOnApply() throws {
        let startZero = try ControlCommand.decode(Data([0x01, 0x00, 0x00]))
        XCTAssertEqual(startZero, .start(intervalMilliseconds: 0))
        XCTAssertEqual(startZero.resolvedIntervalMilliseconds, 1_000)

        let startFifty = try ControlCommand.decode(Data([0x01, 0x32, 0x00]))
        XCTAssertEqual(startFifty, .start(intervalMilliseconds: 50))
        XCTAssertEqual(startFifty.resolvedIntervalMilliseconds, 100)

        let tooLarge = try ControlCommand.decode(Data([0x03, 0x61, 0xEA]))
        XCTAssertEqual(tooLarge, .setInterval(intervalMilliseconds: 60_001))
        XCTAssertEqual(tooLarge.resolvedIntervalMilliseconds, 60_000)
    }
}

final class SenderStatusTests: XCTestCase {
    func testEncode() {
        let status = SenderStatus(
            state: .streaming,
            intervalMilliseconds: 1_000,
            batteryPercentage: 87,
            flags: [.extendedEnabled, .fixAvailable],
            lastError: .none
        )
        let expected: [UInt8] = [0x01, 0x01, 0xE8, 0x03, 0x57, 0x03, 0x00, 0x00]
        XCTAssertEqual(Array(status.encoded()), expected)
    }

    func testDecode() throws {
        let bytes: [UInt8] = [0x01, 0x01, 0xE8, 0x03, 0x57, 0x03, 0x00, 0x00]
        let status = try SenderStatus.decode(Data(bytes))
        XCTAssertEqual(status.state, .streaming)
        XCTAssertEqual(status.intervalMilliseconds, 1_000)
        XCTAssertEqual(status.batteryPercentage, 87)
        XCTAssertEqual(status.flags, [.extendedEnabled, .fixAvailable])
        XCTAssertEqual(status.lastError, .none)
    }

    func testErrorState() throws {
        let status = SenderStatus(state: .error, lastError: .unknownOpcode)
        let decoded = try SenderStatus.decode(status.encoded())
        XCTAssertEqual(decoded.state, .error)
        XCTAssertEqual(decoded.lastError, .unknownOpcode)
    }

    func testInvalidLengthAndVersion() {
        XCTAssertThrowsError(try SenderStatus.decode(Data(repeating: 1, count: 7))) { error in
            XCTAssertEqual(error as? SenderStatusError, SenderStatusError.invalidLength(actual: 7))
        }
        var bytes = Array(SenderStatus.idle.encoded())
        bytes[0] = 0x09
        XCTAssertThrowsError(try SenderStatus.decode(Data(bytes))) { error in
            XCTAssertEqual(error as? SenderStatusError, SenderStatusError.unsupportedVersion(0x09))
        }
    }

    func testUnknownBattery() throws {
        let decoded = try SenderStatus.decode(SenderStatus.idle.encoded())
        XCTAssertNil(decoded.batteryPercentValue)
    }
}

final class ProtocolConstantsTests: XCTestCase {
    func testUUIDsMatchSpec() {
        XCTAssertEqual(P2PGPS.serviceUUID, "B1E5A000-9C3D-4E7A-8F20-1A2B3C4D5E6F")
        XCTAssertEqual(P2PGPS.locationCharacteristicUUID, "B1E5A001-9C3D-4E7A-8F20-1A2B3C4D5E6F")
        XCTAssertEqual(P2PGPS.controlCharacteristicUUID, "B1E5A002-9C3D-4E7A-8F20-1A2B3C4D5E6F")
        XCTAssertEqual(P2PGPS.statusCharacteristicUUID, "B1E5A003-9C3D-4E7A-8F20-1A2B3C4D5E6F")
        XCTAssertEqual(P2PGPS.extendedLocationCharacteristicUUID, "B1E5A004-9C3D-4E7A-8F20-1A2B3C4D5E6F")
        XCTAssertEqual(P2PGPS.deviceInformationServiceUUID, "0000180A-0000-1000-8000-00805F9B34FB")
    }

    func testLocalNameFormat() {
        let name = P2PGPS.localName(platform: .ios, suffix: "7f3c")
        XCTAssertEqual(name, "P2PGPS-IOS-7F3C")
        XCTAssertTrue(P2PGPS.isP2PGPSLocalName(name))
        XCTAssertEqual(P2PGPS.platform(fromLocalName: name), .ios)
        XCTAssertEqual(P2PGPS.platform(fromLocalName: "P2PGPS-ANDROID-A1B2"), .android)
        XCTAssertNil(P2PGPS.platform(fromLocalName: "OtherDevice"))
        XCTAssertFalse(P2PGPS.isP2PGPSLocalName(nil))
    }

    func testRandomLocalNameHasFourHexSuffix() {
        let name = P2PGPS.randomLocalName(platform: .ios)
        let suffix = name.replacingOccurrences(of: "P2PGPS-IOS-", with: "")
        XCTAssertEqual(suffix.count, 4)
        XCTAssertTrue(suffix.allSatisfy { $0.isHexDigit })
    }
}

final class GPSFixConversionTests: XCTestCase {
    func testPacketToFix() throws {
        let packet = LocationPacket(
            flags: [.validFix, .altitudeValid, .speedValid, .simulated],
            sequence: 9,
            latitudeE7: 356_812_360,
            longitudeE7: 1_397_671_250,
            altitudeMeters: 3,
            accuracyMeters: 5,
            speedMetersPerSecond: 2,
            timestamp: 1_763_136_000
        )
        let fix = packet.gpsFix(receivedAt: Date(timeIntervalSince1970: 1_763_136_001))
        XCTAssertEqual(fix.latitude, 35.681236, accuracy: 1e-9)
        XCTAssertEqual(fix.longitude, 139.767125, accuracy: 1e-9)
        XCTAssertEqual(fix.altitudeMeters, 3)
        XCTAssertEqual(fix.horizontalAccuracyMeters, 5)
        XCTAssertEqual(fix.speedMetersPerSecond, 2)
        XCTAssertTrue(fix.isSimulated)
        XCTAssertEqual(fix.sequence, 9)
        XCTAssertTrue(fix.isUsable)
    }

    func testFixToPacketRoundTrip() throws {
        let fix = GPSFix(
            latitude: 35.681236,
            longitude: 139.767125,
            altitudeMeters: 3,
            horizontalAccuracyMeters: 5,
            speedMetersPerSecond: 0,
            timestamp: Date(timeIntervalSince1970: 1_763_136_000)
        )
        let packet = LocationPacket(fix: fix, sequence: 42)
        let decoded = try LocationPacket.decode(packet.encoded())
        XCTAssertEqual(decoded.latitudeE7, 356_812_360)
        XCTAssertEqual(decoded.longitudeE7, 1_397_671_250)
        XCTAssertEqual(decoded.timestamp, 1_763_136_000)
        XCTAssertTrue(decoded.isUsableFix)
        XCTAssertTrue(decoded.flags.contains(.altitudeValid))
        XCTAssertTrue(decoded.flags.contains(.speedValid))
    }

    func testUnknownAccuracyBecomes255() throws {
        let fix = GPSFix(latitude: 10, longitude: 20, horizontalAccuracyMeters: -1)
        let decoded = try LocationPacket.decode(LocationPacket(fix: fix, sequence: 0).encoded())
        XCTAssertEqual(decoded.accuracyMeters, 255)
    }

    func testExtendedFromFix() throws {
        let fix = GPSFix(
            latitude: 1, longitude: 2,
            courseDegrees: 123.45,
            provider: .gps,
            batteryPercentage: 87,
            satellites: 12
        )
        let extended = ExtendedLocationPacket(fix: fix)
        let decoded = try ExtendedLocationPacket.decode(extended.encoded())
        XCTAssertEqual(decoded.provider, .gps)
        XCTAssertEqual(decoded.batteryPercentage, 87)
        XCTAssertEqual(decoded.satellites, 12)
        XCTAssertEqual(decoded.courseCentidegrees, 12_345)
    }
}
