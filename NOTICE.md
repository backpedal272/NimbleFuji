# Notices and attribution

Nimble Fuji is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License, version 3, as published by the Free Software Foundation. See [LICENSE](LICENSE).

## Additional permission: Mac App Store

The copyright holder of fujicli, Nikolaos Karaolidis, granted the following additional permission under section 7 of the GNU GPL v3 in November 2026:

> As the copyright holder of fujicli, I grant you an additional permission under section 7 of the GNU GPL v3 (and AGPL v3): you may distribute NimbleFuji, including the code ported from fujicli, through the Mac App Store, notwithstanding any terms of Apple's App Store that conflict with the license, provided that the app is free of charge and its complete source remains publicly available under the same license.

## fujicli

Nimble Fuji drives the camera through [fujicli](https://github.com/karaolidis/fujicli) (canonical repository: https://git.karaolidis.com/karaolidis/fujicli), and the native **FujiKit** engine in `FujiKit/` is a Swift port of fujicli's `fujicore` and `ptp-cursor` crates.

- Copyright © Nikolaos Karaolidis
- Licensed under the GNU General Public License v3.0
- Ported from commit `6366cff82449d19dab9e6234c3dc6ec5922e6ccb` (2026-10-20)

Changes made in the port: rewritten in Swift; IOKit/IOUSBHost replaces libusb; the X-T5 property tables are written by hand instead of generated from FML; grain code `0x06` is read as Off. A one-line change to fujicli itself, which reads grain code `0x06` as Off, is described in `FujiKit/patches/`.

fujicli builds on reverse-engineering work by [fujihack](https://github.com/fujihack/fujihack), [fudge](https://github.com/petabyt/fudge), [libpict](https://github.com/petabyt/libpict), [fp](https://github.com/petabyt/fp) and [libgphoto2](https://github.com/gphoto/libgphoto2).

## fujifilm-ptp-recipes

Property encodings and camera behaviour are also documented in [fujifilm-ptp-recipes](https://github.com/ILFforever/fujifilm-ptp-recipes) by ILFforever, licensed under CC BY 4.0 (documentation) and MIT (example code).

## Yams

YAML parsing uses [Yams](https://github.com/jpsim/Yams), MIT License.

## Sample recipes

The CLAUTRA 800 sample recipe comes from https://www.aiformortals.co/blog/claude-code-control-fujifilm-camera. Recipe settings are listed as facts, with a link to their source.

Fujifilm and X-T5 are trademarks of FUJIFILM Corporation. This project is not affiliated with or endorsed by Fujifilm.
