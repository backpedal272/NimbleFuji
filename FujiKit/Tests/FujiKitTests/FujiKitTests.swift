// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import Testing
@testable import FujiKit

/// In-memory transport: records writes and plays back queued reads.
final class FakeTransport: PTPTransport {
    var written: [Data] = []
    var reads: [Data] = []

    func write(_ data: Data) throws { written.append(data) }
    func read(maxLength: Int) throws -> Data {
        guard !reads.isEmpty else { return Data() }
        var next = reads.removeFirst()
        if next.count > maxLength {
            reads.insert(next.dropFirst(maxLength), at: 0)
            next = next.prefix(maxLength)
        }
        return next
    }

    static func container(_ type: PTPContainerType, code: UInt16, tid: UInt32, payload: Data = Data()) -> Data {
        var w = PTPWriter()
        w.u32(UInt32(12 + payload.count)); w.u16(type.rawValue); w.u16(code); w.u32(tid)
        w.bytes(payload)
        return w.data
    }
}

struct CodecTests {
    @Test func stringsRoundTrip() throws {
        var w = PTPWriter()
        w.string("Leica Real")
        w.string("")
        w.exactString("ff179502")
        var r = PTPReader(w.data)
        #expect(try r.string() == "Leica Real")
        #expect(try r.string() == "")
        #expect(try r.exactString() == "ff179502")
        #expect(r.isAtEnd)
    }

    @Test func ptpStringLayout() {
        var w = PTPWriter()
        w.string("AB")
        // count includes terminator: 3, then 'A' 'B' NUL as UTF-16LE
        #expect(Array(w.data) == [3, 0x41, 0, 0x42, 0, 0, 0])
    }

    @Test func readerReportsTruncation() {
        var r = PTPReader(Data([1, 2]))
        #expect(throws: PTPCodecError.self) { try r.u32() }
    }
}

struct SessionTests {
    @Test func transactionWithDataPhase() throws {
        let t = FakeTransport()
        t.reads = [
            FakeTransport.container(.response, code: PTPResponse.ok, tid: 0),                   // OpenSession
            FakeTransport.container(.data, code: 0x1015, tid: 1, payload: Data([0x06, 0x00])), // GetDevicePropValue
            FakeTransport.container(.response, code: PTPResponse.ok, tid: 1),
        ]
        let session = PTPSession(transport: t, chunkSize: 1024)
        try session.open()
        #expect(try session.getU16(FujiProperty.usbMode.rawValue) == 6)
        // Second command: length 16, type 1, code 0x1015, tid 1, param 0xD16E
        var r = PTPReader(t.written[1])
        #expect(try r.u32() == 16)
        #expect(try r.u16() == 1)
        #expect(try r.u16() == 0x1015)
        #expect(try r.u32() == 1)
        #expect(try r.u32() == 0xD16E)
    }

    @Test func largeDataPhaseIsChunked() throws {
        let t = FakeTransport()
        t.reads = [FakeTransport.container(.response, code: PTPResponse.ok, tid: 0)]
        let session = PTPSession(transport: t, chunkSize: 100)
        try session.send(.fujiSendObject, data: Data(repeating: 0xAB, count: 250))
        // command, then data: header+88 bytes, 100, 62
        #expect(t.written.map(\.count) == [12, 100, 100, 62])
        var r = PTPReader(t.written[1])
        #expect(try r.u32() == 262)
    }

    @Test func errorResponsesThrow() throws {
        let t = FakeTransport()
        t.reads = [FakeTransport.container(.response, code: 0x2019, tid: 0)]
        let session = PTPSession(transport: t, chunkSize: 1024)
        #expect(throws: PTPError.self) { try session.send(.getDeviceInfo) }
    }
}

struct RenderProfileTests {
    /// Captured from an X-T5 (firmware 4.31) after applying the Leica Real recipe.
    static func fixture() throws -> Data {
        let url = try #require(Bundle.module.url(forResource: "xt5-profile-leica-real", withExtension: "hex", subdirectory: "Fixtures"))
        let hex = try String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        var data = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            data.append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
        return data
    }

    @Test func decodesCapturedProfile() throws {
        let profile = try RenderProfile(data: try Self.fixture(), expectedCode: CameraModel.xt5.renderProfileCode)
        let s = try profile.settings()
        #expect(s.filmSimulation == "reala_ace")
        #expect(s.grainEffect == "off")
        #expect(s.colorChromeEffect == "strong")
        #expect(s.colorChromeFxBlue == "weak")
        #expect(s.whiteBalance == "auto")
        #expect(s.whiteBalanceShiftRed == 2 && s.whiteBalanceShiftBlue == -1)
        #expect(s.dynamicRange == "hdr200")
        #expect(s.highlightTone == -1 && s.shadowTone == 0)
        #expect(s.color == 3 && s.noiseReduction == -4)
    }

    @Test func encodesTwentyNineFields() throws {
        let data = try Self.fixture()
        #expect(data.count == 625) // 28 fields when read
        let profile = try RenderProfile(data: data, expectedCode: CameraModel.xt5.renderProfileCode)
        let encoded = profile.encoded()
        #expect(encoded.count == 629) // 29 fields when written
        #expect(encoded.prefix(625) == data.prefix(625))
    }

    @Test func applyingKeepsUnsetValuesAndEnforcesRules() throws {
        let profile = try RenderProfile(data: try Self.fixture(), expectedCode: CameraModel.xt5.renderProfileCode)
        var changes = CameraSettings()
        changes.filmSimulation = "classic_chrome"
        changes.exposureOffset = 0.33
        let next = try profile.applying(changes).settings()
        #expect(next.filmSimulation == "classic_chrome")
        #expect(next.color == 3) // kept
        #expect(abs((next.exposureOffset ?? 0) - 0.333) < 0.001)

        var tooHigh = CameraSettings()
        tooHigh.dynamicRange = "hdr400"
        #expect(throws: FujiKitError.rule("Dynamic Range cannot exceed the value the image was shot with.")) {
            try profile.applying(tooHigh)
        }

        var mono = CameraSettings()
        mono.filmSimulation = "acros_r"
        let monoSettings = try profile.applying(mono).settings()
        #expect(monoSettings.color == nil)
        #expect(monoSettings.monochromaticColorTemperature == 0)
    }

    @Test func dRangePriorityDropsInheritedTone() throws {
        let profile = try RenderProfile(data: try Self.fixture(), expectedCode: CameraModel.xt5.renderProfileCode)
        var changes = CameraSettings()
        changes.dynamicRangePriority = "strong"
        let s = try profile.applying(changes).settings()
        #expect(s.dynamicRangePriority == "strong")
        #expect(s.dynamicRange == nil && s.highlightTone == nil)
    }
}

struct SettingsTests {
    @Test func grainReadsSixAsOff() throws {
        #expect(try XT5.grainEffect.decode(0x06) == "off")
        #expect(try XT5.grainEffect.encode("off") == 0x01)
    }

    @Test func acceptsCLIAndJSONSpellings() throws {
        #expect(try XT5.filmSimulation.encode("classic-chrome") == 0x0B)
        #expect(try XT5.filmSimulation.encode("classic_chrome") == 0x0B)
        #expect(try XT5.encodeNoiseReduction(-4) == 0x8000)
    }

    @Test func slotRulesMatchFujicli() {
        var s = CameraSettings()
        s.filmSimulation = "provia"
        s.monochromaticColorTint = 2
        #expect(throws: FujiKitError.self) { try SlotIO.validate(s) }
    }

    @Test func settingsJSONMatchesFujicliNames() throws {
        let json = #"{"customSettingName":"Leica Real","filmSimulation":"reala_ace","grainEffect":"off","highlightTone":-1.0,"noiseReduction":0}"#
        let s = try JSONDecoder().decode(CameraSettings.self, from: Data(json.utf8))
        #expect(s.customSettingName == "Leica Real" && s.highlightTone == -1 && s.noiseReduction == 0)
    }
}

struct StaleSessionTests {
    @Test func recoversFromSessionLeftOpen() throws {
        let t = FakeTransport()
        t.reads = [
            FakeTransport.container(.response, code: PTPSession.sessionAlreadyOpen, tid: 0), // OpenSession
            FakeTransport.container(.response, code: PTPResponse.ok, tid: 1),                 // CloseSession
            FakeTransport.container(.response, code: PTPResponse.ok, tid: 0),                 // OpenSession again
        ]
        let session = PTPSession(transport: t, chunkSize: 1024)
        try session.open()
        let codes = try t.written.map { var r = PTPReader($0); try r.skip(6); return try r.u16() }
        #expect(codes == [0x1002, 0x1003, 0x1002])
    }
}
