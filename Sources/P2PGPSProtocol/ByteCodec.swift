//
//  ByteCodec.swift
//  P2PGPSProtocol
//
//  P2P GPS — little-endian byte helpers shared by every packet type.
//  Copyright (C) 2026 haruki0420 and contributors
//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  Spec §2: every multi-byte integer is little-endian, signed integers are
//  two's complement, and floating point is never used on the wire.
//

import Foundation

/// Little-endian read/write helpers for the fixed-size wire formats.
///
/// `Data`'s own integer accessors are big-endian oriented, so every field is
/// read and written explicitly here. The helpers are internal: packets expose
/// only their documented `encode`/`decode` API.
enum ByteCodec {
    /// Appends `value` in little-endian order.
    static func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        withUnsafeBytes(of: value.littleEndian) { buffer in
            data.append(contentsOf: buffer)
        }
    }

    /// Reads a little-endian integer of type `T` at `offset`.
    ///
    /// The caller is responsible for bounds checking; every packet decoder
    /// validates the exact packet length before reading a single field.
    static func read<T: FixedWidthInteger>(_ type: T.Type, from data: Data, at offset: Int) -> T {
        data.withUnsafeBytes { raw in
            T(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: T.self))
        }
    }

    /// Replaces the little-endian integer of type `T` at `offset` in `data`.
    static func write<T: FixedWidthInteger>(_ value: T, to data: inout Data, at offset: Int) {
        withUnsafeBytes(of: value.littleEndian) { buffer in
            data.replaceSubrange(offset..<(offset + buffer.count), with: buffer)
        }
    }

    /// Lowercase hexadecimal rendering, used by the diagnostics screen and logs.
    static func hexString(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
