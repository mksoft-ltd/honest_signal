# Honest Signal — Test Plan

Stage 3 (test) artifact. Written by mobile-qa-architect, 2026-08-08.

The app's product claim is that its number is honest. That makes the test suite
unusually load-bearing: a scoring bug here is not a cosmetic defect, it is the
app lying about the thing it exists to measure. The suite is therefore weighted
towards the measurement engine, the data budget, and the paths that decide what
the status-bar icon says.

---

## 1. How to run the suites

| Suite | Command | Needs |
|---|---|---|
| Unit + widget (everything in `test/`) | `flutter test` | nothing |
| Static analysis | `flutter analyze` | nothing |
| One file | `flutter test test/measurement_engine_test.dart` | nothing |
| One test | `flutter test --plain-name "hysteresis"` | nothing |
| Screenshot / journey harness | see below | a booted Android emulator |

### Screenshot harness

```
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/screenshots_test.dart \
  --dart-define=SCREENSHOT_MODE=true \
  -d <android-device-id>
```

Add `--dart-define=SCREENSHOT_TIER=free` for the paywall and the locked states;
without it the harness runs as Pro and the Pro entry point is absent, so
`05_pro` is not captured.

`flutter drive`, never `flutter test` — only the driver writes the PNGs, into
`store_assets/screenshots/raw/`, which is where ui-designer's
`store_assets/screenshots/render.sh` looks for them before framing each set into
`out/ios/` and `out/play/`. Put the device in **light** appearance first — the
frames use a dark ink plate, so a dark capture dissolves into its own background
(see `store_assets/screenshot_specs.md` §2 for the reasoning).

The driver also records `raw/tier.txt` (`pro` or `free`) from the tier the
harness reports with each capture. `render.sh` hard-fails if the marketing set
was captured with `SCREENSHOT_TIER=free`: on a free run the history route
renders the Pro lock, and framing that under a headline promising a chart would
ship a listing that advertises a graph and shows a paywall.

**Capture on Android.** `convertFlutterSurfaceToImage` is Android-only, and on
the iOS simulator `binding.takeScreenshot` returns the launch-screen layer for
every shot while the widget assertions still pass — byte-identical files that
look like a successful run. If iOS shots are needed, drive the app there and
capture host-side with `xcrun simctl io <udid> screenshot`, or run the harness
on Android and reframe. Either way, **md5 the captures and confirm they
differ** before accepting a run.

Screenshot order is currently `00_onboarding, 01_home, 02_history, 03_settings,
04_how_it_works, 05_pro`. `docs/ASO.md` does not exist yet (stage 5); when it
lands, reorder the captures to its marketing priority before the publish stage
uses them.

---

## 2. Coverage map

255 tests across 15 files. Everything that touches the outside world is behind
an injectable seam — `ProbeClient`, `ConnectivitySource`, `BudgetStore`,
`IapGateway`, `IndicatorChannel` — and every one of them is faked, so no test
opens a socket, contacts a store, or writes to real storage.

| File | Tests | What it holds down |
|---|---|---|
| `test/scoring_test.dart` | 12 | Shape of the model: sub-score curves, blending, verdicts |
| `test/scoring_boundaries_test.dart` | 18 | Exact hysteresis margins, cap precedence, documented constants |
| `test/measurement_engine_test.dart` | 12 | One cycle end to end: probes, transfer, early abort, staleness |
| `test/measurement_engine_edges_test.dart` | 19 | Transfer failure, retry, byte accounting, statistics, probe hosts |
| `test/measurement_controller_test.dart` | 22 | Budget enforcement, re-entrancy, lifecycle, connectivity, indicator feed |
| `test/history_and_controller_test.dart` | 13 | Dedup, retention, ordering; controller basics |
| `test/history_storage_test.dart` | 16 | Hive key limits, unreadable rows, clock jumps, round trips |
| `test/background_host_test.dart` | 17 | Background cycle decisions, the service method channel, notification wording |
| `test/indicator_controller_test.dart` | 15 | Notification-permission gating, overlay policy, service configuration |
| `test/purchase_controller_test.dart` | 11 | Happy-path purchase, restore, availability |
| `test/purchase_states_test.dart` | 20 | Purchase-stream transitions, guards, entitlement scoping |
| `test/settings_and_budget_test.dart` | 15 | Tier clamping, budget rollover, formatters |
| `test/widgets_test.dart` | 20 | Individual widgets, every bar theme and level, the method screen |
| `test/screens_test.dart` | 29 | Paywall, history gating, first run, the meter end to end, an 8-cell layout matrix |
| `test/release_invariants_test.dart` | 18 | Constants that also live in a store record or the manifest |

### Shared fakes (`test/fakes/`)

- `fake_probe_client.dart` — a scripted network. Per-probe round trips (`null`
  is a timeout) and, where the two attempts of a cycle must differ, a per-attempt
  transfer script. Also `FakeConnectivitySource`, which a test drives by hand,
  and `drain()`, which lets an unawaited async chain finish.
- `fake_iap_gateway.dart` — a store that answers on command. `buyNonConsumable`
  deliberately emits nothing; every terminal outcome is emitted by the test, as
  the real stores do.
- `fake_indicator_channel.dart` — the Android side of the indicator bridge. The
  real channel is a no-op off Android, so without this fake every permission and
  overlay path would silently pass on the host.

### What is covered by feature

| Area | Covered |
|---|---|
| Scoring model | Curves, blend, renormalisation, thresholds, hysteresis both directions, severe-loss cap, transfer-failure cap, cap precedence, out-of-range inputs |
| One measurement cycle | Median and MAD arithmetic, early abort, partial loss, byte accounting, transfer retry, setup discount and its floor, staleness expiry, target rotation |
| Data budget | Per-cycle charging, accumulation, exhaustion, day rollover, raising the limit, fail-closed on a broken channel, re-entrancy (one charge per answer) |
| Cadence | Foreground transfer interval, background transfer interval, forced transfer on open/refresh/network change |
| Connectivity | Transport change forces a re-measure, going offline, cellular opt-out |
| Android indicator | Permission requested only when the feature is on, service never starts without it, overlay never starts without the system grant, revoked grant stops it, free-tier values reach the service |
| Background service (Dart side) | Cycle decisions, previous-bars carry-over, budget sharing, the `runCycle` method channel, readiness announcement, notification wording |
| Purchases | Price from the store, unreachable store, buy, cancel, decline, pending, stream error, restore with and without a purchase, acknowledgement, entitlement scoped to the product ID, double-init |
| Storage | Hive auto-increment key limits, unreadable rows, retention boundary, clock moving backwards, JSON round trip |
| UI | Every bar theme and level, budget meter, pause banner, history chart, Pro locks, paywall states, first run, the meter with a good, dead and stalled connection, and a layout matrix of four handset widths (360/393/411/430 dp) against 1.0x and 1.3x text scale |
| Release invariants | Product ID, privacy URL, support URL, probe hosts, documented defaults and ranges, manifest permission set, screenshot mode welded shut in release |

---

## 3. Not covered by automation

### Needs hardware — verify by hand before release

| # | Check | Why it cannot be automated | Pass looks like |
|---|---|---|---|
| M1 | The background Flutter engine boots inside `HonestSignalService` | Requires the real Android service host; no test binding can start a second engine | Turn the indicator on, swipe the app away, wait one background interval, and watch the status-bar icon change as the connection changes |
| M2 | The small icon renders on OEM skins | Monochrome tinting for small icons differs per vendor and Android version | The icon is legible on stock Android, Samsung One UI and a Xiaomi/Pixel skin, at all six levels, in both light and dark status bars |
| M3 | The overlay window behaves | `SYSTEM_ALERT_WINDOW` cannot be granted or drawn in a test | Bubble appears only after the grant, drags smoothly, taps open the app, long-press dismisses, and it never steals keyboard focus from the app underneath |
| M4 | The boot receiver restores the indicator | Needs a real reboot | Enable the indicator, reboot, and the icon returns without opening the app |
| M5 | Real-network sanity | The suite never opens a socket | On real Wi-Fi the score is plausible; on airplane mode it drops to 0 within one cycle; on a deliberately throttled link the transfer-failure cap shows 2 bars |
| M6 | The daily budget on a real device | The counter lives in Android SharedPreferences behind a platform channel | Leave the indicator running for a day; the counter on the home screen rises and stops at the limit, and transfers stop while probes continue |
| M7 | iOS staleness copy | `Platform.isIOS` cannot be faked on the host, so the iOS-only line in `FreshnessLine` is unreachable in tests | On an iPhone, background the app for three minutes; on return the line reads red and states that iOS stops apps measuring in the background |
| M8 | Purchase against the real store | Sandbox accounts only | Buy in an Apple sandbox account and a Play internal-test track; the price matches the storefront, restore works on a second device, and no spinner survives a cancel |

M7 is worth stressing: **anything gated on `Platform.isIOS` or `Platform.isAndroid`
is invisible to the host test runner.** That includes the whole Android section
of Settings, the paywall's floating-indicator feature row, the onboarding
permission paragraph, and the iOS staleness line. They are reachable only on a
device.

### Known testability gaps

- `BackgroundMeasurementHost` calls `DateTime.now()` directly rather than taking
  an injected clock the way `MeasurementEngine` and `MeasurementController` do.
  The first-cycle and immediate-second-cycle transfer decisions are covered; the
  ten-minute expiry is not, because time cannot be advanced. Adding a `clock`
  parameter would close this.

---

## 4. Defects found and fixed during this stage

Two were found by *running* the screenshot harness on a booted Android emulator
rather than only compiling it. Neither was visible to `flutter test`.

1. **The harness could only ever produce one screenshot.**
   `convertFlutterSurfaceToImage` asserts `!_isSurfaceRendered`, so it may run
   once per test. The harness called it before every shot, and the second call
   threw `Surface already converted to an image`. The run "failed" after writing
   `00_onboarding.png` and nothing else. Fixed in
   `integration_test/screenshots_test.dart`: convert once, lazily, then pump
   before each capture. All six shots now land with six distinct md5s.

2. **Every metric tile overflowed by 8.3 px at real phone widths.**
   `A RenderFlex overflowed by 8.3 pixels on the bottom` in `MetricTile`'s
   Column at `w=150.7, h=71.7` — yellow-and-black stripes across the middle of
   the home-screen screenshot, on the shot that would have been the App Store
   hero image. Invisible to the suite because the default widget-test surface is
   800x600 logical, wider than any phone. Reported to ui-designer, who fixed the
   grid and the tile; pinned since by two layout tests at 411 dp and 360 dp
   widths in `test/screens_test.dart`.

   **Lesson worth carrying:** the default 800x600 test surface is wider than
   every real phone, so widget tests silently pass over layout that overflows on
   device. Any new screen test that cares about layout should set a phone-sized
   surface.

3. **The driver wrote the captures where nothing was looking for them.**
   It saved to `store_assets/screenshots/`, but ui-designer's `render.sh` reads
   `store_assets/screenshots/raw/` and aborts with "raw/ is empty" otherwise.
   Corrected in `test_driver/integration_test.dart`.

4. **`Icons.arrow_back` would have broken every iOS harness run.**
   The harness navigated back by tapping that icon; iOS AppBars insert
   `arrow_back_ios_new`. Replaced with `tester.pageBack()`, which resolves
   whichever the platform used. Not observed as a failure because the run was on
   Android — it would have surfaced first in the publish stage.

---

## 5. Findings for stages 4a / 4b

Everything below is pinned by a passing test that documents the behaviour as it
is today, so a change fails loudly. None of them block the gate.

1. **Hysteresis holds a large upward jump at the old level entirely.** *(medium)*
   `SignalScoring.bars` compares only against the boundary of the level it is
   moving to. Coming from 0 bars, a composite of 0.51 maps to 3 bars, fails to
   clear 0.53, and is sent back to **0** — "No usable connection" on a workable
   link — instead of stepping to the level below. It self-heals once the
   composite leaves the 0.03 band, but a connection sitting just inside a
   boundary while recovering from an outage reads as dead. Pinned in
   `scoring_boundaries_test.dart`. A fix would clamp the rejected move to
   `previousBars ± 1` rather than rejecting it outright.

2. **`probesSent` reports the planned count, not the sent count.** *(low)*
   After the early abort, `probesSent` is 4 while two probes were actually sent
   and only two were charged to the budget. The home screen prints this verbatim
   as "4 sent this cycle". For an app whose pitch is honesty about numbers, that
   line is wrong on exactly the failure it is best at detecting. Pinned in
   `measurement_engine_edges_test.dart`.

3. **Two throughput formatters disagree.** *(low)*
   `Format.throughput` renders 48000 kbps as `48 Mbps`; `IndicatorText.throughput`
   renders it as `48.0 Mbps`. The spec says the notification wording lives in one
   place so it cannot drift from the in-app wording — it already has. Both are
   pinned.

4. **A totally unresponsive but lossless link floors at 2 bars.** *(low,
   calibration)* Loss and jitter both score 1.0 when every probe answers at
   1500 ms with no variation, which is 45% of the weight, so the composite cannot
   fall below 0.45. The transfer-failure cap independently pulls that case to 2,
   so the observable result is defensible — but the floor is arithmetic, not
   design, and is worth a deliberate decision.

5. **`SignalScoring.verdict(-1)` returns "Excellent".** *(trivial)* The switch's
   default arm catches anything that is not 0–4. Unreachable today because
   `bars()` cannot return a negative.

6. **Unflexed `Text` inside a `Row` in `FreshnessLine` and `BudgetMeter`.**
   *(low, accessibility)* Neither row's text can shrink: `FreshnessLine`'s
   "Measured …" line and `BudgetMeter`'s "6.0 MB / 25 MB" figure both take their
   natural width with no `Flexible`, `Expanded` or `overflow`. ui-designer fixed
   the *label* side of the budget header at stage 2, but the figure beside it is
   still unbounded.

   **This is not a confirmed device defect.** It only reproduces under the test
   font: `flutter_test` renders in Ahem, where every glyph is a full em square,
   so a string measures roughly twice its real width. Measured at 360 dp and
   1.6x text scale, `FreshnessLine` overflows by 33 px and the budget header by
   24 px; at 411 dp both fit. On a real device with a proportional font the same
   strings are about half as wide and fit comfortably. It would become real at
   the largest iOS accessibility sizes (which reach ~3.1x) on a narrow handset.

   The fix is one line in each: wrap the text in `Flexible` with
   `TextOverflow.ellipsis`. The layout matrix is capped at 1.3x because of this;
   raise it to 1.6x once they are wrapped.

7. **Test-only note for reviewers:** `FakeIapGateway.emit` awaits a
   zero-duration delay and therefore deadlocks inside a widget test, where the
   clock is fake. `emitNow` exists for that case and is documented at the call
   site. Anyone adding widget tests around purchases should use it.

---

## 6. Latest run

**2026-08-08**, Flutter 3.44.4 stable, Dart 3.12.2, on macOS 26.5.2 (arm64).

| Gate | Command | Result |
|---|---|---|
| Static analysis | `flutter analyze` | **No issues found** (exit 0) |
| Unit + widget | `flutter test` | **255/255 passing** (exit 0) |
| Screenshot harness, free tier | `flutter drive … SCREENSHOT_MODE=true SCREENSHOT_TIER=free -d emulator-5554` | **All tests passed** (exit 0) — 6 PNGs in `raw/`, 6 distinct md5s |
| Screenshot harness, Pro tier | same without `SCREENSHOT_TIER` | 5 PNGs (no `05_pro`, correct for this tier) |

The harness ran against a booted Android emulator (`sdk gphone64 arm64`,
Android 16 / API 36). Screenshots landed in `store_assets/screenshots/raw/`; the
files currently there are from the **free-tier** run, in light appearance. Stage
7 must re-capture with `SCREENSHOT_TIER` unset for the marketing set —
`render.sh` now refuses to frame a free-tier capture.

All of the above includes the stage-2 design changes to the theme, widgets and
screens, plus the metric-tile fix that came out of this stage — the suite and
the harness were both re-run after they landed.

Baseline entering this stage was 81 tests; 174 were added.
