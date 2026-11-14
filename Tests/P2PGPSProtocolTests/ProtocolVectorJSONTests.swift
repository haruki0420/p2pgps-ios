//
//  ProtocolVectorJSONTests.swift
//  P2PGPSProtocolTests
//
//  P2P GPS — shared protocol test vectors, read from JSON.
//  Copyright (C) 2026 haruki0420 and contributors
//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  `Vectors/*.json` is a manual mirror of `p2pgps-protocol/tests/vectors/`
//  (MIT). Reading the shared vectors instead of re-typing them in Swift means a
//  divergence between the reference implementation and this one shows up as a
//  test failure (review C-4), and the Control interval vectors pin the raw
//  encode / normalised apply split from spec §5.1 (review C-1).
//

import Foundation
import XCTest
@testable import P2PGPSProtocol

final class ProtocolVectorJSONTests: XCTestCase {
    // MARK: - Loading helpers

    private enum VectorError: Error {
        case malformed(String)
    }

    private func loadJSON(_ name: String) throws -> [String: Any] {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Vectors"),
            "Vectors/\(name).json is missing from the test bundle"
        )
        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? [String: Any] else {
            throw VectorError.malformed("\(name).json: top level is not an object")
        }
        return root
    }

    private func number(_ dictionary: [String: Any], _ key: String) throws -> NSNumber {
        guard let value = dictionary[key] as? NSNumber else {
            throw VectorError.malformed("\(key) is not a number")
        }
        return value
    }

    private func bools(_ value: Any?) -> [Bool]? {
        guard let array = value as? [Any] else { return nil }
        return array.map { element in
            if let bool = element as? Bool { return bool }
            return (element as? NSNumber)?.boolValue ?? false
        }
    }

    private func bytes(from hex: String) -> Data {
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else {
                XCTFail("invalid hex: \(hex)")
                return data
            }
            data.append(byte)
            index = next
        }
        return data
    }

    // MARK: - Schema

    func testVectorFilesArePresentAndSchemaTagged() throws {
        let expected: [(String, String)] = [
            ("location", "location"),
            ("extended", "extended"),
            ("control", "control"),
            ("status", "status"),
            ("sequences", "sequence"),
        ]
        for (name, kind) in expected {
            let root = try loadJSON(name)
            XCTAssertEqual(root["kind"] as? String, kind, "\(name).json: kind")
            let schema = try XCTUnwrap(root["schema"] as? String, "\(name).json: schema")
            XCTAssertTrue(
                schema.hasPrefix("p2pgps-protocol/test-vectors/"),
                "\(name).json: unexpected schema \(schema)"
            )
        }
    }

    // MARK: - Location

    func testLocationVectors() throws {
        let root = try loadJSON("location")
        let vectors = try XCTUnwrap(root["vectors"] as? [[String: Any]])
        XCTAssertFalse(vectors.isEmpty)

        for vector in vectors {
            let id = try XCTUnwrap(vector["id"] as? String)
            let data = bytes(from: try XCTUnwrap(vector["hex"] as? String))
            let wire = try XCTUnwrap(vector["wire"] as? [String: Any])
            let expect = try XCTUnwrap(vector["expect"] as? [String: Any])
            let expectedValid = try XCTUnwrap(expect["valid"] as? Bool)
            let expectedValidFix = expect["valid_fix"] as? Bool
            let reason = expect["reason"] as? String

            let version = try number(wire, "version").uint8Value
            let flagsRaw = try number(wire, "flags").uint8Value
            let sequence = try number(wire, "sequence").uint16Value
            let latitude = try number(wire, "latitude").int32Value
            let longitude = try number(wire, "longitude").int32Value
            let altitude = try number(wire, "altitude_m").int16Value
            let accuracy = try number(wire, "accuracy_m").uint8Value
            let speed = try number(wire, "speed_mps").uint8Value
            let timestamp = try number(wire, "timestamp").uint32Value

            // encode(wire) == hex
            let packet = LocationPacket(
                version: version,
                flags: LocationFlags(rawValue: flagsRaw),
                sequence: sequence,
                latitudeE7: latitude,
                longitudeE7: longitude,
                altitudeMeters: altitude,
                accuracyMeters: accuracy,
                speedMetersPerSecond: speed,
                timestamp: timestamp
            )
            XCTAssertEqual(packet.encoded(), data, "\(id): encode(wire) != hex")

            // degrees: 度表記 → ワイヤ値
            if let degrees = vector["degrees"] as? [String: String],
               let latitudeText = degrees["latitude"],
               let longitudeText = degrees["longitude"],
               let latitudeDegrees = Double(latitudeText),
               let longitudeDegrees = Double(longitudeText) {
                XCTAssertEqual(packet.latitude, latitudeDegrees, accuracy: 1e-7, "\(id): latitude degrees")
                XCTAssertEqual(packet.longitude, longitudeDegrees, accuracy: 1e-7, "\(id): longitude degrees")
            }

            // decode(hex) の期待
            switch reason {
            case nil:
                let decoded = try LocationPacket.decode(data)
                XCTAssertEqual(decoded.version, version, "\(id): version")
                XCTAssertEqual(decoded.flags.rawValue, flagsRaw, "\(id): flags")
                XCTAssertEqual(decoded.sequence, sequence, "\(id): sequence")
                XCTAssertEqual(decoded.latitudeE7, latitude, "\(id): latitude")
                XCTAssertEqual(decoded.longitudeE7, longitude, "\(id): longitude")
                XCTAssertEqual(decoded.accuracyMeters, accuracy, "\(id): accuracy")
                XCTAssertEqual(decoded.speedMetersPerSecond, speed, "\(id): speed")
                XCTAssertEqual(decoded.timestamp, timestamp, "\(id): timestamp")
                if flagsRaw & LocationFlags.altitudeValid.rawValue != 0 {
                    XCTAssertEqual(decoded.altitudeMeters, altitude, "\(id): altitude")
                } else {
                    XCTAssertNil(decoded.altitudeMeters, "\(id): altitude must be nil without ALTITUDE_VALID")
                }
                if let expectedValidFix {
                    XCTAssertEqual(decoded.hasValidFixFlag, expectedValidFix, "\(id): VALID_FIX")
                }
                // `expect.valid` means "the receiver accepts the packet"
                // (reason == null). For the no-fix vector that is true even
                // though `isUsableFix` is false (VALID_FIX=0).
                XCTAssertTrue(expectedValid, "\(id): expect.valid should be true when reason is null")
                XCTAssertEqual(
                    decoded.isUsableFix,
                    expectedValidFix ?? true,
                    "\(id): isUsableFix"
                )
            case "null_island":
                let decoded = try LocationPacket.decode(data)
                XCTAssertFalse(expectedValid, "\(id): null island must be discarded")
                XCTAssertTrue(decoded.isNullIsland, "\(id): isNullIsland")
                XCTAssertFalse(decoded.isUsableFix, "\(id): isUsableFix")
                XCTAssertEqual(decoded.hasValidFixFlag, expectedValidFix ?? false, "\(id): VALID_FIX")
            case "bad_length":
                XCTAssertThrowsError(try LocationPacket.decode(data), "\(id): expected bad length") { error in
                    XCTAssertEqual(error as? LocationPacketError, .invalidLength(actual: data.count), "\(id)")
                }
            case "unknown_version":
                XCTAssertThrowsError(try LocationPacket.decode(data), "\(id): expected unknown version") { error in
                    XCTAssertEqual(error as? LocationPacketError, .unsupportedVersion(version), "\(id)")
                }
            case "reserved_flag_set":
                XCTAssertThrowsError(try LocationPacket.decode(data), "\(id): expected reserved flag") { error in
                    XCTAssertEqual(error as? LocationPacketError, .reservedFlagSet(flagsRaw), "\(id)")
                }
            case "latitude_out_of_range":
                XCTAssertThrowsError(try LocationPacket.decode(data), "\(id): expected latitude range") { error in
                    XCTAssertEqual(error as? LocationPacketError, .latitudeOutOfRange(latitude), "\(id)")
                }
            case "longitude_out_of_range":
                XCTAssertThrowsError(try LocationPacket.decode(data), "\(id): expected longitude range") { error in
                    XCTAssertEqual(error as? LocationPacketError, .longitudeOutOfRange(longitude), "\(id)")
                }
            default:
                XCTFail("\(id): unknown expect.reason \(reason ?? "nil")")
            }
        }
    }

    // MARK: - Extended

    func testExtendedVectors() throws {
        let root = try loadJSON("extended")
        let vectors = try XCTUnwrap(root["vectors"] as? [[String: Any]])
        XCTAssertFalse(vectors.isEmpty)

        for vector in vectors {
            let id = try XCTUnwrap(vector["id"] as? String)
            let data = bytes(from: try XCTUnwrap(vector["hex"] as? String))
            let wire = try XCTUnwrap(vector["wire"] as? [String: Any])
            let expect = try XCTUnwrap(vector["expect"] as? [String: Any])
            let reason = expect["reason"] as? String

            let version = try number(wire, "version").uint8Value
            let providerRaw = try number(wire, "provider").uint8Value
            let battery = try number(wire, "battery_pct").uint8Value
            let satellites = try number(wire, "satellites").uint8Value
            let course = try number(wire, "course").uint16Value
            let verticalAccuracy = try number(wire, "vertical_accuracy_m").uint8Value
            let reserved = try number(wire, "reserved").uint8Value

            let packet = ExtendedLocationPacket(
                version: version,
                provider: ExtendedLocationPacket.Provider(wireValue: providerRaw),
                batteryPercentage: battery,
                satellites: satellites,
                courseCentidegrees: course,
                verticalAccuracyMeters: verticalAccuracy,
                reserved: reserved
            )
            XCTAssertEqual(packet.encoded(), data, "\(id): encode(wire) != hex")

            switch reason {
            case nil:
                let decoded = try ExtendedLocationPacket.decode(data)
                XCTAssertEqual(decoded.version, version, "\(id): version")
                XCTAssertEqual(decoded.provider.rawValue, providerRaw, "\(id): provider")
                XCTAssertEqual(decoded.batteryPercentage, battery, "\(id): battery")
                XCTAssertEqual(decoded.satellites, satellites, "\(id): satellites")
                XCTAssertEqual(decoded.courseCentidegrees, course, "\(id): course")
                XCTAssertEqual(decoded.verticalAccuracyMeters, verticalAccuracy, "\(id): vertical accuracy")
                XCTAssertEqual(decoded.reserved, reserved, "\(id): reserved")
            case "unknown_version":
                XCTAssertThrowsError(try ExtendedLocationPacket.decode(data), "\(id): expected unknown version") { error in
                    XCTAssertEqual(error as? ExtendedLocationPacketError, .unsupportedVersion(version), "\(id)")
                }
            case "bad_length":
                XCTAssertThrowsError(try ExtendedLocationPacket.decode(data), "\(id): expected bad length") { error in
                    XCTAssertEqual(error as? ExtendedLocationPacketError, .invalidLength(actual: data.count), "\(id)")
                }
            default:
                XCTFail("\(id): unknown expect.reason \(reason ?? "nil")")
            }
        }
    }

    // MARK: - Status

    func testStatusVectors() throws {
        let root = try loadJSON("status")
        let vectors = try XCTUnwrap(root["vectors"] as? [[String: Any]])
        XCTAssertFalse(vectors.isEmpty)

        for vector in vectors {
            let id = try XCTUnwrap(vector["id"] as? String)
            let data = bytes(from: try XCTUnwrap(vector["hex"] as? String))
            let wire = try XCTUnwrap(vector["wire"] as? [String: Any])
            let expect = try XCTUnwrap(vector["expect"] as? [String: Any])
            let reason = expect["reason"] as? String

            let version = try number(wire, "version").uint8Value
            let stateRaw = try number(wire, "state").uint8Value
            let interval = try number(wire, "interval_ms").uint16Value
            let battery = try number(wire, "battery_pct").uint8Value
            let flagsRaw = try number(wire, "status_flags").uint8Value
            let lastErrorRaw = try number(wire, "last_error").uint8Value
            let reserved = try number(wire, "reserved").uint8Value

            let status = SenderStatus(
                version: version,
                state: try XCTUnwrap(SenderStatus.State(rawValue: stateRaw), "\(id): state"),
                intervalMilliseconds: interval,
                batteryPercentage: battery,
                flags: SenderStatus.Flags(rawValue: flagsRaw),
                lastError: try XCTUnwrap(SenderStatus.LastError(rawValue: lastErrorRaw), "\(id): last_error"),
                reserved: reserved
            )
            XCTAssertEqual(status.encoded(), data, "\(id): encode(wire) != hex")

            switch reason {
            case nil:
                let decoded = try SenderStatus.decode(data)
                XCTAssertEqual(decoded.version, version, "\(id): version")
                XCTAssertEqual(decoded.state.rawValue, stateRaw, "\(id): state")
                XCTAssertEqual(decoded.intervalMilliseconds, interval, "\(id): interval")
                XCTAssertEqual(decoded.batteryPercentage, battery, "\(id): battery")
                XCTAssertEqual(decoded.flags.rawValue, flagsRaw, "\(id): flags")
                XCTAssertEqual(decoded.lastError.rawValue, lastErrorRaw, "\(id): last_error")
                XCTAssertEqual(decoded.reserved, reserved, "\(id): reserved")
            case "unknown_version":
                XCTAssertThrowsError(try SenderStatus.decode(data), "\(id): expected unknown version") { error in
                    XCTAssertEqual(error as? SenderStatusError, .unsupportedVersion(version), "\(id)")
                }
            case "bad_length":
                XCTAssertThrowsError(try SenderStatus.decode(data), "\(id): expected bad length") { error in
                    XCTAssertEqual(error as? SenderStatusError, .invalidLength(actual: data.count), "\(id)")
                }
            default:
                XCTFail("\(id): unknown expect.reason \(reason ?? "nil")")
            }
        }
    }

    // MARK: - Control

    func testControlVectors() throws {
        let root = try loadJSON("control")
        let vectors = try XCTUnwrap(root["vectors"] as? [[String: Any]])
        XCTAssertFalse(vectors.isEmpty)

        for vector in vectors {
            let id = try XCTUnwrap(vector["id"] as? String)
            let data = bytes(from: try XCTUnwrap(vector["hex"] as? String))
            let expect = try XCTUnwrap(vector["expect"] as? [String: Any])
            let expectedValid = try XCTUnwrap(expect["valid"] as? Bool)

            if let commandJSON = vector["command"] as? [String: Any] {
                let command = try makeCommand(commandJSON, id: id)
                XCTAssertTrue(expectedValid, "\(id): command present but expect.valid=false")
                XCTAssertEqual(command.encoded(), data, "\(id): raw encode != hex")

                let decoded = try ControlCommand.decode(data)
                XCTAssertEqual(decoded, command, "\(id): decode(hex) != command")

                let decodedJSON = try XCTUnwrap(expect["decoded"] as? [String: Any], "\(id): expect.decoded")
                XCTAssertEqual(opcodeName(decoded), decodedJSON["opcode"] as? String, "\(id): opcode")

                if let interval = decodedJSON["interval_ms"] as? NSNumber {
                    XCTAssertEqual(rawInterval(decoded), interval.uint16Value, "\(id): raw interval")
                }
                if let normalized = decodedJSON["normalized_interval_ms"] as? NSNumber {
                    XCTAssertEqual(
                        decoded.resolvedIntervalMilliseconds,
                        normalized.uint16Value,
                        "\(id): normalized interval (spec §5.1)"
                    )
                }
                if let enabled = decodedJSON["enabled"] as? Bool {
                    XCTAssertEqual(extendedEnabled(decoded), enabled, "\(id): enabled")
                }
            } else {
                XCTAssertFalse(expectedValid, "\(id): expect.valid=true but command is null")
                let expectedError = try XCTUnwrap(expect["error"] as? String, "\(id): expect.error")
                let expectedLastError = try XCTUnwrap(expect["last_error"] as? NSNumber, "\(id): expect.last_error")
                XCTAssertThrowsError(try ControlCommand.decode(data), "\(id): expected \(expectedError)") { error in
                    guard let typed = error as? ControlCommandError else {
                        XCTFail("\(id): unexpected error \(error)")
                        return
                    }
                    switch expectedError {
                    case "unknown_opcode":
                        guard case .unknownOpcode = typed else {
                            XCTFail("\(id): expected unknown_opcode, got \(typed)")
                            return
                        }
                        XCTAssertEqual(expectedLastError.intValue, 1, "\(id): last_error mapping")
                    case "bad_length":
                        guard case .badLength = typed else {
                            XCTFail("\(id): expected bad_length, got \(typed)")
                            return
                        }
                        XCTAssertEqual(expectedLastError.intValue, 2, "\(id): last_error mapping")
                    default:
                        XCTFail("\(id): unknown expect.error \(expectedError)")
                    }
                }
            }
        }
    }

    private func makeCommand(_ json: [String: Any], id: String) throws -> ControlCommand {
        let opcode = try XCTUnwrap(json["opcode"] as? String, "\(id): command.opcode")
        switch opcode {
        case "START":
            return .start(intervalMilliseconds: try number(json, "interval_ms").uint16Value)
        case "STOP":
            return .stop
        case "SET_INTERVAL":
            return .setInterval(intervalMilliseconds: try number(json, "interval_ms").uint16Value)
        case "REQUEST_FIX":
            return .requestFix
        case "SET_EXTENDED":
            return .setExtended(enabled: try XCTUnwrap(json["enabled"] as? Bool, "\(id): enabled"))
        case "RESET":
            return .reset
        default:
            throw VectorError.malformed("\(id): unknown opcode \(opcode)")
        }
    }

    private func opcodeName(_ command: ControlCommand) -> String {
        switch command {
        case .start: return "START"
        case .stop: return "STOP"
        case .setInterval: return "SET_INTERVAL"
        case .requestFix: return "REQUEST_FIX"
        case .setExtended: return "SET_EXTENDED"
        case .reset: return "RESET"
        }
    }

    private func rawInterval(_ command: ControlCommand) -> UInt16? {
        switch command {
        case .start(let interval), .setInterval(let interval): return interval
        case .stop, .requestFix, .setExtended, .reset: return nil
        }
    }

    private func extendedEnabled(_ command: ControlCommand) -> Bool? {
        if case .setExtended(let enabled) = command { return enabled }
        return nil
    }

    // MARK: - Sequence scenarios

    func testSequenceVectors() throws {
        let root = try loadJSON("sequences")
        let scenarios = try XCTUnwrap(root["scenarios"] as? [[String: Any]])
        XCTAssertFalse(scenarios.isEmpty)

        for scenario in scenarios {
            let id = try XCTUnwrap(scenario["id"] as? String)
            let packets = try XCTUnwrap(scenario["packets"] as? [[String: Any]])
            let expect = try XCTUnwrap(scenario["expect"] as? [String: Any])
            let accepted = try XCTUnwrap(bools(expect["accepted"]), "\(id): accepted")
            let statuses = try XCTUnwrap(expect["sequence_status"] as? [String], "\(id): sequence_status")
            XCTAssertEqual(packets.count, statuses.count, "\(id): packet/status count")

            var tracker = SequenceTracker()
            for (index, packetJSON) in packets.enumerated() {
                let data = bytes(from: try XCTUnwrap(packetJSON["hex"] as? String, "\(id)[\(index)]: hex"))
                do {
                    let packet = try LocationPacket.decode(data)
                    XCTAssertTrue(accepted[index], "\(id)[\(index)]: expected rejected but decoded")
                    XCTAssertEqual(
                        sequenceStatus(tracker.observe(packet.sequence)),
                        statuses[index],
                        "\(id)[\(index)]: sequence status"
                    )
                } catch {
                    XCTAssertFalse(accepted[index], "\(id)[\(index)]: decode failed: \(error)")
                }
            }
        }
    }

    private func sequenceStatus(_ observation: SequenceObservation) -> String {
        switch observation {
        case .first: return "first"
        case .inOrder: return "ok"
        case .jumpedForward: return "gap"
        case .duplicate: return "duplicate"
        case .rewound: return "regression"
        }
    }
}
