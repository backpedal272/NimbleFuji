// FujiKit — Swift port of fujicli's fujicore PTP types.
// Copyright © Nikolaos Karaolidis (fujicli) and Nimble Fuji contributors.
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

public enum PTPOperation: UInt16, Sendable {
    case getDeviceInfo = 0x1001
    case openSession = 0x1002
    case closeSession = 0x1003
    case getObjectHandles = 0x1007
    case getObjectInfo = 0x1008
    case getObject = 0x1009
    case deleteObject = 0x100B
    case sendObjectInfo = 0x100C
    case sendObject = 0x100D
    case getDevicePropValue = 0x1015
    case setDevicePropValue = 0x1016
    case fujiSendObjectInfo = 0x900C
    case fujiSendObject = 0x900D
}

public enum PTPContainerType: UInt16, Sendable {
    case command = 1, data = 2, response = 3, event = 4
}

/// PTP response codes (only Ok is expected; the rest give readable errors).
public enum PTPResponse {
    public static let ok: UInt16 = 0x2001

    public static func name(_ code: UInt16) -> String {
        let names: [UInt16: String] = [
            0x2002: "GeneralError", 0x2003: "SessionNotOpen", 0x2004: "InvalidTransactionId",
            0x2005: "OperationNotSupported", 0x2006: "ParameterNotSupported", 0x2007: "IncompleteTransfer",
            0x2008: "InvalidStorageId", 0x2009: "InvalidObjectHandle", 0x200A: "DevicePropNotSupported",
            0x200B: "InvalidObjectFormatCode", 0x200C: "StoreFull", 0x200D: "ObjectWriteProtected",
            0x200E: "StoreReadOnly", 0x200F: "AccessDenied", 0x2010: "NoThumbnailPresent",
            0x2011: "SelfTestFailed", 0x2012: "PartialDeletion", 0x2013: "StoreNotAvailable",
            0x2014: "SpecificationByFormatUnsupported", 0x2015: "NoValidObjectInfo", 0x2016: "InvalidCodeFormat",
            0x2017: "UnknownVendorCode", 0x2018: "CaptureAlreadyTerminated", 0x2019: "DeviceBusy",
            0x201A: "InvalidParentObject", 0x201B: "InvalidDevicePropFormat", 0x201C: "InvalidDevicePropValue",
            0x201D: "InvalidParameter", 0x201E: "SessionAlreadyOpen", 0x201F: "TransactionCancelled",
            0x2020: "SpecificationOfDestinationUnsupported",
        ]
        return "\(names[code] ?? "Unknown") (0x\(String(code, radix: 16)))"
    }
}

public enum PTPObjectFormat: UInt16, Sendable {
    case none = 0x0000
    case fujiBackup = 0x5000
    case fujiRAF = 0xF802
}

/// Fujifilm vendor device properties used by FujiKit.
public enum FujiProperty: UInt16, Sendable {
    case usbMode = 0xD16E
    case rawConversionRun = 0xD183
    case rawConversionProfile = 0xD185
    case customSetting = 0xD18C
    case customSettingName = 0xD18D
    case batteryInfo = 0xD36B
}

public struct PTPDeviceInfo: Sendable, Codable {
    public var standardVersion: UInt16
    public var vendorExtensionID: UInt32
    public var vendorExtensionVersion: UInt16
    public var vendorExtensionDescription: String
    public var functionalMode: UInt16
    public var operationsSupported: [UInt16]
    public var eventsSupported: [UInt16]
    public var devicePropertiesSupported: [UInt16]
    public var captureFormats: [UInt16]
    public var imageFormats: [UInt16]
    public var manufacturer: String
    public var model: String
    public var deviceVersion: String
    public var serialNumber: String

    public init(data: Data) throws {
        var r = PTPReader(data)
        standardVersion = try r.u16()
        vendorExtensionID = try r.u32()
        vendorExtensionVersion = try r.u16()
        vendorExtensionDescription = try r.string()
        functionalMode = try r.u16()
        operationsSupported = try r.u16Array()
        eventsSupported = try r.u16Array()
        devicePropertiesSupported = try r.u16Array()
        captureFormats = try r.u16Array()
        imageFormats = try r.u16Array()
        manufacturer = try r.string()
        model = try r.string()
        deviceVersion = try r.string()
        serialNumber = try r.string()
    }
}

/// PTP ObjectInfo dataset; only format, size and filename are used by Fujifilm transfers.
public struct PTPObjectInfo: Sendable {
    public var storageID: UInt32 = 0
    public var format: PTPObjectFormat = .none
    public var protectionStatus: UInt16 = 0
    public var compressedSize: UInt32 = 0
    public var filename = ""

    public init(format: PTPObjectFormat, compressedSize: UInt32, filename: String = "") {
        self.format = format
        self.compressedSize = compressedSize
        self.filename = filename
    }

    public func encoded() -> Data {
        var w = PTPWriter()
        w.u32(storageID)
        w.u16(format.rawValue)
        w.u16(protectionStatus)
        w.u32(compressedSize)
        w.u16(0)           // thumb format
        w.u32(0)           // thumb compressed size
        w.u32(0); w.u32(0) // thumb width, height
        w.u32(0); w.u32(0) // image width, height
        w.u32(0)           // image bit depth
        w.u32(0)           // parent object
        w.u16(0)           // association type
        w.u32(0)           // association description
        w.u32(0)           // sequence number
        w.string(filename)
        w.string("")       // date created
        w.string("")       // date modified
        w.string("")       // keywords
        return w.data
    }
}
