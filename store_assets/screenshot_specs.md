# Honest Signal — store screenshot specs

Stage 2 (design) artifact. Written by ui-designer, 2026-08-08.
Companion to `BRAND.md`. The machine-readable shot list is
`screenshots/specs.json`; this file is the reasoning behind it.

Division of labour: **store-publisher captures, this spec decides what is in the
capture and how it is framed.** Everything here is scripted, so a later release
regenerates an identical set.

---

## 1. How to produce the set

```bash
# 1. Capture. Put the simulator/emulator in LIGHT appearance first (§2),
#    and do NOT pass SCREENSHOT_TIER=free for the marketing set (§3, shot 4).
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/screenshots_test.dart \
  --dart-define=SCREENSHOT_MODE=true

# 2. Drop the captures in store_assets/screenshots/raw/, then frame them.
cd store_assets/screenshots && ./render.sh
# -> out/ios/*.png   1320x2868
# -> out/play/*.png  1080x2160
```

`render.sh` refuses to run on an empty `raw/`, so a set can never be built from
nothing. The frame **letterboxes** the capture rather than cropping it: a frame
that crops silently drops whatever sat below the cut, and the spec then promises
an element the artwork does not show.

**Captures go stale whenever the binary changes what it says.** The app's name
appears inside the screenshots — the app bar, the Pro button, the onboarding
body — so a capture taken before a rename frames new headline copy over old
on-screen text. That is not hypothetical either: at the "True Signal" →
"Honest Signal" rename the existing captures produced artwork whose subheadline
read "Honest Signal measures the connection" above a phone reading "True Signal
actually uses the connection". The stale captures were deleted rather than kept,
precisely so `render.sh`'s empty-`raw/` guard forces a recapture. Do the same
after any change to on-screen copy.

Sizes: Apple wants one 6.9" iPhone set (**1320 × 2868**, portrait) and scales the
rest; the app is iPhone-only (`TARGETED_DEVICE_FAMILY = 1`) so there is no iPad
set. Play's phone minimum is 1080 × 1920, but a 16:9 canvas cannot show a whole
modern phone screen at a sensible scale, so the set is **1080 × 2160** — Play's
maximum permitted 2:1 ratio.

## 2. Capture conditions

| Condition | Value | Why |
|---|---|---|
| Theme | **Light** (device appearance) | See below — this was changed on the evidence, having framed real captures. |
| Demo data | `--dart-define=SCREENSHOT_MODE=true` | Fakes the probe client, connectivity, budget and store, so every run is byte-identical. ANDed with `!kReleaseMode`, so a release binary can never be switched into it. |
| Tier | **default (`pro`)** for the marketing set | Non-negotiable: see §3's history shot. `SCREENSHOT_TIER=free` is for the paywall/IAP capture **only**. |
| Locale | en-GB | The only listing locale. |

**Why light, not dark.** This spec originally called for dark captures on the
reasoning that they would match the ink plate the frames use. Framing real
captures showed that to be exactly backwards: the app's dark surface is
`#0F1511` and the plate runs `#14241E`→`#08120F`, so a dark screenshot all but
disappears into its own background and only the device border separates them. A
light capture reads as a lit device on a dark stage, which is the separation the
layout wants. It also puts the mode most users see by default in the listing.

Both themes remain fully supported and either is shippable — the frame stays ink
regardless — but the set ships light unless there is a reason to change it.

The seeded state, from `lib/core/demo/screenshot_mode.dart` — worth knowing
because the copy below depends on it:

- **Live reading: 5 bars, "Excellent"**, 24 ms latency, 60 Mbps, ±1 ms jitter,
  0% loss, 5/5 score (100/100 composite), Wi-Fi. (Figures read off a real
  capture, not off the demo source — the engine's setup discount lands the
  throughput at 60 Mbps, not the ~48 the fake's comment suggests.)
- **Budget: 6.1 MB / 25 MB** spent today.
- **History: 61 minutes**, telling a story — home Wi-Fi solid, then struggling,
  then failing (a 6-minute drop-out on Wi-Fi at 1 bar); the phone falling back
  to mobile data, which is slow and then drops out too (a 4-minute drop-out on
  cellular at 0 bars); mobile data recovering; Wi-Fi back and strong now. Only
  the raw latency/jitter/throughput/loss figures are invented — every bar count
  comes from `SignalScoring`, so the chart, drop-out list and "By network"
  rows (Wi-Fi 4.2/5, Cellular 3.0/5) are what the real engine produces.
  (Reseeded 2026-10-11 for the 1.1.0 history screen.)

## 3. The shots

Ordered by marketing priority. Most users never swipe past the second, so the
first two carry the hook and the proof.

### 1 — "Full bars. No data."
- **Screen / state:** `/welcome` onboarding, first frame (`00_onboarding`). Shows
  the side-by-side comparison: five grey bars labelled *What your phone says*,
  an arrow, one orange bar labelled *What it can do*.
- **Subheadline:** "Your phone measures the mast. Honest Signal measures the
  connection."
- **Why first:** it states the problem in one picture, before the product is
  even introduced. Everyone who has stood somewhere with full bars and a dead
  page recognises it instantly. A hero shot of the app's own meter cannot do
  that — it looks like every other network tool.
- **Both stores.**

### 2 — "See what it can actually do"
- **Screen / state:** `/` home (`01_home`), demo reading. Bars, verdict
  "Excellent", freshness line, all six metric tiles (Network, Latency, Speed,
  Jitter, Lost probes, Score) and the daily budget meter.
- **Subheadline:** "Latency, jitter, lost probes and a real transfer sample."
- **Why:** the proof shot. Six real figures answer "is this a gimmick?".
- **Framing note:** verified on a real 1080 × 2400 capture — everything fits on
  one screen, including "Measure now" and the Pro button below it. Nothing in
  this shot is at risk of falling below the fold, and the frame letterboxes the
  capture anyway.
- **Both stores.**

### 3 — "A live score in your status bar"  *(Play only)*
- **Screen / state:** `/settings` (`03_settings`), Android build. Shows the
  Indicator section: the status-bar switch on, the floating-indicator row, and
  the three indicator-style swatches.
- **Subheadline:** "Keeps measuring while you get on with something else."
- **Why Play only:** the status-bar indicator and the floating bubble are
  Android features. The same headline above an App Store listing would be a
  false claim, and a false claim is a rejection risk.
- **Why not a photo of the real status bar:** the harness captures the Flutter
  surface only, so a system notification cannot be captured. Showing the control
  that turns it on is honest; a composited mock-up of a notification would not
  be.

### 4 — "Prove the drop-outs are real"  *(badge: Pro)*
- **Screen / state:** `/history` (`02_history`), Pro tier, "Last hour" selected.
  The step chart shows the seeded collapse and recovery; the stat rows below show
  time at 4–5 bars, time at 0–1 bars, median latency, best speed, sample count.
- **Subheadline:** "An hour or a full day, kept on your phone."
- **Badge:** "Pro" — the pill is on the artwork deliberately. Selling a locked
  feature as though it were free is the pattern both stores flag, and it is the
  opposite of the studio line.
- **Both stores** (position 4 on Play, position 3 on iOS).
- **This shot must come from a `pro`-tier capture.** On a `free` run the same
  route renders `ProLock` — "History is a Pro feature" — and the pipeline will
  cheerfully frame that under a headline promising a chart, producing a store
  screenshot that shows a paywall where it advertises a graph. This is not
  hypothetical; a free-tier verification run produced exactly that. `render.sh`
  now refuses to frame the Pro-badged shots unless `raw/tier.txt` says `pro`.

### 5 — "No mystery score"
- **Screen / state:** `/how-it-works` (`04_how_it_works`). The four numbered
  steps and the weighting card.
- **Subheadline:** "Every weight and threshold is written down, in the app."
- **Why it earns a slot:** the product claim is that the number is honest, and
  the only way to sell honesty is to show the working. It is also the answer to
  the obvious objection — "how would it know?".
- **Both stores.**

### Not in either set — the paywall
`05_pro` is still captured, and must be: App Store Connect requires a screenshot
of the in-app purchase for review. It is **excluded from both marketing sets**
because the demo store renders a `£2.99` price label, and a GBP figure baked into
artwork is wrong on every non-UK storefront. Use it only as the IAP review
screenshot.

## 4. Copy rules for any future shot

- Lead with the outcome, not the feature name. Under ~6 words.
- One idea per screenshot; the subheadline explains it, it does not add a second.
- True on **every** storefront the shot ships to — check platform-specific
  features against the set they land in.
- No prices, no currency symbols, no "#1"/"best"/"fastest".
- No trademarked terms. Carrier names, "Wi-Fi" brand marks and OS names stay out
  of the artwork; the app's own screens may say Wi-Fi because it is describing
  the device's own transport.
- Never state or imply the app measures in the background on iOS. It does not,
  and the app itself says so.

---

## 5. 1.1.0 refresh (2026-10-11, store-publisher)

- History shot headline is now **"Every drop‑out, on the record"** /
  "When, how long, and on which network — for 30 days." (both stores, Pro badge).
  It shows the 1 h / 24 h / 7 d / 30 d selector, the drop-out list and "By network".
- Play status-bar shot is captured with **drop-out alerts switched on** (the
  harness taps the switch, pro tier only); its subheadline says alerts are Pro.
- New **Play-only** shot `04_widget`: *not* a harness capture. It is an
  `adb exec-out screencap` of the real 2×1 widget on the emulator home screen
  (status bar shows the live "HS" indicator chip), cropped with
  `ffmpeg -vf crop=1080:1860:0:0` to drop the launcher dock and Google search
  bar (third-party marks). `raw/06_widget.png`. Recapture after any widget
  layout change. `sips -c` crops from the centre and ignores `--cropOffset`.
- The App Store set (`raw_ios/`) is still captured host-side on an iPhone 17
  Pro Max simulator with `xcrun simctl io screenshot`, synchronised by stdout
  markers from a temporary test file (deleted afterwards). Clear the handshake
  files in /tmp between runs or every shot lags one screen.
- Play now ships 6 screenshots; `scripts/play_release.rb` guards on 6.
