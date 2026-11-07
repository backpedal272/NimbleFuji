// FujiKit — X-T5 RAW conversion profile (device property 0xD185), ported from fujicli's
// generated XT5RenderProfile and the render rules in fml/camera.cue.
// Copyright © Nikolaos Karaolidis (fujicli) and Nimble Fuji contributors.
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// The camera's RAW conversion settings: 29 signed 32-bit fields after a short header
/// (28 when read: the trailing field is write-only, as in fujicli's `skip_read`).
/// Field values use the same codes as the C-slot properties, widened to 32 bits.
public struct RenderProfile: Equatable, Sendable {
    enum Field: Int, CaseIterable {
        case head0, fileType, imageSize, imageQuality, exposureOffset, dynamicRange, dynamicRangePriority,
             filmSimulation, grainEffect, colorChromeEffect, whiteBalanceAsShot, whiteBalance,
             whiteBalanceShiftRed, whiteBalanceShiftBlue, whiteBalanceTemperature, highlightTone, shadowTone,
             color, sharpness, noiseReduction, lensModulationOptimizer, colorSpace,
             monochromaticColorTemperature, smoothSkinEffect, colorChromeFxBlue, monochromaticColorTint,
             clarity, teleconverter, tail0
    }

    static let fieldCount: Int16 = 29
    static let paddingLength = 494

    public let profileCode: UInt32
    var fields: [Int32]

    subscript(_ field: Field) -> Int32 {
        get { fields[field.rawValue] }
        set { fields[field.rawValue] = newValue }
    }

    // MARK: Wire format

    public init(data: Data, expectedCode: UInt32) throws {
        var r = PTPReader(data)
        let count = try r.i16()
        guard count == Self.fieldCount else {
            throw PTPError.malformed("render profile has \(count) fields, expected \(Self.fieldCount)")
        }
        let codeText = try r.exactString()
        guard let code = UInt32(codeText, radix: 16), code == expectedCode else {
            throw PTPError.malformed("unexpected render profile code “\(codeText)”")
        }
        profileCode = code
        try r.skip(Self.paddingLength)
        // The last field (tail0) is write-only: the camera sends 28 values but expects 29 back.
        fields = try (0..<Int(count) - 1).map { _ in try r.i32() } + [0]
    }

    public func encoded() -> Data {
        var w = PTPWriter()
        w.i16(Self.fieldCount)
        w.exactString(String(profileCode, radix: 16))
        w.zeros(Self.paddingLength)
        fields.forEach { w.i32($0) }
        return w.data
    }

    // MARK: Decoding

    private func u16(_ f: Field) -> UInt16 { UInt16(truncatingIfNeeded: self[f]) }
    private func i16(_ f: Field) -> Int16 { Int16(truncatingIfNeeded: self[f]) }

    /// The profile as settings, with fujicli's presence rules (e.g. no tone values under DR priority).
    public func settings() throws -> CameraSettings {
        var s = CameraSettings()
        s.fileType = try XT5.fileType.decode(u16(.fileType))
        s.imageSize = try XT5.imageSize.decode(u16(.imageSize))
        s.imageQuality = try XT5.imageQuality.decode(u16(.imageQuality))
        s.exposureOffset = Double(self[.exposureOffset]) / 1000
        let drp = try XT5.dynamicRangePriority.decode(u16(.dynamicRangePriority))
        s.dynamicRangePriority = drp
        if drp == "off" {
            s.dynamicRange = try XT5.dynamicRange.decode(u16(.dynamicRange))
            s.highlightTone = XT5.highlightTone.decode(i16(.highlightTone))
            s.shadowTone = XT5.shadowTone.decode(i16(.shadowTone))
        }
        let film = try XT5.filmSimulation.decode(u16(.filmSimulation))
        s.filmSimulation = film
        let mono = XT5.monochromeSimulations.contains(film)
        s.grainEffect = try XT5.grainEffect.decode(u16(.grainEffect))
        s.colorChromeEffect = try XT5.colorChromeEffect.decode(u16(.colorChromeEffect))
        let asShot = self[.whiteBalanceAsShot] == 1
        s.whiteBalance = asShot ? "as_shot" : try XT5.whiteBalance.decode(u16(.whiteBalance))
        if !asShot {
            s.whiteBalanceShiftRed = Int(XT5.whiteBalanceShiftRed.decode(i16(.whiteBalanceShiftRed)))
            s.whiteBalanceShiftBlue = Int(XT5.whiteBalanceShiftBlue.decode(i16(.whiteBalanceShiftBlue)))
            if s.whiteBalance == "temperature" { s.whiteBalanceTemperature = Int(u16(.whiteBalanceTemperature)) }
        }
        if !mono { s.color = Int(XT5.color.decode(i16(.color))) }
        s.sharpness = Int(XT5.sharpness.decode(i16(.sharpness)))
        s.noiseReduction = try XT5.decodeNoiseReduction(u16(.noiseReduction))
        s.lensModulationOptimizer = try XT5.lensModulationOptimizer.decode(u16(.lensModulationOptimizer))
        s.colorSpace = try XT5.colorSpace.decode(u16(.colorSpace))
        if mono {
            s.monochromaticColorTemperature = Int(XT5.monochromaticColorTemperature.decode(i16(.monochromaticColorTemperature)))
            s.monochromaticColorTint = Int(XT5.monochromaticColorTint.decode(i16(.monochromaticColorTint)))
        }
        s.smoothSkinEffect = try XT5.smoothSkinEffect.decode(u16(.smoothSkinEffect))
        s.colorChromeFxBlue = try XT5.colorChromeFxBlue.decode(u16(.colorChromeFxBlue))
        s.clarity = Int(XT5.clarity.decode(i16(.clarity)))
        s.teleconverter = try XT5.teleconverter.decode(u16(.teleconverter))
        return s
    }

    // MARK: Applying settings

    /// Returns this profile (the RAW's as-shot settings) with `changes` applied,
    /// enforcing the camera's rules. Settings not in `changes` keep their as-shot values.
    public func applying(_ changes: CameraSettings) throws -> RenderProfile {
        let original = try settings()
        var merged = original
        func take<T>(_ key: WritableKeyPath<CameraSettings, T?>) { if let v = changes[keyPath: key] { merged[keyPath: key] = v } }
        take(\.fileType); take(\.imageSize); take(\.imageQuality); take(\.exposureOffset)
        take(\.filmSimulation); take(\.monochromaticColorTemperature); take(\.monochromaticColorTint)
        take(\.grainEffect); take(\.colorChromeEffect); take(\.colorChromeFxBlue)
        take(\.whiteBalance); take(\.whiteBalanceShiftRed); take(\.whiteBalanceShiftBlue); take(\.whiteBalanceTemperature)
        take(\.highlightTone); take(\.shadowTone); take(\.color); take(\.sharpness); take(\.noiseReduction)
        take(\.clarity); take(\.lensModulationOptimizer); take(\.colorSpace)
        take(\.dynamicRange); take(\.dynamicRangePriority); take(\.smoothSkinEffect); take(\.teleconverter)

        // HDR800+ is HDR800 with D-range priority Plus.
        if merged.dynamicRange == "hdr800_plus" {
            merged.dynamicRange = "hdr800"
            merged.dynamicRangePriority = "plus"
        }

        // Inherited values that no longer apply are dropped; explicitly requested ones are errors.
        let mono = merged.filmSimulation.map(XT5.monochromeSimulations.contains) ?? false
        if mono {
            if changes.color != nil { throw FujiKitError.rule("Color does not apply to black and white simulations.") }
            merged.color = nil
            merged.monochromaticColorTemperature = merged.monochromaticColorTemperature ?? 0
            merged.monochromaticColorTint = merged.monochromaticColorTint ?? 0
        } else {
            if changes.monochromaticColorTemperature != nil || changes.monochromaticColorTint != nil {
                throw FujiKitError.rule("Monochromatic color settings only apply to black and white simulations.")
            }
            merged.monochromaticColorTemperature = nil
            merged.monochromaticColorTint = nil
            merged.color = merged.color ?? 0
        }

        let asShot = merged.whiteBalance == "as_shot"
        if merged.whiteBalance != "temperature" || asShot {
            if changes.whiteBalanceTemperature != nil {
                throw FujiKitError.rule("White balance temperature is only meaningful in Temperature mode.")
            }
            merged.whiteBalanceTemperature = nil
        } else if merged.whiteBalanceTemperature == nil {
            merged.whiteBalanceTemperature = 5500
        }
        if asShot {
            if changes.whiteBalanceShiftRed != nil || changes.whiteBalanceShiftBlue != nil {
                throw FujiKitError.rule("White balance shifts apply only when White Balance is not As Shot.")
            }
            merged.whiteBalanceShiftRed = nil
            merged.whiteBalanceShiftBlue = nil
        } else {
            merged.whiteBalanceShiftRed = merged.whiteBalanceShiftRed ?? 0
            merged.whiteBalanceShiftBlue = merged.whiteBalanceShiftBlue ?? 0
        }

        if (merged.dynamicRangePriority ?? "off") != "off" {
            if changes.dynamicRange != nil, changes.dynamicRange != "hdr800_plus" {
                throw FujiKitError.rule("Dynamic Range can only be set when Dynamic Range Priority is disabled.")
            }
            if changes.highlightTone != nil { throw FujiKitError.rule("Highlight Tone can only be set when Dynamic Range Priority is disabled.") }
            if changes.shadowTone != nil { throw FujiKitError.rule("Shadow Tone can only be set when Dynamic Range Priority is disabled.") }
            if merged.dynamicRange != "hdr800" { merged.dynamicRange = nil }
            merged.highlightTone = nil
            merged.shadowTone = nil
        } else {
            merged.dynamicRange = merged.dynamicRange ?? "hdr100"
            merged.highlightTone = merged.highlightTone ?? 0
            merged.shadowTone = merged.shadowTone ?? 0
        }

        if let shot = original.dynamicRange, let allowed = XT5.allowedDynamicRanges(original: shot),
           let wanted = merged.dynamicRange, !allowed.contains(wanted) {
            throw FujiKitError.rule("Dynamic Range cannot exceed the value the image was shot with.")
        }
        if merged.teleconverter == "on", original.teleconverter != "on" {
            throw FujiKitError.rule("Teleconverter can only be enabled if it was enabled when the image was shot.")
        }

        // Encode.
        var next = self
        next[.head0] = 0
        next[.tail0] = 0
        func set(_ f: Field, _ v: UInt16) { next[f] = Int32(v) }
        func set(_ f: Field, _ v: Int16) { next[f] = Int32(v) }
        set(.fileType, try XT5.fileType.encode(merged.fileType ?? "jpeg"))
        set(.imageSize, try XT5.imageSize.encode(merged.imageSize ?? original.imageSize!))
        set(.imageQuality, try XT5.imageQuality.encode(merged.imageQuality ?? original.imageQuality!))
        let ev = Int32(((merged.exposureOffset ?? 0) * 1000).rounded())
        guard (-3000...3000).contains(ev) else { throw FujiKitError.unsupportedValue(field: "exposureOffset", value: "\(merged.exposureOffset ?? 0)") }
        next[.exposureOffset] = XT5.exposureSteps.min { abs($0 - ev) < abs($1 - ev) }!
        next[.dynamicRange] = try merged.dynamicRange.map { Int32(try XT5.dynamicRange.encode($0)) } ?? 0
        set(.dynamicRangePriority, try XT5.dynamicRangePriority.encode(merged.dynamicRangePriority ?? "off"))
        set(.filmSimulation, try XT5.filmSimulation.encode(merged.filmSimulation!))
        set(.grainEffect, try XT5.grainEffect.encode(merged.grainEffect!))
        set(.colorChromeEffect, try XT5.colorChromeEffect.encode(merged.colorChromeEffect!))
        next[.whiteBalanceAsShot] = asShot ? 1 : 2
        set(.whiteBalance, asShot ? u16(.whiteBalance) : try XT5.whiteBalance.encode(merged.whiteBalance!))
        next[.whiteBalanceShiftRed] = try merged.whiteBalanceShiftRed.map { Int32(try XT5.whiteBalanceShiftRed.encode(Double($0))) } ?? 0
        next[.whiteBalanceShiftBlue] = try merged.whiteBalanceShiftBlue.map { Int32(try XT5.whiteBalanceShiftBlue.encode(Double($0))) } ?? 0
        next[.whiteBalanceTemperature] = try merged.whiteBalanceTemperature.map { Int32(try XT5.encodeTemperature($0)) } ?? 0
        next[.highlightTone] = try merged.highlightTone.map { Int32(try XT5.highlightTone.encode($0)) } ?? 0
        next[.shadowTone] = try merged.shadowTone.map { Int32(try XT5.shadowTone.encode($0)) } ?? 0
        next[.color] = try merged.color.map { Int32(try XT5.color.encode(Double($0))) } ?? 0
        set(.sharpness, try XT5.sharpness.encode(Double(merged.sharpness ?? 0)))
        set(.noiseReduction, try XT5.encodeNoiseReduction(merged.noiseReduction ?? 0))
        set(.lensModulationOptimizer, try XT5.lensModulationOptimizer.encode(merged.lensModulationOptimizer ?? "on"))
        set(.colorSpace, try XT5.colorSpace.encode(merged.colorSpace ?? "srgb"))
        next[.monochromaticColorTemperature] = try merged.monochromaticColorTemperature.map { Int32(try XT5.monochromaticColorTemperature.encode(Double($0))) } ?? 0
        set(.smoothSkinEffect, try XT5.smoothSkinEffect.encode(merged.smoothSkinEffect ?? "off"))
        set(.colorChromeFxBlue, try XT5.colorChromeFxBlue.encode(merged.colorChromeFxBlue ?? "off"))
        next[.monochromaticColorTint] = try merged.monochromaticColorTint.map { Int32(try XT5.monochromaticColorTint.encode(Double($0))) } ?? 0
        set(.clarity, try XT5.clarity.encode(Double(merged.clarity ?? 0)))
        set(.teleconverter, try XT5.teleconverter.encode(merged.teleconverter ?? "off"))
        return next
    }
}
