//
//  LogStore.swift
//  P2PGPSCore
//
//  P2P GPS — in-app diagnostic log.
//  Copyright (C) 2026 haruki0420 and contributors
//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  The log is memory-only: nothing is written to disk, because a persistent
//  plain-text record of device interactions is exactly what a location-hiding
//  app must not leave behind (TLocation removed its FFI file logger for the same
//  reason). Coordinates are rounded before they are logged (spec §8).
//

import Foundation

/// Severity of a log entry.
public enum LogLevel: String, Sendable, CaseIterable {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"

    /// SF Symbol name used by the diagnostics screen.
    public var symbolName: String {
        switch self {
        case .debug: return "ladybug"
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.octagon"
        }
    }
}

/// One log line.
public struct LogEntry: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let level: LogLevel
    public let message: String

    public init(id: UUID = UUID(), timestamp: Date = Date(), level: LogLevel, message: String) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.message = message
    }
}

/// Thread-safe, memory-only log with an `ObservableObject` mirror for SwiftUI.
public final class LogStore: ObservableObject, @unchecked Sendable {
    public static let shared = LogStore()

    /// Entries published to the UI. Mutated on the main thread only.
    @Published public private(set) var entries: [LogEntry] = []
    /// Number of error-level entries currently retained.
    @Published public private(set) var errorCount: Int = 0

    private let lock = NSLock()
    private var storage: [LogEntry] = []
    private let maximumEntries: Int

    public init(maximumEntries: Int = 1_000) {
        self.maximumEntries = maximumEntries
    }

    /// Appends a line. Safe to call from any thread.
    public func log(_ message: String, level: LogLevel = .info) {
        let entry = LogEntry(level: level, message: message)

        lock.lock()
        storage.append(entry)
        if storage.count > maximumEntries {
            storage.removeFirst(storage.count - maximumEntries)
        }
        let snapshot = storage
        lock.unlock()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.entries = snapshot
            self.errorCount = snapshot.reduce(into: 0) { count, entry in
                if entry.level == .error { count += 1 }
            }
        }
    }

    public func debug(_ message: String) { log(message, level: .debug) }
    public func info(_ message: String) { log(message, level: .info) }
    public func warning(_ message: String) { log(message, level: .warning) }
    public func error(_ message: String) { log(message, level: .error) }

    /// Logs a coordinate at the user's configured precision (spec §8).
    public func logCoordinate(
        _ label: String,
        latitude: Double,
        longitude: Double,
        decimalPlaces: Int = 5
    ) {
        let text = Self.roundedCoordinate(latitude: latitude, longitude: longitude, decimalPlaces: decimalPlaces)
        log("\(label): \(text)", level: .debug)
    }

    /// Rounds a coordinate for logging / display.
    ///
    /// The format locale is pinned to `en_US_POSIX` so the decimal separator is
    /// always "." regardless of the device locale (review L-18).
    public static func roundedCoordinate(
        latitude: Double,
        longitude: Double,
        decimalPlaces: Int
    ) -> String {
        let places = min(max(decimalPlaces, 0), 7)
        return String(
            format: "%.\(places)f, %.\(places)f",
            locale: Locale(identifier: "en_US_POSIX"),
            arguments: [latitude, longitude]
        )
    }

    /// A snapshot that does not depend on the main-thread publish loop.
    public func snapshot() -> [LogEntry] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    /// Removes every entry.
    public func clear() {
        lock.lock()
        storage.removeAll()
        lock.unlock()
        DispatchQueue.main.async { [weak self] in
            self?.entries = []
            self?.errorCount = 0
        }
    }

    /// A plain-text rendering for the share sheet / diagnostics export.
    public func exportText() -> String {
        let formatter = ISO8601DateFormatter()
        return snapshot()
            .map { "\(formatter.string(from: $0.timestamp)) [\($0.level.rawValue)] \($0.message)" }
            .joined(separator: "\n")
    }
}
