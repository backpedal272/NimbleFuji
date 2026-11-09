# Nimble Fuji

**Batch-render Fujifilm RAW files with film-simulation recipes on your camera's own image processor, from a Mac.**

Nimble Fuji sends your RAF files to a connected Fujifilm X-T5 over USB and has the camera render them, the same way in-camera RAW conversion or Fujifilm X RAW Studio does. The JPEGs come out of the camera's real film simulations, not an emulation. On top of that it adds what X RAW Studio lacks: a library of recipes stored as plain YAML files, rendering every selected RAW with every selected recipe in one go, and drag-and-drop into the camera's C1–C7 custom slots.

<!-- Screenshot: add docs/screenshot.png (camera connected, a few RAWs loaded) and uncomment:
![Nimble Fuji: recipes on the left, RAW files in the middle, the recipe editor on the right](docs/screenshot.png)
-->

> Free and open source (GPL-3.0). An unofficial project, not affiliated with or endorsed by Fujifilm.

## What it does

- **Renders on the camera.** Each RAW is sent to the X-T5, the recipe is applied over the photo's as-shot settings, and the camera's processor produces the JPEG. Nothing on the camera changes: no C slot is used for rendering.
- **Renders in batches.** Tick 3 recipes and select 20 RAWs, and you get 60 JPEGs named `<RAW>_<Recipe>.jpg`. It's a quick way to compare recipes on your own photos.
- **Keeps recipes as YAML.** One readable file per recipe, easy to share, back up, or keep in git. Settings you leave out keep the photo's as-shot value. Import recipe files you find online, or edit them in the app's inspector.
- **Writes recipes to the camera's slots.** Drag a recipe onto C1–C7 and the app shows exactly what will change before writing. Right-click a slot to save the recipe that's on the camera as a YAML file.
- **Backs up the camera first.** Before its first slot write in a session, the app saves a full settings backup of the camera. You can also back up or restore by hand from the Camera menu.
- **Needs no other tools.** The app talks to the camera directly over USB with its own engine, FujiKit, a Swift port of [fujicli](https://github.com/karaolidis/fujicli). fujicli can optionally serve as a fallback.

## Requirements

- A Mac running **macOS 26** or later.
- A **Fujifilm X-T5**. It's the only camera supported and tested so far (firmware 4.31). Other X-Trans V bodies may be close, but aren't supported yet.
- A **USB-C data cable**, connected directly to the Mac (not through a hub).

## Camera setup

1. On the camera: **MENU › NETWORK/USB SETTING › CONNECTION MODE › USB RAW CONV./BACKUP RESTORE**.
2. Turn off **AUTO POWER OFF** while you work, so the camera doesn't drop off in the middle of a batch.
3. Connect the cable and switch the camera on. The toolbar shows the camera when it's ready.

## Install

There's no pre-built download yet, so you build the app from source. It takes a couple of minutes with Xcode:

```sh
git clone https://github.com/backpedal272/NimbleFuji.git
cd NimbleFuji
open NimbleFuji.xcodeproj
```

In Xcode, choose **Product › Run**, or **Product › Archive** to get an app you can copy to /Applications. A free, notarized download is planned.

## Using it

1. **Recipes** (left). Tick the recipes for the next batch. Click one to edit it in the inspector on the right. A setting left at "As shot" keeps the photo's own value.
2. **RAW files** (middle). Drop RAF files or whole folders, or click **+**. The selected rows are the batch.
3. **Render** (bottom bar). Choose the output folder (by default `~/Pictures/Nimble Fuji`) and click **Render**.
4. **Camera slots** (bottom left). Drag a recipe onto a slot to write it. Click a slot to see its settings.

Settings (⌘,) has a draft-quality mode for faster previews, whether to overwrite existing JPEGs, the recipe folder, and the camera engine.

### Good to know

- **Dynamic Range can't go up.** The camera refuses a Dynamic Range above the one the photo was shot with. When a recipe asks for DR400 on a DR200 shot, the app renders at DR200 and notes it on that job.
- **Writing a slot replaces it completely.** Settings the recipe leaves at "As shot" are reset to neutral, because a slot has no "as shot". Image size, quality and color space stay as they were.
- **Backups** are saved in `~/Library/Application Support/Nimble Fuji/Backups`.
- **If macOS grabs the camera** (Image Capture or Photos can claim it when it's plugged in), use **Settings › Release Camera from macOS**, then reconnect.

## Recipe files

Recipes live in `~/Library/Application Support/Nimble Fuji/Recipes` (you can change the folder in Settings). Values are matched loosely, so `Classic Chrome`, `classic-chrome` and `Classic Chrome.` all work.

```yaml
name: CLAUTRA 800
film_simulation: Classic Chrome
grain: Strong Large
color_chrome_effect: Weak
color_chrome_fx_blue: Off
white_balance: 6300K        # or Auto, Daylight, Fluorescent 3, As Shot…
wb_shift_red: 1
wb_shift_blue: -3
dynamic_range: DR400
d_range_priority: Off
highlight: -1.5             # -2…+4, step 0.5
shadow: -0.5
color: 2                    # -4…+4
sharpness: -2
high_iso_nr: -4
clarity: -2                 # -5…+5
smooth_skin: Off
monochromatic_color_wc: 0   # Acros/Monochrome only, -18…+18
monochromatic_color_mg: 0
exposure: -1/3              # -3…+3 EV, applied when rendering only
source: https://…
notes: …
```

Any setting you leave out keeps the photo's as-shot value.

## For developers

### Building

The Xcode project is generated from `project.yml`. After changing `project.yml`, regenerate it:

```sh
brew install xcodegen
xcodegen generate
```

### Tests

`xcodebuild test -scheme NimbleFuji` runs without a camera. The on-camera tests are opt-in:

```sh
TEST_RUNNER_NIMBLE_FUJI_TEST_RAF=/path/to/file.RAF xcodebuild test -scheme NimbleFuji   # renders on the camera
TEST_RUNNER_NIMBLE_FUJI_TEST_SLOTS=1 xcodebuild test -scheme NimbleFuji                # reads C1–C7
```

### FujiKit

`FujiKit/` is the native camera engine: a Swift package, with a `fujikit` command-line tool, that renders, reads and writes slots, and backs up the camera over USB through Apple's IOUSBHost framework. It was checked operation by operation against fujicli. See [FujiKit/README.md](FujiKit/README.md).

### App icon

`scripts/generate_icon.swift` draws the icon (a cream camera on the `#009AD6` → `#006CA5` gradient):

```sh
swift scripts/generate_icon.swift scripts/AppIcon.png
for n in 16 32 64 128 256 512 1024; do sips -z $n $n scripts/AppIcon.png --out NimbleFuji/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-mac-$n.png; done
```

## Credits

Nimble Fuji stands on the reverse-engineering work of others. Above all, [fujicli](https://github.com/karaolidis/fujicli) by Nikolaos Karaolidis, which FujiKit is a port of, and the projects fujicli builds on: [fujihack](https://github.com/fujihack/fujihack), [fudge](https://github.com/petabyt/fudge), [libpict](https://github.com/petabyt/libpict), [fp](https://github.com/petabyt/fp) and [libgphoto2](https://github.com/gphoto/libgphoto2). Property encodings are also documented in [fujifilm-ptp-recipes](https://github.com/ILFforever/fujifilm-ptp-recipes) by ILFforever. YAML parsing uses [Yams](https://github.com/jpsim/Yams). Full attribution is in [NOTICE.md](NOTICE.md).

## License

GPL-3.0. See [LICENSE](LICENSE). fujicli's author has granted an additional permission to distribute the app through the Mac App Store, provided that it is free of charge and its complete source stays public. See [NOTICE.md](NOTICE.md).

Fujifilm and X-T5 are trademarks of FUJIFILM Corporation. This project is not affiliated with or endorsed by Fujifilm. It talks to your camera through an undocumented protocol, so use it at your own risk and keep backups.
