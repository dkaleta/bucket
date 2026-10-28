# ios-frame

Frame a real iOS screenshot in an official Apple device bezel. Requires Python 3
and ImageMagick (`brew install imagemagick`). No Python packages or API keys.

```sh
ios-frame screenshot.png
ios-frame screenshot.png -o showcase.png --background white --padding 160
ios-frame screenshot.png -o showcase.png --background '#f5f3ef' --padding 120
ios-frame --list-frames
```

Default: transparent PNG beside the input named `<input>-iphone-18-pro-black.png`.
Existing files require `--force`. The screenshot is never modified. Matching
lower-resolution screenshots are resized; incompatible aspect ratios are rejected.
Only portrait iPhone 18 Pro Black is configured, with a 1206 × 2622 screen.
Output is 1350 × 2760 before padding.

## Official asset setup

Apple artwork is cached locally, not redistributed in this repository. Download
[Apple's iPhone 18 bezel package](https://developer.apple.com/design/resources/#product-bezels),
open it, and follow its license instructions. Then:

```sh
./ios-frame --install-frame '/Volumes/Bezel-iPhone-18/PNG/iPhone 18 Pro/iPhone 18 Pro - Black - Portrait.png'
```

The verified PNG is copied to `~/.cache/ios-frame/`. Override with `--cache-dir`.
`frames.json` records its source, checksum, screen placement and dimensions.
A changed asset must be inspected and calibrated before updating the manifest.
Additional devices require their own verified manifest entries.

Optional installation on PATH, from this folder:

```sh
mkdir -p ~/.local/bin
ln -s "$(pwd)/ios-frame" ~/.local/bin/ios-frame
```

## Capture

Navigate to the desired screen on an iPhone 18 Pro simulator, then:

```sh
xcrun simctl io <device-UDID> screenshot /tmp/screen.png
ios-frame /tmp/screen.png -o ~/Downloads/showcase.png --background white --padding 160
```

Use an explicit UDID. This CLI frames supplied images; Simulator navigation is
handled by the `ios-showcase` Codex skill. Processing is entirely local.

## Verification

Run `python3 test_cli.py`. Tests use synthetic screenshots and the installed
frame to check pixel placement, transparency, dimensions, backgrounds,
aspect-ratio rejection and overwrite protection.
