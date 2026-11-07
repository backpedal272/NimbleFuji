// FujiKit — X-T5 settings tables, hand-ported from fujicli's FML definitions
// (fml/option.cue, fml/camera.cue at fujicli commit 6366cff).
// Copyright © Nikolaos Karaolidis (fujicli) and Nimble Fuji contributors.
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

public enum FujiKitError: Error, CustomStringConvertible, Equatable {
    /// A combination the camera doesn't allow; messages match fujicli's.
    case rule(String)
    case unknownWireValue(field: String, value: Int)
    case unsupportedValue(field: String, value: String)
    case unsupportedCamera(String)
    case invalidSlot(Int)
    case renderTimedOut

    public var description: String {
        switch self {
        case let .rule(message): "invalid simulation: \(message)"
        case let .unknownWireValue(field, value): "camera reported unknown \(field) value \(value) (0x\(String(value, radix: 16)))"
        case let .unsupportedValue(field, value): "unsupported \(field) value “\(value)”"
        case let .unsupportedCamera(name): "\(name) isn't supported"
        case let .invalidSlot(n): "slot C\(n) doesn't exist on this camera"
        case .renderTimedOut: "the camera didn't produce a rendered image"
        }
    }
}

public struct CameraModel: Sendable, Hashable {
    public let name: String
    public let productID: UInt16
    public let slots: Int
    /// Largest single USB bulk transfer, from fujicli's camera definition.
    public let chunkSize: Int
    public let renderProfileCode: UInt32

    public static let xt5 = CameraModel(name: "FUJIFILM X-T5", productID: 0x02FC, slots: 7,
                                        chunkSize: 16128 * 1024, renderProfileCode: 0xFF17_9502)
    public static let supported: [CameraModel] = [.xt5]
}

/// Settings as fujicli names them (`fujicli --json simulation get` / `simulation export`),
/// so files and outputs are interchangeable between the two tools.
/// Every field is optional: absent means “keep the camera's / photo's value”.
public struct CameraSettings: Codable, Equatable, Sendable {
    public var customSettingName: String?
    public var fileType: String?             // render only
    public var imageSize: String?
    public var imageQuality: String?
    public var exposureOffset: Double?       // render only, EV
    public var filmSimulation: String?
    public var monochromaticColorTemperature: Int?
    public var monochromaticColorTint: Int?
    public var grainEffect: String?
    public var colorChromeEffect: String?
    public var colorChromeFxBlue: String?
    public var whiteBalance: String?
    public var whiteBalanceShiftRed: Int?
    public var whiteBalanceShiftBlue: Int?
    public var whiteBalanceTemperature: Int?
    public var highlightTone: Double?
    public var shadowTone: Double?
    public var color: Int?
    public var sharpness: Int?
    public var noiseReduction: Int?
    public var clarity: Int?
    public var lensModulationOptimizer: String?
    public var colorSpace: String?
    public var dynamicRange: String?
    public var dynamicRangePriority: String?
    public var smoothSkinEffect: String?
    public var teleconverter: String?        // render only

    public init() {}
}

/// Wire encodings for every X-T5 setting.
enum XT5 {
    // Device property codes (C-slot settings).
    enum Prop {
        static let imageSize: UInt16 = 0xD18E
        static let imageQuality: UInt16 = 0xD18F
        static let dynamicRange: UInt16 = 0xD190
        static let dynamicRangePriority: UInt16 = 0xD191
        static let filmSimulation: UInt16 = 0xD192
        static let monochromaticColorTemperature: UInt16 = 0xD193
        static let monochromaticColorTint: UInt16 = 0xD194
        static let grainEffect: UInt16 = 0xD195
        static let colorChromeEffect: UInt16 = 0xD196
        static let colorChromeFxBlue: UInt16 = 0xD197
        static let smoothSkinEffect: UInt16 = 0xD198
        static let whiteBalance: UInt16 = 0xD199
        static let whiteBalanceShiftRed: UInt16 = 0xD19A
        static let whiteBalanceShiftBlue: UInt16 = 0xD19B
        static let whiteBalanceTemperature: UInt16 = 0xD19C
        static let highlightTone: UInt16 = 0xD19D
        static let shadowTone: UInt16 = 0xD19E
        static let color: UInt16 = 0xD19F
        static let sharpness: UInt16 = 0xD1A0
        static let noiseReduction: UInt16 = 0xD1A1
        static let clarity: UInt16 = 0xD1A2
        static let lensModulationOptimizer: UInt16 = 0xD1A3
        static let colorSpace: UInt16 = 0xD1A4
    }

    /// A named-value table. `decodeOnly` holds extra codes the camera reports but must not be written.
    struct Lookup: Sendable {
        let field: String
        let values: [(String, UInt16)]
        var decodeOnly: [UInt16: String] = [:]

        func encode(_ id: String) throws -> UInt16 {
            // Accept fujicli's CLI spelling (classic-chrome) as well as its JSON spelling (classic_chrome),
            // but leave numbers such as "-4" alone.
            let lower = id.lowercased()
            let key = lower.contains(where: \.isLetter) ? lower.replacingOccurrences(of: "-", with: "_") : lower
            guard let match = values.first(where: { $0.0 == key }) else {
                throw FujiKitError.unsupportedValue(field: field, value: id)
            }
            return match.1
        }

        func decode(_ wire: UInt16) throws -> String {
            if let match = values.first(where: { $0.1 == wire }) { return match.0 }
            if let extra = decodeOnly[wire] { return extra }
            throw FujiKitError.unknownWireValue(field: field, value: Int(wire))
        }
    }

    static let imageSize = Lookup(field: "imageSize", values: [
        ("7728x5152", 0x07), ("7728x4344", 0x08), ("5152x5152", 0x09), ("6864x5152", 0x0E), ("6432x5152", 0x10),
        ("5472x3648", 0x04), ("5472x3080", 0x05), ("3648x3648", 0x06), ("4864x3648", 0x12), ("4560x3648", 0x14),
        ("3888x2592", 0x01), ("3888x2184", 0x02), ("2592x2592", 0x03), ("3456x2592", 0x0A), ("3264x2592", 0x0C),
    ])
    static let imageQuality = Lookup(field: "imageQuality", values: [
        ("fine_raw", 0x04), ("fine", 0x02), ("normal_raw", 0x05), ("normal", 0x03), ("raw", 0x01),
    ])
    static let filmSimulation = Lookup(field: "filmSimulation", values: [
        ("provia", 0x01), ("velvia", 0x02), ("astia", 0x03), ("pro_neg_hi", 0x04), ("pro_neg_std", 0x05),
        ("monochrome", 0x06), ("monochrome_ye", 0x07), ("monochrome_r", 0x08), ("monochrome_g", 0x09),
        ("sepia", 0x0A), ("classic_chrome", 0x0B), ("acros", 0x0C), ("acros_ye", 0x0D), ("acros_r", 0x0E),
        ("acros_g", 0x0F), ("eterna", 0x10), ("classic_negative", 0x11), ("eterna_bleach_bypass", 0x12),
        ("nostalgic_negative", 0x13), ("reala_ace", 0x14),
    ])
    static let monochromeSimulations: Set<String> = [
        "monochrome", "monochrome_ye", "monochrome_r", "monochrome_g", "acros", "acros_ye", "acros_r", "acros_g",
    ]
    /// Cameras read back 0x06 for Off on default slots; 0x01 is what must be written.
    static let grainEffect = Lookup(field: "grainEffect", values: [
        ("strong_large", 0x05), ("weak_large", 0x04), ("strong_small", 0x03), ("weak_small", 0x02), ("off", 0x01),
    ], decodeOnly: [0x06: "off"])
    static func strength(_ field: String) -> Lookup {
        Lookup(field: field, values: [("strong", 0x03), ("weak", 0x02), ("off", 0x01)])
    }
    static let colorChromeEffect = strength("colorChromeEffect")
    static let colorChromeFxBlue = strength("colorChromeFxBlue")
    static let smoothSkinEffect = strength("smoothSkinEffect")
    static let whiteBalance = Lookup(field: "whiteBalance", values: [
        ("as_shot", 0x0000), ("white_priority", 0x8020), ("auto", 0x0002), ("ambience_priority", 0x8021),
        ("custom1", 0x8008), ("custom2", 0x8009), ("custom3", 0x800A), ("temperature", 0x8007),
        ("daylight", 0x0004), ("shade", 0x8006), ("fluorescent1", 0x8001), ("fluorescent2", 0x8002),
        ("fluorescent3", 0x8003), ("incandescent", 0x0006), ("underwater", 0x0008),
    ])
    static let noiseReduction = Lookup(field: "noiseReduction", values: [
        ("4", 0x5000), ("3", 0x6000), ("2", 0x0000), ("1", 0x1000), ("0", 0x2000),
        ("-1", 0x3000), ("-2", 0x4000), ("-3", 0x7000), ("-4", 0x8000),
    ])
    static let lensModulationOptimizer = Lookup(field: "lensModulationOptimizer", values: [("on", 0x01), ("off", 0x02)])
    static let colorSpace = Lookup(field: "colorSpace", values: [("srgb", 0x02), ("adobe_rgb", 0x01)])
    static let dynamicRange = Lookup(field: "dynamicRange", values: [
        ("auto", 0xFFFF), ("hdr100", 0x64), ("hdr200", 0xC8), ("hdr400", 0x190), ("hdr800", 0x320), ("hdr800_plus", 0x640),
    ])
    static let dynamicRangePriority = Lookup(field: "dynamicRangePriority", values: [
        ("auto", 0x8000), ("plus", 0x03), ("strong", 0x02), ("weak", 0x01), ("off", 0x00),
    ])
    // Render-only settings.
    static let fileType = Lookup(field: "fileType", values: [("jpeg", 0x07), ("heif", 0x12), ("tiff8", 0x09), ("tiff16", 0x0B)])
    static let teleconverter = Lookup(field: "teleconverter", values: [("on", 0x01), ("off", 0x02)])
    /// Exposure offset in thousandths of a stop, on a 1/3-stop grid.
    static let exposureSteps: [Int32] = [-3000, -2667, -2333, -2000, -1667, -1333, -1000, -667, -333, 0,
                                         333, 667, 1000, 1333, 1667, 2000, 2333, 2667, 3000]

    // MARK: Numeric settings (scaled signed 16-bit)

    struct Scaled: Sendable {
        let field: String
        let scale: Double
        let range: ClosedRange<Double>
        let step: Double

        func encode(_ value: Double) throws -> Int16 {
            guard range.contains(value), abs((value / step).rounded() * step - value) < 1e-6 else {
                throw FujiKitError.unsupportedValue(field: field, value: Self.text(value))
            }
            return Int16((value * scale).rounded())
        }

        func decode(_ wire: Int16) -> Double { Double(wire) / scale }

        static func text(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(v) }
    }

    static let monochromaticColorTemperature = Scaled(field: "monochromaticColorTemperature", scale: 10, range: -18...18, step: 1)
    static let monochromaticColorTint = Scaled(field: "monochromaticColorTint", scale: 10, range: -18...18, step: 1)
    static let whiteBalanceShiftRed = Scaled(field: "whiteBalanceShiftRed", scale: 1, range: -9...9, step: 1)
    static let whiteBalanceShiftBlue = Scaled(field: "whiteBalanceShiftBlue", scale: 1, range: -9...9, step: 1)
    static let highlightTone = Scaled(field: "highlightTone", scale: 10, range: -2...4, step: 0.5)
    static let shadowTone = Scaled(field: "shadowTone", scale: 10, range: -2...4, step: 0.5)
    static let color = Scaled(field: "color", scale: 10, range: -4...4, step: 1)
    static let sharpness = Scaled(field: "sharpness", scale: 10, range: -4...4, step: 1)
    static let clarity = Scaled(field: "clarity", scale: 10, range: -5...5, step: 1)
    static let temperatureRange: ClosedRange<Int> = 2500...10000

    static func encodeTemperature(_ kelvin: Int) throws -> UInt16 {
        guard temperatureRange.contains(kelvin), kelvin % 10 == 0 else {
            throw FujiKitError.unsupportedValue(field: "whiteBalanceTemperature", value: String(kelvin))
        }
        return UInt16(kelvin)
    }

    static func encodeNoiseReduction(_ value: Int) throws -> UInt16 { try noiseReduction.encode(String(value)) }
    static func decodeNoiseReduction(_ wire: UInt16) throws -> Int { Int(try noiseReduction.decode(wire))! }

    /// DR values that a RAW shot at `original` can be rendered with.
    static func allowedDynamicRanges(original: String) -> Set<String>? {
        switch original {
        case "hdr100": ["hdr100"]
        case "hdr200": ["hdr100", "hdr200"]
        case "hdr400": ["hdr100", "hdr200", "hdr400"]
        case "hdr800": ["hdr100", "hdr200", "hdr400", "hdr800"]
        default: nil
        }
    }
}
