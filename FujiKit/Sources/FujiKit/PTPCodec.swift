// FujiKit — Swift port of fujicli's ptp-cursor crate.
// Copyright © Nikolaos Karaolidis (fujicli) and Nimble Fuji contributors.
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

public enum PTPCodecError: Error, CustomStringConvertible, Equatable {
    case unexpectedEnd(needed: Int, offset: Int)
    case invalidUTF16
    case invalidValue(String)

    public var description: String {
        switch self {
        case let .unexpectedEnd(needed, offset): "PTP data ended early: needed \(needed) bytes at offset \(offset)"
        case .invalidUTF16: "PTP string is not valid UTF-16"
        case let .invalidValue(message): message
        }
    }
}

/// Little-endian PTP serializer.
public struct PTPWriter {
    public private(set) var data = Data()

    public init() {}

    public mutating func u8(_ v: UInt8) { data.append(v) }
    public mutating func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
    public mutating func i16(_ v: Int16) { u16(UInt16(bitPattern: v)) }
    public mutating func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
    public mutating func i32(_ v: Int32) { u32(UInt32(bitPattern: v)) }
    public mutating func bytes(_ d: Data) { data.append(d) }
    public mutating func zeros(_ count: Int) { data.append(Data(count: count)) }

    /// PTP string: UInt8 character count including the terminator, UTF-16LE, then 0x0000.
    /// The empty string is a single 0 byte.
    public mutating func string(_ s: String) {
        guard !s.isEmpty else { return u8(0) }
        let units = Array(s.utf16)
        u8(UInt8(truncatingIfNeeded: units.count + 1))
        units.forEach { u16($0) }
        u16(0)
    }

    /// Fujifilm "exact" string: character count without a terminator, no trailing 0x0000.
    public mutating func exactString(_ s: String) {
        guard !s.isEmpty else { return u8(0) }
        let units = Array(s.utf16)
        u8(UInt8(truncatingIfNeeded: units.count))
        units.forEach { u16($0) }
    }

    public mutating func u32Array(_ values: [UInt32]) {
        u32(UInt32(values.count))
        values.forEach { u32($0) }
    }
}

/// Little-endian PTP deserializer.
public struct PTPReader {
    public let data: Data
    public private(set) var offset: Int

    public init(_ data: Data) {
        self.data = data
        self.offset = data.startIndex
    }

    public var remaining: Int { data.endIndex - offset }
    public var isAtEnd: Bool { remaining == 0 }

    private mutating func take(_ n: Int) throws -> Data {
        guard remaining >= n else { throw PTPCodecError.unexpectedEnd(needed: n, offset: offset - data.startIndex) }
        defer { offset += n }
        return data[offset..<offset + n]
    }

    private mutating func integer<T: FixedWidthInteger>(_: T.Type) throws -> T {
        let bytes = try take(MemoryLayout<T>.size)
        var value: T = 0
        for (i, byte) in bytes.enumerated() { value |= T(byte) << (8 * i) }
        return value
    }

    public mutating func u8() throws -> UInt8 { try integer(UInt8.self) }
    public mutating func u16() throws -> UInt16 { try integer(UInt16.self) }
    public mutating func i16() throws -> Int16 { Int16(bitPattern: try u16()) }
    public mutating func u32() throws -> UInt32 { try integer(UInt32.self) }
    public mutating func i32() throws -> Int32 { Int32(bitPattern: try u32()) }
    public mutating func bytes(_ n: Int) throws -> Data { try take(n) }
    public mutating func skip(_ n: Int) throws { _ = try take(n) }

    public mutating func string() throws -> String {
        let count = Int(try u8())
        guard count > 0 else { return "" }
        var units: [UInt16] = []
        for _ in 0..<(count - 1) { units.append(try u16()) }
        _ = try u16() // terminator
        return String(decoding: units, as: UTF16.self)
    }

    public mutating func exactString() throws -> String {
        let count = Int(try u8())
        var units: [UInt16] = []
        for _ in 0..<count { units.append(try u16()) }
        return String(decoding: units, as: UTF16.self)
    }

    public mutating func u16Array() throws -> [UInt16] {
        let n = Int(try u32())
        return try (0..<n).map { _ in try u16() }
    }

    public mutating func u32Array() throws -> [UInt32] {
        let n = Int(try u32())
        return try (0..<n).map { _ in try u32() }
    }
}
