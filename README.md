# Nimble Fuji

A macOS 26 app that renders Fujifilm RAF files on an X-T5's own image processor, using film-simulation recipes stored as YAML.

## How it works

1. **Recipes** (sidebar). Tick one or more recipes for the batch, and click a recipe to edit it in the inspector. Each recipe is one `.yaml` file in `~/Library/Application Support/Nimble Fuji/Recipes` (you can change the folder in Settings).
2. **RAW files** (center). Drop RAF files or folders, or click **+**. The selected rows make up the batch.
3. **Render** (bottom bar). Every selected RAW is rendered with every ticked recipe: `fujicli image render` applies the recipe's settings over the as-shot settings, so no C slot is touched. Output goes to `<output folder>/<RAW>_<Recipe>.jpg`.

The camera won't raise Dynamic Range above the value the RAW was shot with. When a recipe asks for more (for example DR400 on a DR200 shot), the app renders at the as-shot DR and adds a note to that job.

To run the on-camera test: `TEST_RUNNER_NIMBLE_FUJI_TEST_RAF=/path/to/file.RAF xcodebuild test -scheme NimbleFuji`.

Camera setup: USB data cable, then **MENU › NETWORK/USB SETTING › CONNECTION MODE › USB RAW CONV./BACKUP RESTORE**, with auto power-off turned off.

## Recipe YAML

Any setting you leave out keeps the as-shot value. Values are matched leniently (`Classic Chrome`, `classic-chrome` and `Classic Chrome.` all work).

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
exposure: -1/3              # -3…+3 EV
source: https://…
notes: …
```

## Building

```sh
brew install xcodegen
xcodegen generate          # regenerates NimbleFuji.xcodeproj from project.yml
open NimbleFuji.xcodeproj
```

fujicli must be installed (built here into `~/.local/bin/fujicli` from https://github.com/karaolidis/fujicli). You can change its location in Settings.

## Native engine (FujiKit)

`FujiKit/` holds a native Swift port of fujicli (library plus a `fujikit` command-line tool). It talks to the camera through IOUSBHost and needs no external tools. The app still uses fujicli for now; see [FujiKit/README.md](FujiKit/README.md).

## License

GPL-3.0. See [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md) for attribution to fujicli and the other projects this builds on. Distribution is planned as a free, notarized app outside the App Store.

## App Store status (superseded)

v1 calls the external, GPL-3.0 `fujicli` binary, so the App Sandbox is **off** and this build can't go to the App Store. Before submitting:

- Replace `FujiCLI` with a native Swift PTP-over-USB engine behind the same interface (`render`, `connectedCameras`).
- Turn on `ENABLE_APP_SANDBOX` and add `com.apple.security.device.usb` plus user-selected read/write file access.
- Save the output and recipe folders as security-scoped bookmarks instead of plain paths.
- Remove the “Release Camera from macOS” button (it runs `killall`).
- Add an app icon.
