# FujiKit

Native Swift control of Fujifilm cameras over USB PTP: in-camera RAW rendering, C-slot read/write and settings backups. Needs no libusb, Rust or external tools.

FujiKit is a Swift port of [fujicli](https://github.com/karaolidis/fujicli)'s `fujicore` and `ptp-cursor` crates by Nikolaos Karaolidis, and is licensed under the **GPL-3.0**, like fujicli. See [../NOTICE.md](../NOTICE.md).

Only the **X-T5** is supported (and tested), as in fujicli. The camera must be in **USB RAW CONV./BACKUP RESTORE** mode.

## Command line

```sh
swift build -c release
.build/release/fujikit device list
.build/release/fujikit device info
.build/release/fujikit slot list
.build/release/fujikit slot get c1 > leica.json
.build/release/fujikit slot set c4 leica.json
.build/release/fujikit backup export camera.bak
.build/release/fujikit render --settings leica.json DSCF0001.RAF DSCF0001.jpg
```

Settings files use fujicli's JSON field names and values (`"filmSimulation": "reala_ace"`, `"highlightTone": -1`), so `fujicli simulation export` files work as-is. For `render`, settings that aren't in the file keep the photo's as-shot values.

## Library

```swift
import FujiKit

let camera = try FujiCamera()                  // first connected X-T5
let leica = try camera.readSlot(1)             // CameraSettings
let jpeg = try camera.render(raf: rafData, changes: leica)
```

`FujiCamera` isn't thread-safe; use it from one thread or actor.

## Checked against fujicli on an X-T5 (firmware 4.31)

| Operation | Result |
|---|---|
| Device info, USB mode, slot names | Same output |
| Slot read, C1–C7 | Field-for-field identical JSON, including D-range priority slots and grain code `0x06` |
| Render settings block (0xD185) | Byte-identical for color, monochrome, Kelvin WB and exposure-offset recipes |
| Rendered JPEG | Same settings in its metadata. Pixels vary from run to run with both tools, so they can't be compared bit for bit |
| Backup export | Byte-identical |
| Slot write | Round-trips unchanged; fujicli reads back the same values |
| Backup import | Implemented, **not yet tested** |

### Differences from fujicli

- **Grain:** grain code `0x06` is read as Off. fujicli 0.2.0 fails to read such slots; see `patches/`.
- **D-range priority:** when a render turns D-range priority on, FujiKit drops the photo's inherited DR, highlight and shadow values. fujicli refuses instead ("Dynamic Range can only be set when Dynamic Range Priority is disabled"), so it can't apply a DRP recipe to a photo shot without DRP.
- **Transport:** USB goes through Apple's IOUSBHost framework. Notarized, non-sandboxed builds work. The App Sandbox would need the `com.apple.security.device.usb` entitlement (untested).

## Tests

`swift test` runs without a camera. It uses a fake transport and a settings block captured from a real X-T5.
