# True Signal — Code Review

Stage 4a artifact. Written by mobile-code-reviewer, 2026-08-08.
Scope: full codebase — Dart (`lib/`, 45 files) and the Kotlin native layer
(`android/app/src/main/kotlin/com/froggyeye/truesignal/`, 8 files).

Baseline confirmed at review time: `flutter analyze` **No issues found**,
`flutter test` **255/255 passing**.

Every finding below was verified by executing code, not by reading alone. The
verification probes were temporary and have been removed; the exact commands and
outputs are quoted with each finding so the fixer can reproduce them.

---

## CODE QUALITY SCORE

**6.5 / 10.**

The architecture is genuinely good and the reasoning is unusually well
documented: clean feature/domain/data/presentation layering, four injectable
seams (`ProbeClient`, `ConnectivitySource`, `BudgetStore`, `IapGateway`) that let
the whole engine be driven from fakes, a scoring model that is pure functions
with the formula living in exactly one language, and comments that explain *why*
rather than *what* (the Hive 32-bit key limit, the `specialUse` vs `dataSync`
choice, the `IntrinsicHeight` grid rationale, the `buyNonConsumable`
busy-flag contract). The purchase flow is correct, including acknowledgement —
the thing that most often ships broken.

The score is held down by two defects that the layering itself introduced. The
provider graph rebuilds a stateful, self-scheduling controller as if it were a
value, and the scoring model's hysteresis rule is written against the wrong
boundary. Both are small edits; both currently break the app's headline feature.

## PERFORMANCE RISK LEVEL

**Medium.**

Nothing here burns battery or data at a rate that would draw a platform
complaint: the background cadence is Kotlin-driven with a hard 30 s floor, the
foreground/background double-probe interlock exists, the daily budget is a real
hard stop that fails closed, and the 18 pre-rendered drawables avoid runtime
bitmap work on the notification path. The risks that remain are (a) settings
sliders that persist to disk and reconfigure the Android service on every
pointer move, (b) the history screen re-parsing the whole Hive box on every
controller notification, and (c) an ironic one — the app currently *under*-uses
resources, because measurement stops entirely after the first settings change
(C1).

---

## CODE QUALITY ISSUES

### C1 — Changing any setting permanently stops all measurement (Critical)

- **Location**: `lib/app/providers.dart:94-111` (`measurementControllerProvider`),
  interacting with `lib/features/measurement/presentation/screens/home_screen.dart:32-36`
  and `lib/features/measurement/data/measurement_controller.dart:67-99`.
- **Severity**: **Critical**
- **Why it matters**: this is the app not working.

`measurementControllerProvider` calls `ref.watch(effectiveSettingsProvider)` at
line 102 to pass the initial settings. `AppSettings` defines no `operator ==`, so
every recomputation of `effectiveSettingsProvider` yields an instance Riverpod
considers different, and `ref.watch` therefore **disposes and rebuilds the
controller** on every settings change.

`MeasurementController.start()` is called from exactly one place — `HomeScreen`'s
`initState` post-frame callback — which does not run again, because pushing
`/settings` keeps the home screen's `State` alive. The replacement controller
therefore has `_started == false` forever, which means:

- no periodic timer (`_scheduleTimer` is never called),
- no connectivity subscription,
- `setForeground()` returns at its `if (!_started) return` guard, so
  `setUiActive(false)` is **never sent to the Android service**, and the
  service's `runCycle()` keeps short-circuiting on `uiActive` (`TrueSignalService.kt:214`).

So both isolates stop. The UI meter freezes, the status-bar indicator freezes,
and the ongoing notification keeps presenting the last value as the live
connection quality. Only a full process restart recovers it. The manual
"Measure now" button and pull-to-refresh still work, because `measureNow()` does
not check `_started` — which is exactly what makes the failure look like a
glitch rather than a stoppage.

There is a second, debug-only symptom from the same cause: the `ref.listen` at
line 105 fires `applySettings` on the just-disposed controller, and
`applySettings` calls `notifyListeners()` unconditionally at
`measurement_controller.dart:107`, throwing:

```
A MeasurementController was used after being disposed.
  ChangeNotifier.notifyListeners (package:flutter/src/foundation/change_notifier.dart:414:27)
  MeasurementController.applySettings (…/measurement_controller.dart:107:5)
```

`debugAssertNotDisposed` is behind an `assert`, so this throws in debug and
profile and is compiled out of release — but the functional stoppage above is
present in **all** build modes.

**Verified end to end** by pumping the real `TrueSignalApp` through the real
provider graph with the four seams faked, seeding `hasSeenOnboarding: true` so
the router lands on Home:

```
PROBE7 probes sent in the first ~12s: 12          <- 3 cycles, working normally
   … user changes themeMode …
PROBE7 probes at the moment of the settings change: 12
PROBE7 probes after a further ~36s: 12
PROBE7 NEW PROBES AFTER THE SETTINGS CHANGE: 0
PROBE7 uiActive messages seen by the Android bridge: [true]
```

`uiActive: [true]` with no matching `false` is the second half of the failure:
the background service stays suppressed.

Note that `indicatorControllerProvider` (lines 77-88) already does this
correctly — it watches only the stable channel provider and reacts to settings
through `ref.listen`. `measurementControllerProvider` should follow it.

### C2 — Hysteresis reports a healthy connection as "No usable connection" (Critical)

- **Location**: `lib/features/measurement/domain/scoring.dart:153-164`; amplified
  by `lib/features/measurement/data/measurement_controller.dart:144`.
- **Severity**: **Critical**
- **Why it matters**: the product's entire claim is that this number is honest.
  This is the number being wrong, in the direction of maximum alarm, in the
  scenario the app was built for.

QA raised this as *medium* (TEST_PLAN §5.1) on the 0.51 case. Measuring the
whole range shows it is considerably worse than that.

When the level moves **up**, the code tests the composite against the threshold
of the level it is moving *to* (`barThresholds[result]`), not the boundary it is
actually crossing. A jump of more than one level therefore essentially always
fails the test, and the reading is rejected **entirely** — sent back to the old
level rather than stepped toward the new one:

```
PROBE2 composite=0.33 raw=2 fromPrevious0=0 verdict="No usable connection"
PROBE2 composite=0.51 raw=3 fromPrevious0=0 verdict="No usable connection"
PROBE2 composite=0.69 raw=4 fromPrevious0=0 verdict="No usable connection"
PROBE2 composite=0.86 raw=5 fromPrevious0=0 verdict="No usable connection"
```

A composite of **0.86 is a five-bar connection** and it displays *"No usable
connection — Requests are timing out. Data is not getting through."*

It does not self-heal, because the rejected reading becomes the next cycle's
`previousBars`:

```
PROBE2 repeated cycles at composite 0.51 from 0 bars: [0, 0, 0, 0, 0, 0]
```

The trap band is 0.03 wide above each of the five thresholds, so roughly 15% of
possible recovery composites land in it, and the app stays wrong for as long as
the connection sits there. The failure is asymmetric — downward moves test
against `barThresholds[previousBars]`, which is correct, so drops of any size
pass straight through.

`MeasurementController` makes it worse on launch. Line 144 passes
`previousBars: _state.hasReading ? _state.sample.bars : null`, and `_state.sample`
is initialised from `_history.latest()` — the last *stored* sample, possibly
many hours old. A user whose last session was during an outage (which is when
people open this app) gets their next cold start hysteresis-compared against a
stale 0, so the very first reading on the hero screen can read "No usable
connection" on a perfect connection.

Worst-case error under the current rule, swept across all previous levels and
composites: **5 bars**.

### M1 — `uiActive` is a one-shot latch with no re-assertion or expiry (Major)

- **Location**: `TrueSignalService.kt:90,132-134,214`; `IndicatorPlugin.kt:76-89,177-179`;
  `lib/features/measurement/data/measurement_controller.dart:74,88`.
- **Severity**: **Major**
- **Why it matters**: the mechanism that makes C1 kill the status-bar indicator
  is independently reachable, so fixing C1 alone leaves the same failure behind
  three other doors.

The service suppresses its whole measurement loop on a single boolean that is
only ever changed by an edge-triggered message from Dart, with no
acknowledgement, no re-assertion and no timeout. Every path that loses one
message leaves the indicator permanently frozen while it continues to display a
stale reading as live:

1. `IndicatorPlugin.send()` (line 177) wraps `startService` in `runCatching` and
   swallows the failure. Its comment says "losing the message costs a stale icon
   for one cycle" — that is not right. Nothing re-sends `setUiActive(false)`, so
   losing it costs a stale icon *forever*. This is the exact message most likely
   to be lost, because it is sent on the way to the background, which is when
   `startService` throws `IllegalStateException`.
2. `setUiActive` is dropped entirely when `TrueSignalService.isRunning` is false
   (`IndicatorPlugin.kt:77`). So when a user turns the indicator on while the app
   is open, `start()`'s earlier `setUiActive(true)` was discarded and the fresh
   service comes up with `uiActive = false` — it then runs a full background
   cycle (including a 120 KB transfer, since `_lastTransferAt == null`) in
   parallel with the UI isolate, which is precisely the double-spend the design
   says it prevents.
3. C1's `!_started` early return.

`cycleInFlight` (`TrueSignalService.kt:92,214`) has the same shape: if the
background engine dies without answering the method call, no callback fires, the
flag stays true, and the indicator freezes with no recovery short of toggling it
off and on.

### M2 — The Pro floating bubble never updates unless the status-bar indicator is also on (Major)

- **Location**: `OverlayService.kt:46` (`publish`), reached only from
  `TrueSignalService.kt:129,232`; `IndicatorPlugin.kt:61-74` (`publishSample`
  guarded by `TrueSignalService.isRunning`); settings UI at
  `settings_screen.dart:32-52` and `overlay_setup_screen.dart:103-114`.
- **Severity**: **Major**
- **Why it matters**: it is half of the £2.99 Pro proposition, and the two
  settings are presented to the user as independent.

`OverlayService.publish()` is called from exactly two places, both inside
`TrueSignalService`. The UI isolate's `publishSample` is also dropped when the
service is not running. So with "Status-bar indicator" switched off and
"Floating indicator" switched on — a combination the settings screen offers with
no warning, and an attractive one for a user who does not want a permanent
notification — the bubble renders its initial state (`lastBars = 0`, the red
"dead" colour) and never changes, in the foreground or the background.

Secondary: `OverlayService` is a plain `Service`, so without the foreground
service in the same process keeping it alive, Android's background execution
limits will stop it; `START_STICKY` then churns it back. The overlay is
effectively dependent on the notification indicator both for data and for
lifetime, and nothing in the code or the UI says so.

### M3 — A lossless but unusable link reports 3 bars, "Workable" (Major)

- **Location**: `lib/features/measurement/domain/scoring.dart:99-126` (blend and
  renormalisation), `58-66` (`latencyScore` floors at 600 ms).
- **Severity**: **Major**
- **Why it matters**: this is the second way the headline number can be
  confidently wrong, and unlike C2 it is a design consequence rather than a slip.

QA raised this (TEST_PLAN §5.4) as a low/calibration note, reasoning that the
transfer-failure cap rescues the observable result. It does — but only on cycles
that actually attempted a transfer. Sweeping the no-throughput case:

```
PROBE3 latency=700.0  jitter=20.0 composite=0.578 bars=3 verdict="Workable"
PROBE3 latency=1500.0 jitter=20.0 composite=0.578 bars=3 verdict="Workable"
PROBE3 latency=5000.0 jitter=20.0 composite=0.600 bars=3 verdict="Workable"
PROBE3 latency=5000.0 jitter=60.0 composite=0.493 bars=2 verdict="Slow"
```

With throughput absent, the weights renormalise over loss (0.30), latency (0.30)
and jitter (0.15). A lossless link scores a flat 1.0 on 0.30 of that 0.75, so the
composite cannot fall below **0.40** however bad the connection is; with jitter
also low it reaches 0.60, which is 3 bars — *"Browsing and standard video work"*
— on a link with five-second round trips. Latency saturates at 600 ms
(`latencyWorstMs`), so 700 ms and 5000 ms are indistinguishable to the model.

The app enters the no-throughput state routinely and by design: every background
cycle between the 10-minute transfer samples once the 5-minute carry-over has
expired, and *every* cycle after the daily data budget is spent — a state
`budget_meter.dart:73-75` advertises as normal ("Transfer samples paused until
midnight. Latency probes continue."). Those are exactly the cycles that drive the
status-bar icon.

---

## PERFORMANCE ISSUES

### P1 — Settings sliders persist and reconfigure on every pointer move (Minor)

`_IntervalTile` and `_BudgetTile` (`settings_screen.dart:317-323, 344-353`) pass
`Slider.onChanged` straight to `SettingsController.update`, which writes the
whole settings map to Hive (`settings_controller.dart:16-20`). A drag emits one
event per pointer move, so a single slider drag is dozens to hundreds of disk
writes. Riverpod coalesces the *downstream* graph work to roughly one flush per
frame, but that per-frame work is not cheap either: a full `MeasurementController`
teardown and rebuild (C1) plus `IndicatorController.sync`, which is 4-7 platform
channel round trips ending in a `startService` intent that makes the Kotlin
service call `restartLoop()`.

**Root cause**: no commit/preview split. `Slider` already provides
`onChangeEnd` for exactly this.

### P2 — The history screen re-parses the whole Hive box on every notification (Minor)

`history_screen.dart:25-27` calls `controller.historySince(_window)` inside
`build()`, and the screen `ref.watch`es the controller, which calls
`notifyListeners()` about five times per measurement cycle (budget refresh,
`measuring: true`, sample, `measuring: false`). `HistoryRepository.since()`
iterates every row in the box, constructs a `SignalSample` for each, and sorts
(`history_repository.dart:62-73`); `_Stats.from` then walks the list three more
times and sorts again. With 25-hour retention that is up to a few thousand
allocations per rebuild, in bursts of five, every five seconds, on the UI
isolate. Not a freeze, but avoidable jank on low-end hardware.

### P3 — Throughput is systematically flattered on high-latency links (Minor)

`MeasurementEngine._toKbps` (`measurement_engine.dart:170-174`) subtracts
`2 × medianRttMs` from the elapsed time on **every** transfer, floored at 25% of
elapsed. The floor caps the correction at a **4× inflation** of the reported
speed. Two issues: the `http.Client` is long-lived and keep-alive, so transfers
after the first in a session have already paid their setup cost and are being
discounted for it a second time; and the median RTT comes from the rotating
gstatic/cloudflare probe hosts, not from `speed.cloudflare.com`. The bias is
largest precisely where latency is worst — i.e. it flatters the connections this
app exists to expose. It is documented as deliberate in PRODUCT_SPEC §5, so it is
listed as calibration to revisit rather than a defect, but the interaction with
M3 is worth a decision.

### Things that are right, and worth keeping

- The re-entrancy guard in `measureNow` is claimed **synchronously before the
  first await** (`measurement_controller.dart:116-117`) — the correct way to do
  it, and the comment says why.
- The budget fails **closed** on a broken channel (`budget_store.dart:60-67`).
- `intervalSeconds.coerceIn(30, 3600)` in `applyConfig` means no settings value
  can turn the service into a battery drain.
- `specialUse` over `dataSync` with the Android 15 six-hour cap as the stated
  reason, and the subtype string in the manifest.
- Cache-busting on probes (`probe_client.dart:128-131`) — without it a cached 204
  reports a 2 ms round trip on a dead link.
- The purchase controller acknowledges pending purchases
  (`purchase_controller.dart:132-134`), scopes entitlement to the product ID, and
  clears `busy` only from the stream.
- 18 static drawables rather than a runtime bitmap for the notification small
  icon, with the OEM-tinting rationale recorded.

---

## RECOMMENDED IMPROVEMENTS

Ordered by impact. The first two are the blocking ones.

### 1. Stop rebuilding `MeasurementController` (fixes C1)

In `lib/app/providers.dart`, read the initial settings instead of watching them,
and let the existing (already-tested) `applySettings` path do the updating:

```dart
final measurementControllerProvider =
    ChangeNotifierProvider<MeasurementController>((ref) {
  final controller = MeasurementController(
    engine: ref.watch(measurementEngineProvider),
    connectivity: ref.watch(connectivitySourceProvider),
    history: ref.watch(historyRepositoryProvider),
    budgetStore: ref.watch(budgetStoreProvider),
    indicator: ref.watch(indicatorChannelProvider),
    // read, not watch: settings changes are delivered through applySettings
    // below. Watching rebuilds this controller, which owns a timer, a
    // connectivity subscription and the service's uiActive handshake.
    settings: ref.read(effectiveSettingsProvider),
  );

  ref.listen<AppSettings>(
    effectiveSettingsProvider,
    (_, next) => controller.applySettings(next),
  );

  return controller;
});
```

Then add the two guards that should have made this loud instead of silent:

- `MeasurementController.applySettings` — return early `if (_disposed)` before
  touching `_refreshBudget`/`notifyListeners` (`measurement_controller.dart:101`).
- `MeasurementController.start()` — make it idempotent and callable again, and
  have `setForeground` fall back to `start()` rather than returning when
  `!_started`, so no future lifecycle change can strand the controller again.

Recommended regression test (there is currently none that changes a setting
through the real graph while a controller is running): pump `TrueSignalApp`,
record `FakeProbeClient.probeCalls`, change `themeMode` via
`settingsProvider.notifier`, pump 30 s, and assert the count increased and that
`FakeIndicatorChannel.uiActive` ends `false` after backgrounding.

### 2. Test the boundary being crossed, not the destination (fixes C2)

In `lib/features/measurement/domain/scoring.dart`, one line:

```dart
final boundary = result > previousBars
    ? barThresholds[previousBars + 1]   // was: barThresholds[result]
    : barThresholds[previousBars];
```

and delete the `if (!cleared) result = previousBars` clamp only for the upward
case — once the adjacent boundary is cleared, the full move is legitimate.

I swept this against the current implementation over all previous levels and
composites in 0.001 steps:

```
single-step behaviour changes (should be 0): 0
multi-step cases the proposal changes: 303
cases where the proposal is further from raw than today (should be 0): 0
worst bar error possible today: 5 bars
```

Flicker suppression is bit-for-bit unchanged (`prev=2, c=0.515 → 2`;
`prev=2, c=0.535 → 3`; `prev=3, c=0.505 → 3`), and every multi-level jump now
lands on the truth. This is preferable to the `previousBars ± 1` clamp QA
suggested, which is also correct but imposes an artificial slew rate — three
cycles to climb out of a 0-bar reading.

Additionally, do not apply hysteresis across a gap. In
`measurement_controller.dart:144`, pass `previousBars: null` when
`_state.sample.timestamp` is older than about two minutes, so a cold start after
an outage is not anchored to a stale reading.

`test/scoring_boundaries_test.dart` pins the current behaviour deliberately, so
those assertions must be rewritten as part of this change — they are the
specification of the bug, not of the intent.

### 3. Make `uiActive` a lease rather than a latch (fixes M1)

Have the UI isolate re-assert liveness with every publish, and let the service
expire it:

- Add `"uiActive" to true` to the `publishSample` payload
  (`indicator_channel.dart:66-77`), and refresh a timestamp in
  `TrueSignalService` whenever `ACTION_PUBLISH` or `ACTION_UI_ACTIVE` arrives.
- In `runCycle()`, treat the UI as active only while that timestamp is within,
  say, `max(3 × foreground interval, 60 s)`. A lost message then costs one cycle,
  as the comment already claims.
- Include the current UI-active state in the `startIndicator` config intent so a
  service starting while the app is open does not immediately double-probe.
- Give `cycleInFlight` a watchdog: `handler.postDelayed({ cycleInFlight = false }, 30_000)`
  cancelled on reply.

### 4. Feed and gate the overlay independently (fixes M2)

Either route `publishSample` to `OverlayService.publish` directly from
`IndicatorPlugin` regardless of `TrueSignalService.isRunning`, or — simpler and
more honest about the lifetime constraint — state the dependency in the UI:
disable the "Floating indicator" row with an explanatory subtitle while
`notificationIndicatorEnabled` is false, and have `IndicatorController.sync` not
start the overlay without the service. The overlay screen's promise that it
"never appears until you turn it on here" stays true either way.

### 5. Give the model a way to say "slow" without a transfer sample (addresses M3)

Options, cheapest first:

- Raise `latencyWorstMs` from 600 ms, or add a second knee, so 700 ms and 5000 ms
  are not scored identically.
- Cap bars by latency alone — a median RTT above ~1 s cannot be more than 1 bar
  whatever else is true, in the same spirit as the existing severe-loss and
  transfer-failure caps, which are the model's established mechanism for "one
  measurement is damning on its own".
- Do not award full marks for loss when nothing else was measurable: scale the
  loss sub-score by the latency sub-score when throughput is absent.

The first two are small and testable; the third changes the model's shape and
should be a deliberate product decision. Whichever is chosen, PRODUCT_SPEC §5 and
the in-app "How the score works" screen both have to move with it — the spec
requires all three to agree.

### 6. Report probes actually sent (QA §5.2, Minor)

`measurement_engine.dart:73-76` sets `failures = targets.length` on early abort,
which is right for `lossRatio` but corrupts `probesSent`. Verified:

```
PROBE4 probesSent=4 bytesUsed=1400 loss=1.0     (probes cost 700 bytes each)
```

The home screen prints "4 sent this cycle" (`home_screen.dart:216`) next to a
data counter that moved by two probes' worth. Track attempts in a separate
counter and set `lossRatio = 1.0` explicitly:

```dart
var attempted = 0;
// … attempted++ per iteration …
if (failures >= 2 && rtts.isEmpty) { abortedDead = true; break; }
final probesSent = math.max(attempted, 1);
final lossRatio = abortedDead ? 1.0 : failures / probesSent;
```

### 7. One throughput formatter (QA §5.3, Minor)

Verified drift, confined to values at or above 10 Mbps:

```
PROBE5 kbps=48000.0 in-app="48 Mbps"   notification="48.0 Mbps"
PROBE5 kbps=9500.0  in-app="9.5 Mbps"  notification="9.5 Mbps"
```

`IndicatorText.throughput` (`indicator_text.dart:22-24`) should delegate to
`Format.throughput` (`formatters.dart:6-14`), which is where PRODUCT_SPEC says
the wording lives. `Format` is in `core/` and `IndicatorText` in
`features/measurement/domain/`, so the dependency direction is fine.

### 8. Smaller items

- **Slider debounce** (P1): move `controller.update` to `Slider.onChangeEnd` and
  hold the in-flight value in local widget state for the label.
- **Notification freshness**: the in-app UI is scrupulous about the age of a
  reading (`FreshnessLine`), but the notification shows none —
  `TrueSignalService.buildNotification` sets `setShowWhen(false)`, suppressing
  even the platform's own timestamp. During Doze the handler-driven loop is
  deferred, so the status bar can assert "Excellent" for hours after a
  connection died. Append the measurement time to the detail line, or use
  `setShowWhen(true)` with `setWhen(sampleTimestamp)`.
- **Overlay position is never clamped** (`OverlayService.kt:153-161` with
  `FLAG_LAYOUT_NO_LIMITS`): the bubble can be dragged off-screen, and the
  position persists to prefs, so it stays unreachable — including the long-press
  that is meant to be its escape hatch. Clamp to display bounds on `ACTION_UP`
  and on `showBubble`. Also handle `ACTION_CANCEL`, which currently loses the
  drag.
- **BootReceiver does not re-check notifications** (`BootReceiver.kt:19-26`): if
  the user revoked the notification permission since enabling the indicator, the
  service restarts on boot and measures with nothing visible. Gate on
  `NotificationManagerCompat.from(context).areNotificationsEnabled()`.
- **Connectivity change during an in-flight cycle is dropped**
  (`measurement_controller.dart:190-195` hitting the `_inFlight` guard at 116):
  set a `_remeasureRequested` flag and honour it in the `finally`.
- **Dead code**: `SettingsRepository.loadBudget` / `saveBudget`
  (`settings_repository.dart:25-35`) have no callers, yet PRODUCT_SPEC §7 lists a
  "budget mirror" in the settings box as part of the storage design — delete the
  methods or delete the claim. `MeasurementController.backgroundTransferInterval`
  (line 45) is never used by the controller and duplicates
  `BackgroundMeasurementHost.transferInterval`; keep one.
  `MeasurementEngine.dispose()` (line 200) is never called, and would close a
  client that `probeClientProvider` also closes.
- **`SignalScoring.verdict(-1)` returns "Excellent"** (QA §5.5): unreachable
  today, but the default arm should be the safe end. Change `_ =>` to `5 =>` plus
  an explicit fallback, or clamp on entry.
- **`BackgroundMeasurementHost` uses `DateTime.now()` directly** (line 84) while
  the engine and the foreground controller both take an injected clock; QA
  flagged this as the reason the ten-minute transfer expiry is untestable. Add a
  `clock` parameter for symmetry.

---

## ARCHITECTURE IMPROVEMENTS

**The layering is sound; keep it.** Two structural notes, both narrow.

**1. Long-lived controllers must not be `ref.watch` dependents.** C1 is not a
typo, it is a category error that the graph makes easy: `MeasurementController`
owns a timer, a stream subscription, a cycle counter and a handshake with a
native service, but it is wired as though it were a derived value.
`indicatorControllerProvider` right beside it gets this right. The rule worth
writing down in the file: *a provider that constructs an object owning a
subscription, a timer or native state takes its dependencies by `ref.read` and
receives updates by `ref.listen`; only pure derivations `ref.watch`.* Applying
that consistently is a five-line change today and prevents the next instance.
Adding `operator ==`/`hashCode` to `AppSettings` would blunt the symptom, but the
ownership rule is the actual fix and should land regardless.

**2. The cross-process indicator handshake needs to be state-based, not
event-based.** `uiActive`, `cycleInFlight` and `isRunning` are three pieces of
service state maintained by unacknowledged one-way messages across a process
boundary that Android is free to interrupt. The recommendation in §3 above
(timestamped leases with expiry) is the standard fix and keeps Kotlin owning the
timing, which is the right call and well argued in the existing comments.

**Migration path**: all of the above is local. §1 is one file, §2 is one
expression plus a rewrite of `scoring_boundaries_test.dart`, §3 is confined to
`TrueSignalService.kt` + `IndicatorChannel`, §4 is a UI gate. None of it touches
the feature layout, the seams, the storage schema or the purchase flow. No data
migration. The one thing that must move together is §5: the model, PRODUCT_SPEC
§5 and the "How the score works" screen are contractually required to agree.

---

## Findings by severity

| Severity | Count | IDs |
|---|---|---|
| Critical | 2 | C1, C2 |
| Major | 3 | M1, M2, M3 |
| Minor | 12 | P1, P2, P3, and the nine items under Recommended Improvements §6-§8 |

## Re-verification note for the fix round

The three probes that produced the quoted evidence should be re-run by this
reviewer, not self-certified by the fixer: the end-to-end "probes after a
settings change" reproduction (C1), the hysteresis sweep against an independent
re-implementation of the rule from PRODUCT_SPEC §5 (C2), and the no-throughput
composite sweep (M3). For C2 in particular, a shared helper used by both the
model and its tests would let the two agree while both being wrong; the sweep
must be written from the spec.

---

## Fix round — what changed (flutter-architect, 2026-08-09)

Recorded so this reviewer can re-run the three probes against a known state.
**The verdict line below is deliberately unchanged** — flipping it belongs to
the re-verification, not to the fixer.

| ID | Change | How it was checked here |
|---|---|---|
| C1 | `providers.dart` now takes `settings: ref.read(effectiveSettingsProvider)` and updates through the existing `ref.listen → applySettings`, as recommended. `applySettings` returns early when `_disposed`; `setForeground` falls back to `start()` when `!_started`. | `test/provider_graph_regression_test.dart` was rewritten. It had been asserting liveness with a manual `controller.measureNow()`, which passes against a stranded controller because `measureNow` does not check `_started`. It now waits out the real 5 s foreground timer and emits a transport change, touching the controller only for the final `setForeground(false)`. Confirmed to fail when `ref.read` is reverted to `ref.watch`, and pass when restored. |
| C2 | `scoring.dart` tests the boundary being crossed (`barThresholds[previousBars + 1]`) on the way up; the clamp is kept, so an uncleared boundary still holds the previous level. | Swept against a hand transcription of PRODUCT_SPEC §5 written from the prose, not from any helper the model shares: **112,560 cases across previousBars × latency × loss × cap × composite, 0 mismatches**. The four evidence cases from 0 bars now read 0.33→2, 0.51→3, 0.69→4, 0.86→5. `scoring_boundaries_test.dart` was rewritten to specify the intent. |
| M1 | `uiActive` is now a 60 s renewable lease (`UI_ACTIVE_LEASE_MS`, `renewUiLease`/`isUiActive`); every `publishSample` carries `uiActive: true` so a foreground reading renews it; the `startIndicator` config intent carries `uiActive`, closing the "service starts while the app is open → double-probe" path; `cycleInFlight` has a generation-stamped watchdog (`finishCycle`) that ignores late callbacks. | Source review only — the handshake needs a device. |
| M2 | The dependency is now stated rather than hidden: `IndicatorController.sync` will not start the overlay unless `notificationIndicatorEnabled`, the Settings row subtitle says "Requires the status-bar indicator to keep its score current", and `overlay_setup_screen.dart` gates with "Turn on the status-bar indicator first." | Covered by `indicator_controller_test.dart`. |
| M3 | Two latency caps rather than one: `poorLatencyBarCap = 2` at ≥600 ms (where the latency sub-score already reaches zero) and `unusableLatencyBarCap = 1` at ≥1,000 ms. | The no-throughput sweep now reads 700 ms → **2 bars "Slow"** (was 3, "Workable"), 1500 ms and 5000 ms → 1 bar. New boundary tests pin 599.9/600/999.9/1000 ms. PRODUCT_SPEC §5 and the in-app "How the score works" screen were both moved with it; §5's blend paragraph, which still described only the 1,000 ms cap and therefore contradicted its own "Composite → bars" section, was corrected. |
| §6 probesSent | `measurement_engine.dart` counts `attempted` separately and sets `lossRatio = abortedDead ? 1.0 : failures / probesSent`. | The home screen's "N sent this cycle" now matches the bytes charged. |
| §7 formatter | `IndicatorText.throughput` delegates to `Format.throughput`. | The `48 Mbps` / `48.0 Mbps` drift is gone. |

Not attempted in this round, and still open from §8: slider debounce (P1), the
history screen's per-notification re-parse (P2), notification freshness, overlay
position clamping, `BootReceiver` notification re-check, the dropped
connectivity change during an in-flight cycle, the dead `loadBudget`/`saveBudget`
pair, `verdict(-1)`, and `BackgroundMeasurementHost`'s direct `DateTime.now()`.

Gates at the end of the round: `flutter analyze` **No issues found**;
`flutter test` **268/268 passing, 0 skipped**; `flutter build apk --release`
**succeeds** (52.9 MB).

---

## Re-verification (mobile-code-reviewer, 2026-08-09)

All five blocking findings are fixed. Verified by executing code against the
current tree, not by reading the fix notes: the checker for C2/M3 was written
from `docs/PRODUCT_SPEC.md` §5 prose rather than from `scoring.dart` or from
anything the fix round added, so the model and the check cannot be wrong
together. Probes were temporary and have been removed.

| ID | Result | Evidence |
|---|---|---|
| C1 | **Fixed** | Pumped the real `TrueSignalApp` through the real provider graph, changed three unrelated settings (theme, budget, cellular opt-out) in succession: `controller survived: true`; probes `before=12 atChange=12 after=40` → **28 new probes** in the following 36 s, against **0** before the fix. `uiActive on backgrounding: [false]` — the service is now released, so the background loop resumes. |
| C2 | **Fixed** | `0.16→0`, `0.33→2`, `0.51→3`, `0.69→4`, `0.86→5` from 0 bars; repeated cycles at 0.51 now `[3,3,3,3,3,3]` (was `[0,0,0,0,0,0]`). Flicker suppression bit-for-bit unchanged: `prev2@0.515=2`, `prev2@0.535=3`, `prev3@0.505=3`. |
| C2+M3 | **Fixed** | Independent sweep over 7 `previousBars` × 1,001 composites × 7 latencies × 4 loss ratios (~196k cases) against the spec transcription: **0 mismatches, worst bar delta 0**. |
| M1 | **Fixed (source review)** | Lease renewed on `ACTION_PUBLISH` and `ACTION_UI_ACTIVE`, cleared on `false`, carried on the start intent; `isUiActive()` is a timestamp comparison, so a lost message costs one lease period rather than forever. Watchdog is generation-stamped and `finishCycle` correctly ignores a late callback. Still needs a device (M1/M3 in TEST_PLAN §3). |
| M2 | **Fixed** | `sync` requires `notificationIndicatorEnabled` before starting the overlay; the settings subtitle and the overlay screen both state the dependency. This was the option that matches the lifetime constraint rather than papering over it. |
| M3 | **Fixed** | No-throughput sweep: 700 ms → **2 "Slow"** (was 3, "Workable"), 1500 ms and 5000 ms → **1 "Barely usable"**. A good link is untouched (25 ms/3 ms/48 Mbps → 5). |
| §6 | **Fixed** | Early abort now reports `probesSent=2` alongside `bytesUsed=1400` — the two agree. Partial loss still reports all four (`probesSent=4, bytes=2800, loss=0.5`), so no regression. |
| §7 | **Fixed** | 0 disagreements between `Format.throughput` and `IndicatorText.throughput` across the range; 48000 kbps reads `48 Mbps` in both. |

The regression test was independently checked rather than taken on trust:
reinstating `ref.watch` in `providers.dart` makes
`test/provider_graph_regression_test.dart` fail on its `identical(...)`
assertion, and restoring `ref.read` makes it pass. The file was restored and the
gates re-run afterwards.

**Gates confirmed by this reviewer on the current tree**: `flutter analyze`
**No issues found**; `flutter test` **268/268 passing**.

### Three observations from the fix round — all Minor, none blocking

- **N1 — the latency caps reintroduce the flicker hysteresis exists to prevent.**
  The caps are step functions applied *after* hysteresis, so hysteresis cannot
  damp them. A median RTT oscillating either side of a knee alternates the
  reading every cycle, with the composite perfectly steady:
  ```
  latency alternating 595/605 ms, composite steady at 0.60: [3,2,3,2,3,2,3,2,3,2]
  latency alternating 990/1010 ms:                          [2,1,2,1,2,1,2,1,2,1]
  composite alternating 0.495/0.505 (damped, for contrast): [2,2,2,2,2,2,2,2,2,2]
  ```
  This is the failure the model's own comment calls "reads as a broken app", now
  on the latency axis, and the status-bar icon changes with it. The pre-existing
  caps share the shape but are far less exposed — with four probes, loss is
  quantised to 0/25/50/75/100% and cannot hover at ⅓, whereas latency is
  continuous and a link sitting near 600 ms is ordinary. Fix: give the caps
  their own hysteresis band (engage at ≥600 ms, release below ~550 ms), or apply
  them to the composite before the bar mapping so the existing damping covers
  them.
- **N2 — the UI lease is a flat 60 s while the Pro foreground interval also
  maxes at 60 s.** `UI_ACTIVE_LEASE_MS = 60_000` is renewed by each publish, so a
  Pro user on a 60 s foreground interval leaves a gap equal to the cycle
  duration between lease expiry and the next renewal; a service tick landing in
  that gap runs the duplicate cycle M1 exists to prevent. The default 5 s
  interval is unaffected. Fix: carry the foreground interval in the publish and
  lease `max(3 × interval, 60 s)`, as originally recommended.
- **N3 — the caps key off an RTT that includes connection setup.** Probes rotate
  across three hosts, so on a cold `http.Client` pool three of the four probes in
  a cycle pay DNS+TCP+TLS, and the first cycle after opening the app is the most
  exposed — it is also the one the user sees immediately. A slow-to-connect but
  usable link can therefore trip the 600 ms cap. Pre-existing (the sub-score
  already scored those zero), and the new direction of error is the safe one for
  this product, but worth folding into P3 when throughput calibration is
  revisited.

### Still open, unchanged

The twelve Minor items from §8 remain unfixed and are explicitly passed with
recommendations, joined by N1-N3 above. N1 is the one I would take first — it is
small, it is a regression rather than pre-existing debt, and it degrades the
headline indicator. P1 (slider debounce) and P2 (history re-parse) are the next
best value. None of them blocks release.

## N1 / N2 pass (flutter-architect, 2026-08-09)

Both taken. N3 and the twelve §8 Minors deliberately left for a point release.

**N1 — latency caps now carry their own hysteresis.** Of the two options
offered, the composite-clamp one does **not** work, and it is worth recording
why so it is not re-suggested: the discontinuity is on the latency axis and
never reaches the composite, so clamping the composite still alternates. Traced
at the 600 ms knee — clamp high (just under 0.50) and the cap cannot engage at
all, because falling from 3 bars needs ≤0.47; clamp to 0.47−ε and it engages,
but the 595 ms cycle is unclamped at 0.60, clears 0.53, and goes straight back
to 3. Either way still `[3,2,3,2,…]`.

Implemented the release-band option instead. `poorLatencyReleaseMs = 550`,
`unusableLatencyReleaseMs = 900`; a cap engages at its threshold and holds until
latency falls below the release figure, with "currently engaged" inferred from
`previousBars` being a reading that cap could have produced — so `bars` stays a
pure function and the model keeps no hidden state. The cap logic is now
`SignalScoring.latencyBarCap(latencyMs, previousBars:)`, public so it can be
tested apart from the composite mapping.

The reviewer's two sequences, re-measured:

```
latency alternating 595/605 ms, composite steady 0.60:  [2,2,2,2,2,2,2,2,2,2]   (was [3,2,3,2,…])
latency alternating 990/1010 ms:                        [1,1,1,1,1,1,1,1,1,1]   (was [2,1,2,1,…])
```

Checked three ways: an oscillation test in `scoring_boundaries_test.dart` that
**fails when the release band is collapsed** (verified by setting both release
figures back to their engage figures — the set becomes `{2,3}`); a release-band
test covering 595 ms held at 2, 549.9 ms released, 595 ms from 5 bars *not*
retroactively capped, and cold start with no previous reading; and a re-run of
the spec sweep with the bands transcribed by hand into the independent
implementation — **113,120 cases, 0 mismatches**.

Because the band is a *visible* rule (a link at 570 ms can now show 2 bars), both
PRODUCT_SPEC §5 and the in-app "How the score works" screen were updated to say
so rather than leaving the screen quietly incomplete.

**N2 — the lease is now sized from the publishing cadence.**
`publishSample` carries `uiIntervalSeconds`; `TrueSignalService.renewUiLease`
takes `max(60 s, 3 × interval)`. Three intervals means two publishes must be
lost before the lease lapses, not one. A bare `ACTION_UI_ACTIVE` lifecycle
message passes 0 and falls back to the flat floor, which is correct — it is not
a cadence signal. Dart side is covered by a test asserting the *foreground*
interval travels with the reading (it would fail if the background interval were
sent, since the two differ in the fixture); the Kotlin arithmetic is source
review plus a clean compile, as it needs a device.

Gates: `flutter analyze` **No issues found** · `flutter test` **271/271, 0
skipped** · `flutter build apk --release` **succeeds** (52.9 MB, Kotlin
recompiled).

---

## N1 / N2 re-verification (mobile-code-reviewer, 2026-08-09)

Both fixed. **Verdict stays PASS.** Verified by executing code against the tree;
probes were temporary and have been removed. The Kotlin was compiled
(`./gradlew compileDebugKotlin`, exit 0) because `flutter test` does not cover
it and N2 is mostly a Kotlin change.

**The fixer is right about the rejected alternative, and I was wrong.** My second
suggestion — clamp the composite before the bar mapping so the existing
damping covers the caps — cannot work, for the reason given. I reproduced it
independently across four clamp values:

```
RW1 clampTo=0.4999 -> [3, 3, 3, 3, 3, 3, 3, 3]   cap never engages at all
RW1 clampTo=0.4699 -> [3, 2, 3, 2, 3, 2, 3, 2]   still flickers
RW1 clampTo=0.46   -> [3, 2, 3, 2, 3, 2, 3, 2]
RW1 clampTo=0.40   -> [3, 2, 3, 2, 3, 2, 3, 2]
```

Clamp high enough to sit inside the 2-bar band and the downward margin is never
cleared, so the cap does nothing; clamp low enough to engage it and the *next*
cycle is unclamped, clears the upward margin and jumps straight back. There is
no clamp value that works, because the oscillation is on the latency axis and a
composite-side margin can only ever damp composite-side movement. The band on
the latency thresholds was the right and only choice of my two.

| ID | Result | Evidence |
|---|---|---|
| N1 | **Fixed** | `595/605 ms, composite steady 0.60: [3,2,2,2,2,2,2,2,2,2]` and `990/1010 ms: [2,1,1,1,1,1,1,1,1,1]` — one transition into the cap, then stable, against `[3,2,3,2,…]` before. A wider straddle inside the band (`560/640 ms`) is also stable. |
| N1 | **No regression** | Caps still engage on the exact thresholds (599.9→5, 600→2, 999.9→2, 1000→1) and still release (595/prev2→2, 550/prev2→2, 549.9/prev2→**5**; 950/prev1→1, 899.9/prev1→2). A good reading is not retroactively capped inside the band (595 ms with prev 5/4/3 → 5), and a cold start inside the band imposes nothing (595 ms, no previous → 5). |
| N1 | **Nothing else moved** | C2 (0.16→0, 0.33→2, 0.51→3, 0.69→4, 0.86→5 from 0 bars), M3 (700→2 "Slow", 1500/5000→1), the good link (→5), composite flicker suppression (`prev2@0.515=2`, `prev2@0.535=3`, `prev3@0.505=3`) and the loss caps (0.34→1, 1.0→0) all unchanged. |
| N2 | **Fixed** | The **foreground** interval travels: `measurement_controller.dart:233` sends `_settings.foregroundIntervalSeconds` (effective settings, so a free install sends 5), `indicator_channel.dart:85` carries it, `IndicatorPlugin.kt:75` puts it on the intent defaulting to 0, and `renewUiLease` takes `maxOf(60 s, interval × 3)`. At the 60 s Pro maximum the lease is 180 s, so two publishes must be lost before it lapses — the gap that made a duplicate cycle possible is closed. A bare lifecycle message passes 0 and falls back to the floor, which is right: it is not a cadence signal. |

Gates confirmed by this reviewer: `flutter analyze` **No issues found**;
`flutter test` **271/271**; `./gradlew compileDebugKotlin` **exit 0**.

### On the in-app wording — the second opinion that was asked for

It is honest, and it is fine to ship. The screen discloses the behaviour that
would otherwise surprise someone ("why does it still say 2 bars when my ping is
570?"), which is the part that matters. One nit was raised: every other rule on
that screen names its exact figure — 600 ms, one second, a third, 120 KB, two
bars — and the cap release said "comfortably below the line", so a reader who
could reproduce every other number could not reproduce this one.

**Taken and closed, 2026-08-09.** The screen now names both release thresholds,
interpolated from `SignalScoring.poorLatencyReleaseMs` /
`unusableLatencyReleaseMs` rather than typed in, so the copy cannot quote a
threshold the model no longer uses; the step widget loses `const` as a result,
noted inline. Verified by rendering the screen and matching **hardcoded**
literals rather than the constants: `"550 ms and 900 ms"` present, and `"550.0"`
/ `"900.0"` absent — `.round()` is applied, so there is no stray decimal. Model,
PRODUCT_SPEC §5 and the screen now all name 550 ms and 900 ms.

Note for a future reader: the shipped assertion in `widgets_test.dart` builds its
expected string from the same two constants as the copy, so it pins copy-model
*agreement*, not the values themselves. That is the right job for it — the values
are pinned independently by the release-band cases in
`scoring_boundaries_test.dart` (549.9 releases, 550 holds; 899.9 releases, 900
holds). The pair together is adequate; neither alone would be.

### One property of the design, recorded rather than raised as a finding

Inferring "a cap is engaged" from `previousBars` cannot distinguish a reading the
cap produced from one the composite produced at the same level. Inside a band,
that holds a link down that was never capped: at 560 ms with the best composite
actually reachable there (0.708, raw 4 bars), a previous reading of 2 holds at 2,
where a previous reading of 3 gives 3. The error direction is conservative — a
560 ms link is not a four-bar connection — and it clears as soon as latency drops
below 550 ms. The alternative is explicit cap state in the model, which is worse:
it trades a bounded, conservative inaccuracy for hidden state in a pure function
that three call sites depend on. Keeping it pure was the right call.

### Wording nit from the N1/N2 re-verification — taken (flutter-architect, 2026-08-09)

The reviewer's point stands: every other rule on the "How the score works"
screen names its exact figure, so "comfortably below the line" was the one
number a reader could not reproduce. The screen now names both release
thresholds, **interpolated from `SignalScoring.poorLatencyReleaseMs` and
`unusableLatencyReleaseMs`** rather than retyped, so the copy cannot quote a
threshold the model no longer uses. That step widget drops `const` as a result,
which is noted inline so it is not "tidied" back.

A `widgets_test.dart` assertion pins the rendered figures to the same constants,
guarding against someone hardcoding them again. Model, PRODUCT_SPEC §5 and the
screen all name 550 ms and 900 ms.

Gates: `flutter analyze` **No issues found** · `flutter test` **271/271, 0
skipped**.

---

Verdict: PASS
