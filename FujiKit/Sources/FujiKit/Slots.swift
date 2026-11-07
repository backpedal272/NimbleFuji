// FujiKit — C-slot read/write, ported from fujicli's generated XT5Simulation try_pull/try_push.
// Copyright © Nikolaos Karaolidis (fujicli) and Nimble Fuji contributors.
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

extension PTPSession {
    func getI16(_ code: UInt16) throws -> Int16 { Int16(bitPattern: try getU16(code)) }
    func setI16(_ code: UInt16, _ value: Int16) throws { try setU16(code, UInt16(bitPattern: value)) }

    func getString(_ code: UInt16) throws -> String {
        var r = PTPReader(try getProperty(code))
        return try r.string()
    }

    func setString(_ code: UInt16, _ value: String) throws {
        var w = PTPWriter()
        w.string(value)
        try setProperty(code, w.data)
    }
}

enum SlotIO {
    /// Reads every setting of the currently selected slot.
    static func read(_ ptp: PTPSession) throws -> CameraSettings {
        typealias P = XT5.Prop
        var s = CameraSettings()
        s.customSettingName = try ptp.getString(FujiProperty.customSettingName.rawValue)
        s.imageSize = try XT5.imageSize.decode(try ptp.getU16(P.imageSize))
        s.imageQuality = try XT5.imageQuality.decode(try ptp.getU16(P.imageQuality))
        let film = try XT5.filmSimulation.decode(try ptp.getU16(P.filmSimulation))
        s.filmSimulation = film
        let mono = XT5.monochromeSimulations.contains(film)
        if mono {
            s.monochromaticColorTemperature = Int(XT5.monochromaticColorTemperature.decode(try ptp.getI16(P.monochromaticColorTemperature)))
            s.monochromaticColorTint = Int(XT5.monochromaticColorTint.decode(try ptp.getI16(P.monochromaticColorTint)))
        }
        s.grainEffect = try XT5.grainEffect.decode(try ptp.getU16(P.grainEffect))
        s.colorChromeEffect = try XT5.colorChromeEffect.decode(try ptp.getU16(P.colorChromeEffect))
        s.colorChromeFxBlue = try XT5.colorChromeFxBlue.decode(try ptp.getU16(P.colorChromeFxBlue))
        let wb = try XT5.whiteBalance.decode(try ptp.getU16(P.whiteBalance))
        s.whiteBalance = wb
        s.whiteBalanceShiftRed = Int(XT5.whiteBalanceShiftRed.decode(try ptp.getI16(P.whiteBalanceShiftRed)))
        s.whiteBalanceShiftBlue = Int(XT5.whiteBalanceShiftBlue.decode(try ptp.getI16(P.whiteBalanceShiftBlue)))
        if wb == "temperature" {
            s.whiteBalanceTemperature = Int(try ptp.getU16(P.whiteBalanceTemperature))
        }
        if !mono {
            s.color = Int(XT5.color.decode(try ptp.getI16(P.color)))
        }
        s.sharpness = Int(XT5.sharpness.decode(try ptp.getI16(P.sharpness)))
        s.noiseReduction = try XT5.decodeNoiseReduction(try ptp.getU16(P.noiseReduction))
        s.clarity = Int(XT5.clarity.decode(try ptp.getI16(P.clarity)))
        s.lensModulationOptimizer = try? XT5.lensModulationOptimizer.decode(try ptp.getU16(P.lensModulationOptimizer))
        s.colorSpace = try XT5.colorSpace.decode(try ptp.getU16(P.colorSpace))
        let drp = try XT5.dynamicRangePriority.decode(try ptp.getU16(P.dynamicRangePriority))
        s.dynamicRangePriority = drp
        if drp == "off" {
            s.highlightTone = XT5.highlightTone.decode(try ptp.getI16(P.highlightTone))
            s.shadowTone = XT5.shadowTone.decode(try ptp.getI16(P.shadowTone))
            s.dynamicRange = try XT5.dynamicRange.decode(try ptp.getU16(P.dynamicRange))
        }
        s.smoothSkinEffect = try XT5.smoothSkinEffect.decode(try ptp.getU16(P.smoothSkinEffect))
        return s
    }

    /// Checks a full slot write against the camera's rules (fujicli's simulation rules).
    static func validate(_ s: CameraSettings) throws {
        let mono = s.filmSimulation.map(XT5.monochromeSimulations.contains) ?? false
        if !mono, s.monochromaticColorTemperature != nil || s.monochromaticColorTint != nil {
            throw FujiKitError.rule("Monochromatic color settings only apply to black and white simulations.")
        }
        if mono, s.color != nil {
            throw FujiKitError.rule("Color does not apply to black and white simulations.")
        }
        if s.whiteBalanceTemperature != nil, s.whiteBalance != "temperature" {
            throw FujiKitError.rule("White balance temperature is only meaningful in Temperature mode.")
        }
        let drp = s.dynamicRangePriority ?? "off"
        if drp != "off" {
            if s.dynamicRange != nil { throw FujiKitError.rule("Dynamic Range can only be set when Dynamic Range Priority is disabled.") }
            if s.highlightTone != nil { throw FujiKitError.rule("Highlight Tone can only be set when Dynamic Range Priority is disabled.") }
            if s.shadowTone != nil { throw FujiKitError.rule("Shadow Tone can only be set when Dynamic Range Priority is disabled.") }
        }
        if let name = s.customSettingName, name.utf16.count > 25 {
            throw FujiKitError.unsupportedValue(field: "customSettingName", value: name)
        }
    }

    /// Writes the settings that are present, in the order fujicli uses (film simulation
    /// before its dependants, D-range priority before tone and DR).
    static func write(_ s: CameraSettings, _ ptp: PTPSession) throws {
        typealias P = XT5.Prop
        try validate(s)
        if let v = s.customSettingName { try ptp.setString(FujiProperty.customSettingName.rawValue, v) }
        if let v = s.imageSize { try ptp.setU16(P.imageSize, try XT5.imageSize.encode(v)) }
        if let v = s.imageQuality { try ptp.setU16(P.imageQuality, try XT5.imageQuality.encode(v)) }
        if let v = s.filmSimulation { try ptp.setU16(P.filmSimulation, try XT5.filmSimulation.encode(v)) }
        if let v = s.monochromaticColorTemperature { try ptp.setI16(P.monochromaticColorTemperature, try XT5.monochromaticColorTemperature.encode(Double(v))) }
        if let v = s.monochromaticColorTint { try ptp.setI16(P.monochromaticColorTint, try XT5.monochromaticColorTint.encode(Double(v))) }
        if let v = s.grainEffect { try ptp.setU16(P.grainEffect, try XT5.grainEffect.encode(v)) }
        if let v = s.colorChromeEffect { try ptp.setU16(P.colorChromeEffect, try XT5.colorChromeEffect.encode(v)) }
        if let v = s.colorChromeFxBlue { try ptp.setU16(P.colorChromeFxBlue, try XT5.colorChromeFxBlue.encode(v)) }
        if let v = s.whiteBalance { try ptp.setU16(P.whiteBalance, try XT5.whiteBalance.encode(v)) }
        if let v = s.whiteBalanceShiftRed { try ptp.setI16(P.whiteBalanceShiftRed, try XT5.whiteBalanceShiftRed.encode(Double(v))) }
        if let v = s.whiteBalanceShiftBlue { try ptp.setI16(P.whiteBalanceShiftBlue, try XT5.whiteBalanceShiftBlue.encode(Double(v))) }
        if let v = s.whiteBalanceTemperature { try ptp.setU16(P.whiteBalanceTemperature, try XT5.encodeTemperature(v)) }
        if let v = s.color { try ptp.setI16(P.color, try XT5.color.encode(Double(v))) }
        if let v = s.sharpness { try ptp.setI16(P.sharpness, try XT5.sharpness.encode(Double(v))) }
        if let v = s.noiseReduction { try ptp.setU16(P.noiseReduction, try XT5.encodeNoiseReduction(v)) }
        if let v = s.clarity { try ptp.setI16(P.clarity, try XT5.clarity.encode(Double(v))) }
        if let v = s.lensModulationOptimizer {
            // fujicli treats this field as flaky: the camera sometimes rejects it; skip on error.
            try? ptp.setU16(P.lensModulationOptimizer, try XT5.lensModulationOptimizer.encode(v))
        }
        if let v = s.colorSpace { try ptp.setU16(P.colorSpace, try XT5.colorSpace.encode(v)) }
        if let v = s.smoothSkinEffect { try ptp.setU16(P.smoothSkinEffect, try XT5.smoothSkinEffect.encode(v)) }
        if let v = s.dynamicRangePriority { try ptp.setU16(P.dynamicRangePriority, try XT5.dynamicRangePriority.encode(v)) }
        if let v = s.highlightTone { try ptp.setI16(P.highlightTone, try XT5.highlightTone.encode(v)) }
        if let v = s.shadowTone { try ptp.setI16(P.shadowTone, try XT5.shadowTone.encode(v)) }
        if let v = s.dynamicRange { try ptp.setU16(P.dynamicRange, try XT5.dynamicRange.encode(v)) }
    }
}
