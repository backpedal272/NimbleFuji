// FujiKit — camera-level operations, ported from fujicli's fujicore::Camera and its
// render / backup / simulation managers.
// Copyright © Nikolaos Karaolidis (fujicli) and Nimble Fuji contributors.
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// An open PTP session with a supported Fujifilm camera. Not thread-safe: use from one thread or actor.
public final class FujiCamera {
    public let descriptor: USBCameraDescriptor
    public let model: CameraModel
    let ptp: PTPSession
    private let transport: PTPTransport

    /// Opens the first supported camera, or a specific one.
    public init(_ descriptor: USBCameraDescriptor? = nil) throws {
        let found = descriptor ?? IOUSBHostTransport.cameras().first { $0.model != nil }
        guard let found else { throw FujiUSBError.noCamera }
        guard let model = found.model else { throw FujiKitError.unsupportedCamera(found.description) }
        let transport = try IOUSBHostTransport(camera: found)
        self.descriptor = found
        self.model = model
        self.transport = transport
        self.ptp = PTPSession(transport: transport, chunkSize: model.chunkSize)
        try ptp.open()
    }

    /// For tests: a camera over any transport.
    init(transport: PTPTransport, model: CameraModel = .xt5) throws {
        self.descriptor = USBCameraDescriptor(vendorID: IOUSBHostTransport.fujifilmVendorID, productID: model.productID, locationID: 0, model: model)
        self.model = model
        self.transport = transport
        self.ptp = PTPSession(transport: transport, chunkSize: model.chunkSize)
        try ptp.open()
    }

    deinit {
        ptp.close()
    }

    public static func connected() -> [USBCameraDescriptor] { IOUSBHostTransport.cameras() }

    // MARK: Info

    public func deviceInfo() throws -> PTPDeviceInfo { try ptp.deviceInfo() }

    /// 6 is USB RAW CONV./BACKUP RESTORE.
    public func usbMode() throws -> UInt16 { try ptp.getU16(FujiProperty.usbMode.rawValue) }

    public var isInRawConversionMode: Bool { (try? usbMode()) == 6 }

    // MARK: Slots

    private func select(slot: Int) throws {
        guard (1...model.slots).contains(slot) else { throw FujiKitError.invalidSlot(slot) }
        try ptp.setU16(FujiProperty.customSetting.rawValue, UInt16(slot))
    }

    public func slotName(_ slot: Int) throws -> String {
        try select(slot: slot)
        return try ptp.getString(FujiProperty.customSettingName.rawValue)
    }

    public func readSlot(_ slot: Int) throws -> CameraSettings {
        try select(slot: slot)
        return try SlotIO.read(ptp)
    }

    /// Writes the settings that are present into a slot.
    public func writeSlot(_ slot: Int, _ settings: CameraSettings) throws {
        try SlotIO.validate(settings)
        try select(slot: slot)
        try SlotIO.write(settings, ptp)
    }

    // MARK: Backup

    /// The camera's full settings backup.
    public func exportBackup() throws -> Data {
        try ptp.send(.getObjectInfo, [0])
        return try ptp.send(.getObject, [0])
    }

    public func importBackup(_ backup: Data) throws {
        let info = PTPObjectInfo(format: .fujiBackup, compressedSize: UInt32(backup.count))
        try ptp.send(.sendObjectInfo, [0, 0], data: info.encoded())
        try ptp.send(.sendObject, [0], data: backup)
    }

    // MARK: Render

    /// Renders a RAF on the camera's image processor. Settings in `changes` are applied
    /// over the RAW's as-shot settings; the result is a JPEG unless `fileType` says otherwise.
    public func render(raf: Data, changes: CameraSettings, draft: Bool = false,
                       progress: ((String) -> Void)? = nil) throws -> Data {
        progress?("Sending RAW to camera")
        let info = PTPObjectInfo(format: .fujiRAF, compressedSize: UInt32(raf.count), filename: "FUP_FILE.dat")
        try ptp.send(.fujiSendObjectInfo, [0, 0, 0], data: info.encoded())
        try ptp.send(.fujiSendObject, data: raf)

        progress?("Applying settings")
        let current = try readRenderProfile()
        let next = try current.applying(changes)
        try ptp.setProperty(FujiProperty.rawConversionProfile.rawValue, next.encoded())

        progress?("Rendering")
        try ptp.setU16(FujiProperty.rawConversionRun.rawValue, draft ? 0 : 1)
        var handle: UInt32?
        let deadline = Date().addingTimeInterval(120)
        while handle == nil {
            var r = PTPReader(try ptp.send(.getObjectHandles, [UInt32.max, 0, 0]))
            handle = try r.u32Array().first
            if handle == nil {
                guard Date() < deadline else { throw FujiKitError.renderTimedOut }
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
        progress?("Downloading result")
        let image = try ptp.send(.getObject, [handle!])
        _ = try? ptp.send(.deleteObject, [handle!])
        return image
    }

    /// Raw bytes of the RAW conversion profile property, for debugging.
    public func readRenderProfileData() throws -> Data {
        try ptp.getProperty(FujiProperty.rawConversionProfile.rawValue)
    }

    /// The RAW conversion profile currently loaded (after sending a RAF: its as-shot settings).
    public func readRenderProfile() throws -> RenderProfile {
        try RenderProfile(data: try ptp.getProperty(FujiProperty.rawConversionProfile.rawValue),
                          expectedCode: model.renderProfileCode)
    }
}
