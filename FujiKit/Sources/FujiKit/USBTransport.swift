// FujiKit — USB bulk transport over IOUSBHost (replaces fujicli's libusb/rusb layer).
// Copyright © Nikolaos Karaolidis (fujicli) and Nimble Fuji contributors.
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import IOKit
import IOUSBHost

public enum FujiUSBError: Error, CustomStringConvertible {
    case noCamera
    case noImagingInterface
    case missingEndpoints
    case transfer(String, underlying: Error)

    public var description: String {
        switch self {
        case .noCamera: "no supported camera found"
        case .noImagingInterface: "the camera has no PTP imaging interface (is it in USB RAW CONV./BACKUP RESTORE mode?)"
        case .missingEndpoints: "the camera's PTP interface has no bulk endpoints"
        case let .transfer(what, error): "USB \(what) failed: \((error as NSError).localizedDescription)"
        }
    }
}

/// Moves raw bytes to and from the camera. Abstracted so PTP can be tested without hardware.
public protocol PTPTransport: AnyObject {
    /// Writes one bulk transfer.
    func write(_ data: Data) throws
    /// Reads one bulk transfer of at most `maxLength` bytes.
    func read(maxLength: Int) throws -> Data
}

/// A Fujifilm camera found on USB.
public struct USBCameraDescriptor: Sendable, Hashable, CustomStringConvertible {
    public let vendorID: UInt16
    public let productID: UInt16
    public let locationID: UInt32
    public let model: CameraModel?

    public var description: String {
        let name = model?.name ?? "Unknown Fujifilm camera"
        return String(format: "%@ (%04x:%04x) (location 0x%08x)", name, vendorID, productID, locationID)
    }
}

public final class IOUSBHostTransport: PTPTransport {
    public static let fujifilmVendorID: UInt16 = 0x04CB

    private let interface: IOUSBHostInterface
    private let bulkIn: IOUSBHostPipe
    private let bulkOut: IOUSBHostPipe
    /// 0 waits forever, like fujicli. Renders can take a few seconds per image.
    public var timeout: TimeInterval = 0

    /// Lists connected Fujifilm cameras.
    public static func cameras() -> [USBCameraDescriptor] {
        // USB matching rules don't accept a vendor ID on its own, so list every device and filter.
        let matching = IOServiceMatching("IOUSBHostDevice")
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var result: [USBCameraDescriptor] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            func number(_ key: String) -> UInt32? {
                (IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? NSNumber)?.uint32Value
            }
            guard number("idVendor") == UInt32(fujifilmVendorID), let product = number("idProduct") else { continue }
            let pid = UInt16(truncatingIfNeeded: product)
            result.append(USBCameraDescriptor(
                vendorID: fujifilmVendorID, productID: pid,
                locationID: number("locationID") ?? 0,
                model: CameraModel.supported.first { $0.productID == pid }))
        }
        return result
    }

    /// Opens the PTP (still image, class 6) interface of `camera`.
    public init(camera: USBCameraDescriptor) throws {
        // List every USB interface and pick this camera's still-image (PTP) one.
        let matching = IOServiceMatching("IOUSBHostInterface")
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            throw FujiUSBError.noImagingInterface
        }
        defer { IOObjectRelease(iterator) }

        var opened: IOUSBHostInterface?
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            func number(_ key: String) -> Int? {
                (IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? NSNumber)?.intValue
            }
            guard number("idVendor") == Int(camera.vendorID), number("idProduct") == Int(camera.productID),
                  number("bInterfaceClass") == 6 else { continue }
            if camera.locationID != 0, let location = number("locationID"), location != Int(camera.locationID) { continue }
            do {
                opened = try IOUSBHostInterface(__ioService: service, options: [], queue: nil, interestHandler: nil)
            } catch {
                throw FujiUSBError.transfer("opening the camera", underlying: error)
            }
            break
        }
        guard let interface = opened else { throw FujiUSBError.noImagingInterface }
        self.interface = interface

        var bulkIn: IOUSBHostPipe?, bulkOut: IOUSBHostPipe?
        var current = UnsafeRawPointer(interface.interfaceDescriptor).assumingMemoryBound(to: IOUSBDescriptorHeader.self)
        while let endpoint = IOUSBGetNextEndpointDescriptor(interface.configurationDescriptor, interface.interfaceDescriptor, current) {
            let address = endpoint.pointee.bEndpointAddress
            if endpoint.pointee.bmAttributes & 0x03 == 0x02 { // bulk
                let pipe = try interface.copyPipe(withAddress: Int(address))
                if address & 0x80 != 0 { bulkIn = bulkIn ?? pipe } else { bulkOut = bulkOut ?? pipe }
            }
            current = UnsafeRawPointer(endpoint).assumingMemoryBound(to: IOUSBDescriptorHeader.self)
        }
        guard let bulkIn, let bulkOut else {
            interface.destroy()
            throw FujiUSBError.missingEndpoints
        }
        self.bulkIn = bulkIn
        self.bulkOut = bulkOut
    }

    deinit {
        interface.destroy()
    }

    public func write(_ data: Data) throws {
        let buffer = NSMutableData(data: data)
        var transferred = 0
        do {
            try bulkOut.__sendIORequest(with: buffer, bytesTransferred: &transferred, completionTimeout: timeout)
        } catch {
            throw FujiUSBError.transfer("write", underlying: error)
        }
    }

    public func read(maxLength: Int) throws -> Data {
        guard let buffer = NSMutableData(length: maxLength) else { return Data() }
        var transferred = 0
        do {
            try bulkIn.__sendIORequest(with: buffer, bytesTransferred: &transferred, completionTimeout: timeout)
        } catch {
            throw FujiUSBError.transfer("read", underlying: error)
        }
        return Data(bytes: buffer.bytes, count: transferred)
    }
}
