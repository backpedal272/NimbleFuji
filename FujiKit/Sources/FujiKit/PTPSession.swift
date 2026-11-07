// FujiKit — Swift port of fujicli's fujicore::ptp::Ptp.
// Copyright © Nikolaos Karaolidis (fujicli) and Nimble Fuji contributors.
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

public enum PTPError: Error, CustomStringConvertible {
    case response(operation: UInt16, code: UInt16)
    case malformed(String)

    public var description: String {
        switch self {
        case let .response(op, code):
            "camera rejected operation 0x\(String(op, radix: 16)): \(PTPResponse.name(code))"
        case let .malformed(message):
            "malformed PTP container: \(message)"
        }
    }
}

/// A PTP session: command / data / response transactions over a transport.
public final class PTPSession {
    static let headerSize = 12

    private let transport: PTPTransport
    /// Largest single bulk transfer (fujicli: 16128 KiB for the X-T5).
    private let chunkSize: Int
    private(set) var transactionID: UInt32 = 0
    private var isOpen = false

    public init(transport: PTPTransport, chunkSize: Int) {
        self.transport = transport
        self.chunkSize = chunkSize
    }

    // MARK: Transactions

    /// Runs one transaction and returns the data phase sent by the camera (empty if none).
    @discardableResult
    public func send(_ operation: PTPOperation, _ params: [UInt32] = [], data: Data? = nil) throws -> Data {
        let tid = transactionID
        defer { transactionID &+= 1 }

        var payload = PTPWriter()
        params.forEach { payload.u32($0) }
        try write(.command, code: operation.rawValue, payload: payload.data, transactionID: tid)
        if let data {
            try write(.data, code: operation.rawValue, payload: data, transactionID: tid)
        }

        var result = Data()
        while true {
            let (type, code, _, body) = try readContainer()
            switch type {
            case PTPContainerType.data.rawValue:
                result = body
            case PTPContainerType.response.rawValue:
                guard code == PTPResponse.ok else {
                    throw PTPError.response(operation: operation.rawValue, code: code)
                }
                return result
            default:
                continue // events and unknown containers are ignored, as in fujicli
            }
        }
    }

    private func write(_ type: PTPContainerType, code: UInt16, payload: Data, transactionID: UInt32) throws {
        var header = PTPWriter()
        header.u32(UInt32(Self.headerSize + payload.count))
        header.u16(type.rawValue)
        header.u16(code)
        header.u32(transactionID)

        // First transfer carries the header plus as much payload as fits; the rest follows in chunks.
        let firstLength = min(payload.count, chunkSize - Self.headerSize)
        var first = header.data
        first.append(payload.prefix(firstLength))
        try transport.write(first)

        var offset = payload.startIndex + firstLength
        while offset < payload.endIndex {
            let end = min(offset + chunkSize, payload.endIndex)
            try transport.write(payload[offset..<end])
            offset = end
        }
    }

    private func readContainer() throws -> (type: UInt16, code: UInt16, transactionID: UInt32, payload: Data) {
        let first = try transport.read(maxLength: 8 * 1024)
        var reader = PTPReader(first)
        guard first.count >= Self.headerSize else {
            throw PTPError.malformed("got \(first.count) bytes, expected at least a 12-byte header")
        }
        let total = Int(try reader.u32())
        let type = try reader.u16()
        let code = try reader.u16()
        let tid = try reader.u32()
        guard total >= Self.headerSize else { throw PTPError.malformed("container length \(total) is below the header size") }

        let payloadLength = total - Self.headerSize
        var payload = Data(capacity: payloadLength)
        payload.append(first.dropFirst(Self.headerSize))
        while payload.count < payloadLength {
            let chunk = try transport.read(maxLength: min(payloadLength - payload.count, chunkSize))
            if chunk.isEmpty { break }
            payload.append(chunk)
        }
        return (type, code, tid, payload.prefix(payloadLength))
    }

    // MARK: Session

    public func open(sessionID: UInt32 = 1) throws {
        try send(.openSession, [sessionID])
        isOpen = true
    }

    public func close() {
        guard isOpen else { return }
        _ = try? send(.closeSession)
        isOpen = false
    }

    public func deviceInfo() throws -> PTPDeviceInfo {
        try PTPDeviceInfo(data: try send(.getDeviceInfo))
    }

    // MARK: Device properties

    public func getProperty(_ code: UInt16) throws -> Data {
        try send(.getDevicePropValue, [UInt32(code)])
    }

    public func setProperty(_ code: UInt16, _ value: Data) throws {
        try send(.setDevicePropValue, [UInt32(code)], data: value)
    }

    public func getU16(_ code: UInt16) throws -> UInt16 {
        var r = PTPReader(try getProperty(code))
        return try r.u16()
    }

    public func setU16(_ code: UInt16, _ value: UInt16) throws {
        var w = PTPWriter()
        w.u16(value)
        try setProperty(code, w.data)
    }
}
