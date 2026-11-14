//
//  SequenceTracker.swift
//  P2PGPSProtocol
//
//  P2P GPS — sequence-number continuity tracking.
//  Copyright (C) 2026 haruki0420 and contributors
//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  Spec §3.3 rule 6: a rewound sequence is logged but the packet itself is
//  accepted (the link is lossy and reorder-tolerant, and a sender restart is
//  not an error). This type only classifies what happened; it never rejects.
//

import Foundation

/// What a newly received sequence number means relative to the previous one.
public enum SequenceObservation: Equatable, Sendable {
    /// The first packet from this sender.
    case first
    /// Exactly the next sequence number (including the 65535 → 0 wrap).
    case inOrder
    /// Skipped one or more sequence numbers (packets were lost).
    case jumpedForward(by: Int)
    /// The same sequence number as the previous packet (duplicate notify).
    case duplicate
    /// The sequence number went backwards (sender restarted or reordered).
    case rewound(by: Int)
}

/// Tracks the sequence number of one sender.
///
/// The half-range rule (a delta greater than 32768 is treated as a rewind) is
/// what makes the 16-bit wrap unambiguous: 65535 → 0 is a forward step of 1,
/// while 0 → 65535 is a rewind of 1.
public struct SequenceTracker: Sendable {
    /// The last sequence number observed, or `nil` before the first packet.
    public private(set) var lastSequence: UInt16?
    /// Number of packets observed.
    public private(set) var observedCount: Int = 0
    /// Number of rewinds observed (spec §3.3 rule 6: log these).
    public private(set) var rewindCount: Int = 0
    /// Number of forward gaps observed (packets lost).
    public private(set) var gapCount: Int = 0

    public init() {}

    /// Classifies `sequence` and records it as the new last value.
    @discardableResult
    public mutating func observe(_ sequence: UInt16) -> SequenceObservation {
        defer {
            lastSequence = sequence
            observedCount += 1
        }

        guard let previous = lastSequence else {
            return .first
        }

        let delta = (Int(sequence) - Int(previous) + 65_536) % 65_536
        switch delta {
        case 0:
            return .duplicate
        case 1:
            return .inOrder
        case 2...32_768:
            gapCount += 1
            return .jumpedForward(by: delta - 1)
        default:
            rewindCount += 1
            return .rewound(by: 65_536 - delta)
        }
    }

    /// Forgets the last sequence number (e.g. after reconnecting).
    public mutating func reset() {
        lastSequence = nil
    }
}
