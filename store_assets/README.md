# store_assets/

Design sources for Honest Signal. Everything here regenerates from a script — no
hand-edited binaries, so a later release produces an identical set.

| Path | What |
|---|---|
| `BRAND.md` | Palette, typography, shape scale, icon rationale, tone |
| `screenshot_specs.md` | The shot list and why each shot exists |
| `icon/` | `build_icon.py` → SVGs, `render.sh` → PNGs, proofs |
| `feature_graphic/` | Play 1024 × 500 + crop proof |
| `screenshots/` | `frame.html` + `specs.json` + `render.sh`; `raw/` takes the captures |

This Mac has **no ImageMagick, rsvg-convert, Inkscape or PIL**. Every raster step
is headless Chrome, and downscales are `sips` (Chrome crops rather than scales
when the window is smaller than the source).

## Regenerating the icon

```bash
store_assets/icon/render.sh          # SVG -> PNG + proofs
dart run flutter_launcher_icons      # wire into both platforms
```

**Then undo what the generator breaks.** `flutter_launcher_icons` 0.14.4
overwrites the *project-level* `ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS`
in `ios/Runner.xcodeproj/project.pbxproj` with the string `AppIcon` (it belongs
in `ASSETCATALOG_COMPILER_APPICON_NAME`, which is already set on the target).
Two lines, both must go back to `YES`:

```bash
sed -i '' \
  's/ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = AppIcon;/ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;/g' \
  ios/Runner.xcodeproj/project.pbxproj
```

The repo is not under git yet, so **copy `project.pbxproj` somewhere before
running the generator** — a diff is the only way to see what it did.

The generator also creates and rewrites `android/app/src/main/res/values/colors.xml`.
The hand-written launch-window colour therefore lives in its own
`values*/window_background.xml`; Android merges every XML file in a `values`
folder, so it survives. Do not move it into `colors.xml`.

`flutter_native_splash` is **not** used — the launch window is a themed colour,
which is all a local-first utility needs and avoids the package's habit of
reindenting `Info.plist` and regenerating `LaunchScreen.storyboard` on every run.

## Proofs worth actually looking at

Geometry arithmetic passes long after a mark has stopped reading. Every render
script emits proofs; open them.

- `icon/preview_48.png` — does the mark still read at a launcher's smallest size?
- `icon/preview_adaptive.png` — the foreground at the 16% inset inside the round
  launcher mask, with the safe circle drawn on top.
- `feature_graphic/proof_crop.png` — the outer 100 px shaded, because Play crops
  the graphic on some surfaces.
