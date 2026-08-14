# 1.0.1 (versionCode 3) — indicator verification captures

Taken on the stock `Medium_Phone_API_36.1` emulator (Android 16) against
release builds, 2026-08-14. Status-bar strips are magnified; the phone renders
these icons at 24dp.

| File | What it shows |
|---|---|
| `01_before_after_and_chip.png` | The live versionCode 2 mark, the 1.0.1 plated mark on the same status bar, the Android 16 promoted chip on the home screen, and the same chip with ten other notifications posted. |
| `02_toggle_and_level0.png` | The high-contrast switch moving the live notification between `ic_signal_bars_plate_5` and `ic_signal_bars_5`, and the plated mark at score 0 with its five empty slots outlined. |
| `03_dark_status_bar.png` | The plate under a dark status bar, where the system tints it white. |
| `04_hs_lettering_prototype_rejected.png` | The rejected experiment: "HS" lettering inside the 24dp mask, beside the shipped design. The S reads as a 5 and the bars lose half their height. |
| `05_upgrade_v2_to_v3.png` | The upgrade path every live user takes — versionCode 2 installed and running, then versionCode 3 installed over it. |
| `06_colorized_shade_pre_android16.png` | What Android 15 and below get: the shade entry colorized to the score colour. Captured by forcing `canPromote()` false in a throwaway debug build, since this device is API 36. |
| `07_promoted_shade_android16.png` | Android 16: the promoted notification sitting above ten other notifications in the shade. |

The claims that a screenshot cannot carry — which drawable resource is live,
whether the system granted promotion, whether anything made a sound — were read
from `dumpsys notification` and mapped through `aapt2 dump resources`. Those
readings are quoted in `PIPELINE.md` under the 1.0.1 section.
