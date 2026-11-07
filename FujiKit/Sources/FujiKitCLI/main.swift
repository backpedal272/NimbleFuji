// fujikit — command-line front end for FujiKit (a Swift port of fujicli).
// Copyright © Nikolaos Karaolidis (fujicli) and Nimble Fuji contributors.
// SPDX-License-Identifier: GPL-3.0-only

import FujiKit
import Foundation

let usage = """
fujikit — control Fujifilm cameras over USB (native Swift port of fujicli)

Usage:
  fujikit device list
  fujikit device info
  fujikit slot list
  fujikit slot get <c1…c7>                 Print a slot as fujicli-compatible JSON
  fujikit slot set <c1…c7> <settings.json> Write the settings present in the file
  fujikit backup export <file.bak>
  fujikit backup import <file.bak>
  fujikit render [--settings <file.json>] [--draft] <input.RAF> <output.jpg>
  fujikit profile                          Print the camera's current RAW conversion profile

Settings files use fujicli's JSON names (filmSimulation, highlightTone, …).
The camera must be in USB RAW CONV./BACKUP RESTORE mode.

"""

struct CLIError: Error, CustomStringConvertible {
    let description: String
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("Error: \(message)\n".utf8))
    exit(1)
}

func slotNumber(_ text: String) throws -> Int {
    let digits = text.lowercased().hasPrefix("c") ? String(text.dropFirst()) : text
    guard let n = Int(digits) else { throw CLIError(description: "invalid slot “\(text)”, expected c1…c7") }
    return n
}

func json<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return String(decoding: try encoder.encode(value), as: UTF8.self)
}

func readSettings(_ path: String) throws -> CameraSettings {
    try JSONDecoder().decode(CameraSettings.self, from: Data(contentsOf: URL(filePath: path)))
}

func run(_ args: [String]) throws {
    guard args.count >= 2 else { print(usage, terminator: ""); return }
    switch (args[0], args[1]) {
    case ("device", "list"):
        let cameras = FujiCamera.connected()
        if cameras.isEmpty { print("No supported cameras connected") }
        cameras.forEach { print("- \($0)") }

    case ("device", "info"):
        let camera = try FujiCamera()
        let info = try camera.deviceInfo()
        print("Manufacturer: \(info.manufacturer)")
        print("Model: \(info.model)")
        print("Version: \(info.deviceVersion)")
        print("Serial Number: \(info.serialNumber)")
        let mode = try camera.usbMode()
        print("Mode: \(mode == 6 ? "Raw Conversion" : "0x\(String(mode, radix: 16))")")

    case ("slot", "list"):
        let camera = try FujiCamera()
        for n in 1...camera.model.slots { print("- C\(n): \(try camera.slotName(n))") }

    case ("slot", "get") where args.count == 3:
        let camera = try FujiCamera()
        print(try json(try camera.readSlot(try slotNumber(args[2]))))

    case ("slot", "set") where args.count == 4:
        let settings = try readSettings(args[3])
        let camera = try FujiCamera()
        let slot = try slotNumber(args[2])
        try camera.writeSlot(slot, settings)
        print(try json(try camera.readSlot(slot)))

    case ("backup", "export") where args.count == 3:
        let camera = try FujiCamera()
        try camera.exportBackup().write(to: URL(filePath: args[2]))

    case ("backup", "import") where args.count == 3:
        let data = try Data(contentsOf: URL(filePath: args[2]))
        let camera = try FujiCamera()
        try camera.importBackup(data)

    case ("render", _):
        var rest = Array(args.dropFirst())
        var settings = CameraSettings()
        var draft = false
        while let first = rest.first, first.hasPrefix("--") {
            rest.removeFirst()
            switch first {
            case "--draft": draft = true
            case "--settings":
                guard !rest.isEmpty else { throw CLIError(description: "--settings needs a file") }
                settings = try readSettings(rest.removeFirst())
            default: throw CLIError(description: "unknown option \(first)")
            }
        }
        guard rest.count == 2 else { throw CLIError(description: "render needs <input.RAF> <output>") }
        let raf = try Data(contentsOf: URL(filePath: rest[0]))
        let camera = try FujiCamera()
        let start = Date()
        let image = try camera.render(raf: raf, changes: settings, draft: draft) {
            FileHandle.standardError.write(Data("\($0)…\n".utf8))
        }
        try image.write(to: URL(filePath: rest[1]))
        FileHandle.standardError.write(Data(String(format: "Rendered %d bytes in %.1fs\n", image.count, Date().timeIntervalSince(start)).utf8))

    case ("profile", "--raw"):
        let data = try FujiCamera().readRenderProfileData()
        print("\(data.count) bytes")
        print(data.map { String(format: "%02x", $0) }.joined(separator: " "))

    case ("profile", _):
        let camera = try FujiCamera()
        print(try json(try camera.readRenderProfile().settings()))

    default:
        print(usage, terminator: "")
        exit(2)
    }
}

var arguments = Array(CommandLine.arguments.dropFirst())
if arguments.first == "profile" { arguments.append("") }
do {
    try run(arguments)
} catch {
    fail("\(error)")
}
