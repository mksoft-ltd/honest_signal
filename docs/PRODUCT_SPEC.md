# Honest Signal — Product Spec

Stage 1 (build) artifact. Written by flutter-architect, 2026-08-07.
Downstream stages (design, QA, code review, security, metadata, compliance,
publish) read this file as the description of what the app is and why it needs
what it asks for.

---

## 1. Product summary

Your phone's signal icon reports **radio strength** — how loudly the nearest
mast or router is shouting. It says nothing about whether data is actually
moving. Everyone has stood somewhere with five bars and a page that will not
load.

Honest Signal measures the connection instead of listening to the radio. It sends
real requests, times them, downloads a real sample, and scores what the
connection **can actually do** from 0 to 5 bars. On Android that score lives in
the status bar as a normal-looking signal icon sitting next to the OS one, so
the honest number is always visible without opening anything.

**Positioning:** the signal indicator that tells the truth.
**Studio line:** useful apps, no ads, no dark patterns.

## 2. Target users

- **People with unreliable connections** — rural areas, thick-walled buildings,
  busy trains, patchy office Wi-Fi. They already suspect their bars are lying
  and want proof.
- **People diagnosing a problem** — "is it my Wi-Fi or the site?" — who need to
  tell a dead link apart from a slow one before calling an ISP.
- **Commuters and travellers** who want to know whether a call will survive the
  next five minutes.
- **Technical users** who want latency, jitter, loss and throughput in one
  place without running a full speed test that burns a gigabyte.

Not a speed-test app. A speed test answers "how fast is this right now, if I
spend 200 MB finding out". Honest Signal answers "is this connection working, all
day, for almost no data".

## 3. Features

### MVP (built)

| Feature | Tier |
|---|---|
| Live true-signal meter: 0–5 bars, verdict, and what it means in practice | Free |
| Latency (median), jitter, packet-loss proxy, throughput estimate, network type | Free |
| Adaptive sampling — faster in the foreground, sparse in the background, immediate on network change | Free |
| Hard daily data budget with an always-visible counter | Free |
| Android status-bar indicator: foreground service whose small icon is the live score | Free |
| High-contrast status-bar icon (plate behind the mark), on by default, switchable | Free |
| Android 16: promoted ongoing chip labelled "HS" in the status bar | Free |
| Honest freshness ("measured 3 min ago"), with iOS background limits stated in-app | Free |
| "How the score works" — the full scoring method, in-app | Free |
| Onboarding that explains the premise and the one permission | Free |
| Restore purchases, privacy policy link, light/dark/system theme | Free |
| History: last hour / last 24 hours, step chart plus summary stats | **Pro** |
| Floating overlay bubble over other apps (draggable, tap to open, long-press to dismiss) | **Pro** |
| Custom sampling intervals (2 s–60 s foreground, 1 min–60 min background) | **Pro** |
| Indicator themes: bars, dots, wave — in-app and in the status bar | **Pro** |

### Later (deliberately not in the MVP)

- **iOS home-screen widget** showing the last score and its timestamp. Needs a
  WidgetKit extension target, which cannot be added from the Flutter CLI and
  would need hand-editing the Xcode project. Deferred rather than done badly.
- **iOS BGTaskScheduler refresh** so the widget has something recent to show.
  iOS grants background time on its own schedule; the app must never imply the
  number is live when it is not.
- Per-network history ("your home Wi-Fi averages 4.2 bars").
- Export history as CSV.
- Alerts when the connection drops below a chosen level.
- Automatic diagnosis text ("this looks like a captive portal").

## 4. Screen map

```
/welcome            Onboarding — the premise, then the notification permission
   └─ /             Home (start route after first run)

/                   Home — bars, verdict, freshness, metric grid, budget meter,
                    "Measure now", Pro entry point
   ├─ /history      History (Pro; ProLock when free)
   ├─ /how-it-works The scoring method, weights, and what each level means
   ├─ /pro          Paywall
   └─ /settings     Settings
        └─ /settings/overlay   Floating indicator setup + permission (Pro)
```

Routing is GoRouter; the start route is `/welcome` until onboarding completes,
then `/`.

## 5. The scoring model

Documented here, in `lib/features/measurement/domain/scoring.dart`, and in the
app's own "How the score works" screen. All three must agree — the product
claim is that the number is honest, so the method is not a secret.

### One measurement cycle

1. **Four latency probes**, sequential, 2 s timeout each, to rotating
   connectivity-check endpoints (`gstatic`, `cloudflare`). Round-trip time is
   measured from request start to the body being fully read. A cache-busting
   query parameter prevents a cached 204 from reporting a 2 ms round trip on a
   dead link. Four is the smallest count giving both a usable median and a
   meaningful loss fraction (0/25/50/75/100%).
   - **Early abort:** two failures with nothing succeeding ends the cycle at
     once. The answer is already known and the user should not wait eight
     seconds for it.
2. **Median** of the successful round trips → latency.
   **Mean absolute deviation** from that median → jitter (chosen over standard
   deviation so one outlier probe does not triple the reported figure).
   **Failures ÷ probes sent** → loss ratio.
3. **Transfer sample**, on its own slower clock (see §6): download ~120 KB from
   Cloudflare's sized-download endpoint and time it. Two round trips are
   discounted from the elapsed time to account for DNS/TCP/TLS setup, floored
   at 25% of elapsed so the correction cannot invent infinite speed. One retry
   at a third of the size before declaring failure.

### Sub-scores (each 0–1)

| Component | Curve | Perfect at | Zero at |
|---|---|---|---|
| Latency | logarithmic | ≤ 40 ms | ≥ 600 ms |
| Jitter | logarithmic | ≤ 15 ms | ≥ 200 ms |
| Throughput | logarithmic | ≥ 15 Mbps | ≤ 100 kbps |
| Loss | linear | 0% | ≥ 50% |

Log curves because the perceptual gap between 40 ms and 80 ms is far larger
than between 500 ms and 540 ms. Loss is linear because the first dropped
request matters as much as the last.

### Blend

`composite = Σ(weight × sub-score) ÷ Σ(weights present)`

| Component | Weight |
|---|---|
| Lost probes | 30% |
| Latency | 30% |
| Throughput | 25% |
| Jitter | 15% |

Weights are renormalised over whatever was measured, so a cheap latency-only
cycle is not penalised for skipping the transfer sample. A throughput reading
may be carried over for up to 5 minutes and is flagged as stale in the UI;
after that it expires rather than being reused forever. A latency-only cycle
still cannot call an interactive link healthy: median RTT ≥600 ms caps the
display at 2 bars and ≥1,000 ms at 1 bar, even when the loss and jitter
readings are otherwise good. Both caps are stated in full under
"Composite → bars" below.

### Composite → bars

Thresholds `[0.00, 0.15, 0.32, 0.50, 0.68, 0.85]` → 0…5 bars.

Four rules sit on top:

- **Hysteresis (±0.03).** A level change requires clearing the boundary by this
  margin. Without it the indicator flickers whenever the connection sits on an
  edge, which reads as a broken app.
- **Severe-loss cap.** Loss ≥ ⅓ caps the display at 1 bar however fast the
  surviving packets were. Total loss forces 0.
- **Transfer-failure cap (2 bars).** Probes answering while a 120 KB download
  will not complete is precisely the "full bars, no data" failure this app
  exists to expose. Latency and jitter both look excellent in that state, so
  the composite alone would report a healthy connection. The cap applies
  immediately and is *not* softened by hysteresis.
- **Latency caps (2 bars, then 1 bar).** Median RTT ≥600 ms caps the display at
  2 bars, and ≥1,000 ms at 1 bar — including sparse cycles with no current
  transfer sample. 600 ms is where the latency component already scores zero;
  without these caps the remaining components can still carry a 700 ms link to
  3 bars, "browsing and standard video work", which it is not. A response that
  takes a full second to make a round trip is not a workable browsing link at
  all.

  These two caps carry **their own hysteresis**, because unlike loss — which
  four probes quantise to 0/25/50/75/100% — latency is continuous, and a link
  sitting near 600 ms is ordinary. A cap engages at its threshold and releases
  only below **550 ms** and **900 ms** respectively. Without that band a median
  oscillating 595/605 ms alternates the indicator every cycle while the
  composite sits perfectly still; the composite margin cannot damp it, because
  the discontinuity never reaches the composite. A cap is treated as engaged
  when the reading already on screen is one that cap could have produced, so
  the model stays a pure function of its inputs and holds no hidden state.

### Verdicts

| Bars | Verdict | Meaning shown to the user |
|---|---|---|
| 0 | No usable connection | Requests are timing out. Data is not getting through. |
| 1 | Barely usable | Messages may send eventually. Pages and video will struggle. |
| 2 | Slow | Fine for messaging and email. Video calls will suffer. |
| 3 | Workable | Browsing and standard video work. Large transfers are slow. |
| 4 | Good | Comfortable for video calls, HD streaming and downloads. |
| 5 | Excellent | Fast and stable. Everything should feel instant. |

## 6. Sampling cadence and the data budget

| Situation | Latency probes | Transfer sample |
|---|---|---|
| App on screen | every 5 s (Pro: 2–60 s) | at most every 90 s |
| Android background (service) | every 5 min (Pro: 1–60 min) | at most every 10 min |
| App opened, manual refresh, network change | immediately | forced |
| iOS, app closed | nothing runs | nothing runs |

Cost: a latency probe is ~700 B of headers, so a cycle of four costs ~2.8 KB.
A transfer sample costs ~120 KB. The default 25 MB/day budget (adjustable
5–250 MB on every tier) comfortably covers all-day background monitoring plus
normal foreground use.

The budget is a hard stop, not a guideline, and the counter is on the home
screen rather than buried in settings. Each transfer has both an 8-second
wall-clock deadline and a response-byte cap equal to its requested size, so a
misbehaving endpoint cannot stream indefinitely. When it is spent, **latency
probes keep running** — the user still gets a reading — and only the 120 KB
transfer sample pauses until local midnight. A failed budget read fails
*closed* (reports the budget as spent) so a broken platform channel can never
spend unlimited data.

## 7. Data model

All local. No backend, no accounts, no sync.

**`SignalSample`** — one completed cycle: timestamp, network kind, bars,
composite, latency, jitter, throughput (+ stale flag), loss ratio, probes sent,
bytes used, network detail.

**`AppSettings`** — indicator on/off, overlay on/off, foreground and background
intervals, daily budget MB, bar theme, measure-on-cellular, theme mode,
onboarding seen.

**`DataBudget`** — local calendar day key, bytes used, limit.

### Storage

| Store | Holds | Why there |
|---|---|---|
| Hive box `settings` | settings JSON, budget mirror, Pro flag | House pattern: one JSON map per key, no adapters, no codegen, no migrations |
| Hive box `history` | samples, auto-increment keys, values carry their own timestamp | Keying by `millisecondsSinceEpoch` is impossible — **Hive rejects integer keys above 0xFFFFFFFF**, which an epoch in milliseconds passed in 1970. Auto keys are monotonic, so insertion order is chronological order. |
| Android SharedPreferences (`BudgetStore.kt`) | the day's probe-byte counter | Two Dart isolates need it — the UI engine and the background engine — and **Hive is not isolate-safe**. Both reach it through one platform channel. |
| Android SharedPreferences (service/overlay) | which indicators the user enabled, bubble position, service config | Must survive the app process dying and be readable by the boot receiver |

History is pruned to 25 hours (one hour of slack so a "last 24 h" view is never
short) and deduplicated: a sample is stored when the score changes, the network
changes, or 30 s have passed. Without that, a 5 s foreground cadence would
write 17,000 rows an hour for an unchanging connection.

## 8. Architecture

```
lib/
  main.dart                  main() + honestSignalBackgroundMain() entry points
  app/                       app shell, GoRouter, Riverpod providers
  core/
    constants/ theme/ utils/ storage/ demo/
  features/
    measurement/  domain (scoring, models, config) | data (engine, probe
                  client, controller, repositories, background host) |
                  presentation (screens, widgets)
    settings/     domain | data | presentation
    purchases/    domain | data (IapGateway, PurchaseController) | presentation
    indicator/    data (platform channel, controller) | presentation
    onboarding/   presentation
  shared/widgets/            SignalBars, MetricTile, ProLock
android/app/src/main/kotlin/com/froggyeye/honestsignal/
  HonestSignalService.kt       foreground service + background Flutter engine
  IndicatorPlugin.kt         UI-engine method channel
  BudgetChannel.kt           cross-isolate byte counter
  IndicatorIcons.kt          theme+level → drawable
  OverlayService.kt          floating bubble
  SignalBubbleView.kt        bubble canvas
  BootReceiver.kt            restore after restart
```

**State:** Riverpod. `MeasurementController`, `PurchaseController` and
`IndicatorController` are plain `ChangeNotifier`s exposed through providers, so
each is unit-testable with fakes and none of them import Flutter widgets.

**Seams (everything that touches the outside world is injectable):**
`ProbeClient`, `ConnectivitySource`, `BudgetStore`, `IapGateway`. Tests drive
all four with scripted fakes and never open a socket or contact a store.

**Deviation from the house default:** no Freezed / build_runner. The app has
three small models; hand-written `copyWith` and JSON are less machinery to read
than a codegen pipeline, and keep `flutter analyze` deterministic. No Dio
either — `package:http`'s `Client` is a cleaner seam for timing individual
requests, and the app calls no API.

**Effective settings:** stored settings are never rewritten when Pro lapses.
`AppSettings.clampedForTier` applies the free-tier limits on read, so a user who
buys, customises, and is later refunded finds their choices intact if they buy
again.

### How the Android indicator stays live

`HonestSignalService` hosts a **background Flutter engine** running the app's own
Dart measurement engine (`honestSignalBackgroundMain`, kept from tree-shaking by
`@pragma('vm:entry-point')` — verified present in the release AOT snapshot for
all three ABIs). Kotlin owns the *timing*; Dart owns the *answer*.

The alternative — reimplementing the scoring model in Kotlin — would put the
product's core IP in two languages that are guaranteed to drift apart. This way
the formula exists exactly once.

While the app is on screen the service's loop **pauses** and shows the reading
the UI isolate publishes, so the two never probe in parallel and the user's data
is never spent twice for the same answer. UI activity is a renewable 60-second
lease carried in every published reading; a missed lifecycle message therefore
recovers automatically rather than freezing the background service forever.

The status-bar icon is one of 36 pre-rendered vector drawables (3 themes × 6
levels × 2 contrast variants), generated by
`android/tools/generate_indicator_icons.py`. A runtime-generated bitmap would be
more flexible but is not guaranteed to survive every Android version's and OEM
skin's monochrome tinting path for small icons; thirty-six tiny XML files buy
that certainty.

### What the indicator can and cannot look like (1.0.1)

Android hands a status-bar small icon to the system as an **alpha mask**: the
system picks the colour — white on a dark status bar, near-black on a light one
— and the app supplies shape and opacity only. Three consequences follow, and
they are the answers to the four things users asked for after 1.0.0.

**Contrast against any wallpaper.** The only lever an alpha mask has is mass and
relative opacity, so the default icon from 1.0.1 draws the mark on a filled
plate at 44% alpha with the lit elements at 100% and a transparent moat cut
between them. Every part of the mark is then adjacent to a different opacity,
which holds up over a busy wallpaper in a way five thin strokes did not. Unlit
slots keep their interior at plate alpha rather than being cut through: an
open hole shows the wallpaper, and over a pale patch an *empty* bar lit up as
brightly as a full one. `AppSettings.highContrastIndicator` switches the plate
off for users who prefer the original mark; it is free, not a Pro theme.

The one case no alpha mask survives is a wallpaper that happens to match the
tint the system chose. The plate improves the odds — a larger mark is more
likely to overlap a contrasting patch — but the app cannot fix it.

**Colour.** A green/amber/red *status-bar icon* is not possible on modern
Android at all; the tint is not ours to set. The score colour
(`SignalColours.forBars`, mirroring `AppColors.dark.forBars` in Dart) therefore
appears where colour is permitted: the floating Pro bubble draws its bars in it,
the notification carries it as `setColor`, and below Android 16 the shade entry
is `setColorized(true)`, so the card itself is red, amber or green and changes
with the score.

**Telling it apart from the system's own bars, and not being dropped from a
crowded status bar.** Neither has an API on Android 13–15: icon order and which
icons get culled are the system's ranking, and the only lever an app has is
notification importance — which is fixed at channel creation, so raising it
would cost every existing install its channel settings and buy a heads-up card
nobody asked for. It was not taken. From Android 16 the ongoing indicator asks
to be a **promoted ongoing notification** (`setRequestPromotedOngoing`), which
gets its own status-bar chip outside the icon row and can carry a few
characters of text; the app sets `setShortCriticalText("HS")`. Lettering *inside*
the 24dp mask was prototyped and rejected — at status-bar size "HS" is a smudge
and it halves the height available to the bars.

## 9. Permissions — and why each one is needed

Store reviewers and the compliance auditor should read this section as the
authoritative justification.

### Android

| Permission | Why Honest Signal needs it | User-visible? |
|---|---|---|
| `INTERNET` | The measurement engine's entire function is to make real network requests and time them. Without it the app has nothing to measure. | No (normal) |
| `ACCESS_NETWORK_STATE` | Reports whether the device is on Wi-Fi or mobile, shown next to the score, and signals the instant the transport changes so the stale reading can be replaced immediately. | No (normal) |
| `POST_NOTIFICATIONS` | **The status-bar indicator *is* a notification** — its small icon is the live score. This is the app's headline feature, not an engagement channel. The app posts exactly one ongoing, silent (IMPORTANCE_DEFAULT, with sound, vibration and lights removed on both the channel and the builder — DEFAULT is the lowest importance that still gets a status-bar icon from Android 11) non-dismissible-while-running notification and never sends any other kind. Declining leaves the whole in-app experience working. | Yes (runtime, Android 13+) |
| `POST_PROMOTED_NOTIFICATIONS` | Android 16+, non-runtime. Lets the one ongoing indicator notification be promoted to a status-bar chip, which is how Android 16 shows a live ongoing status outside the icon row. Users reported the indicator being dropped when the status bar filled with other apps' icons; the chip is the only sanctioned way to ask not to be. The chip also carries the label "HS", which is how a user tells our mark from the system's own radio bars. Nothing else about the notification changes, and the user can switch promoted notifications off per app in system settings — the service re-checks that on every update and falls back to a colourised shade entry. | Yes (system settings, Android 16+) |
| `FOREGROUND_SERVICE` | Measurement must continue while the app is not on screen, or a status-bar indicator would be permanently stale. | No (normal) |
| `FOREGROUND_SERVICE_SPECIAL_USE` | See below. | No (normal) |
| `SYSTEM_ALERT_WINDOW` | The optional floating bubble. See below. | Yes (system settings) |
| `RECEIVE_BOOT_COMPLETED` | Restores the status-bar indicator the user had switched on after a restart. An indicator that silently vanishes on every reboot stops being trusted. Only ever restarts what the user already enabled. | No (normal) |

**Transitively merged, not declared by us:** `com.android.vending.BILLING`
(required by `in_app_purchase`) and
`com.froggyeye.honestsignal.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` (an
internal signature-level permission androidx adds). Verified by parsing the
merged manifest — **no location, camera, storage, phone-state or contacts
permission is merged from any dependency.** Note for the data-safety form:
Google's own billing library (`com.android.billingclient:billing:8.0.0`) pulls
`play-services-location` and `com.google.android.datatransport` as transitive
dependencies. Neither adds a permission, neither is called by this app, and
neither can be excluded without breaking Play Billing.

#### Why `specialUse` and not `dataSync`

`dataSync` is the obvious-looking foreground service type, and it is the wrong
one: **from Android 15 a `dataSync` foreground service is capped at 6 hours per
day.** A persistent connection indicator that dies part-way through every day —
silently, at a different time depending on usage — is worse than no indicator,
because the user cannot tell "the indicator stopped" from "the connection is
fine". `specialUse` has no such cap.

The declared subtype string in the manifest is:

> Continuously measures real network throughput and latency so the live
> connection-quality indicator in the status bar stays accurate while the app is
> not open. The measurement must run on the user's own schedule and cannot be
> deferred to a background job without the indicator going stale.

This needs a matching declaration in Play Console. The supporting argument: the
service's only output is the notification the user explicitly turned on; it does
no work when the app is in the foreground; its interval is user-controlled and
clamped to a 30 s floor; and its data cost is hard-capped by a user-visible
daily budget.

#### Why `SYSTEM_ALERT_WINDOW`, and how it is constrained

The floating bubble draws the live score over other apps so the user can watch
the real signal *while using the app that is struggling* — which is the only
moment the information is actually useful. Every constraint that matters:

- **Pro-only and off by default.** It cannot appear on a fresh install.
- **Requires the status-bar indicator.** Its foreground service supplies the
  live score and keeps the bubble alive; the app stops the overlay if that
  indicator is disabled rather than showing a stale bubble.
- **The permission is never requested until the user turns the feature on**, on
  a dedicated screen (`/settings/overlay`) that explains what will be drawn
  before offering the system settings link.
- Android provides no in-app grant for it; the app deep-links to the system
  screen and re-checks on resume. The grant is revocable there at any time and
  the service re-checks it on every start.
- **~44 dp**, about the size of a status-bar icon, semi-transparent.
- `FLAG_NOT_FOCUSABLE` — it never takes input from the app underneath except on
  the bubble itself. Keyboards and gestures behave normally.
- Drag to move, tap to open Honest Signal, **long-press to switch it off without
  opening anything**.
- It displays only the score. It shows no ads, no promotions and no content
  from anywhere else, and it never overlays a system permission dialog.

### iOS

**No permission-gated API is used at all.** No purpose strings are required and
none are declared. Confirmed by symbol-scanning the built binary: zero
references to `AVCaptureDevice`, `PHPhotoLibrary`, `UIImagePickerController`,
`CLLocationManager`, `CNContactStore`, `ATTrackingManager` or
`CTTelephonyNetworkInfo` (house-facts #17 — Apple scans linked symbols, not call
sites, so this was checked against the binary rather than the source).

`ITSAppUsesNonExemptEncryption = false` is declared: the app uses only standard
HTTPS through the system stack.

**iOS honesty requirement.** iOS cannot measure while the app is closed. The app
never pretends otherwise: the home screen always states the reading's age, and
once a reading is more than two minutes old it says outright that iOS stops apps
measuring in the background and offers pull-to-refresh. No background
measurement is attempted beyond what BGTaskScheduler would realistically allow,
and that is deferred to a later release alongside the widget.

## 10. Privacy posture

**Data collected: none.** No analytics, no crash reporting, no advertising, no
accounts, no backend. Both stores' labels should read "No data collected".

The probes are anonymous HTTPS requests carrying no identifier, cookie or
account to public connectivity-check endpoints operated by Google and
Cloudflare — the same endpoints the OS already polls for captive-portal
detection. Those operators necessarily see the originating IP address, as they
would for any web request; `PRIVACY_POLICY.md` says so explicitly rather than
claiming the traffic is invisible. Nothing else is sent, and nothing comes back
except timing.

Privacy policy: `PRIVACY_POLICY.md` at the repo root, linked from Settings,
served at the house raw-GitHub URL (`AppConstants.privacyPolicyUrl`). **The URL
must be confirmed to return 200 before submission** — the repo has to exist
under `mksoft-ltd` first.

## 11. Monetisation

One-time non-consumable unlock, **£2.99**, product ID
`com.froggyeye.honestsignal.pro`, native `in_app_purchase` plugin only — no
RevenueCat or any other wrapper.

- Price shown on the paywall comes from the store, never hardcoded, so it
  matches the user's actual storefront.
- Restore purchases from the paywall and from Settings; a silent restore also
  runs on every launch so a reinstall lands in the tier it paid for.
- `buyNonConsumable` only reports that the sheet *opened*; every terminal
  outcome — bought, cancelled, declined — arrives on the purchase stream, and
  the busy flag is cleared there. A cancelled purchase leaves no spinner.
- Purchases pending completion are acknowledged, or Android auto-refunds them
  after three days.
- The paywall names each Pro feature and what it does before asking for money.

## 12. Gate results (stage 1 exit)

| Gate | Result |
|---|---|
| `flutter analyze` | **No issues found** |
| `flutter test` | **81/81 passing** |
| `flutter build apk --debug` | ✅ |
| `flutter build apk --release` (R8 minify + resource shrink) | ✅ 52.9 MB universal APK |
| `flutter build ios --simulator --debug` | ✅ (no codesign) |
| Release AOT retains `honestSignalBackgroundMain` | ✅ verified in all three ABIs |
| Merged Android manifest permission audit | ✅ no unexpected permissions |
| iOS binary privacy-symbol scan | ✅ zero privacy-class API symbols |

Two real defects were found by the tests and fixed rather than worked around:
Hive's 32-bit integer key limit (history would have crashed on the first sample
on-device) and a re-entrancy hole where a timer tick landing mid-cycle started a
second set of probes and double-charged the data budget.

**Re-run 2026-08-09, after the True Signal → Honest Signal rename.** The table
above is a stage-1 snapshot and its names have been updated to the current ones;
the row that matters for the rename was re-verified rather than merely retyped —
the release AOT retains `honestSignalBackgroundMain` in all three ABIs and the
old `trueSignalBackgroundMain` appears in none of them. The suite has also grown
since: `flutter test` is now **271/271**, and the merged release manifest carries
`package="com.froggyeye.honestsignal"` with zero occurrences of the old token
anywhere in the APK.

## 13. Notes for downstream stages

- **ui-designer:** the bar mark is drawn three times — `signal_bars.dart`
  (Flutter), `IndicatorIcons` (18 vector drawables, regenerable via the
  generator described in §8), and `SignalBubbleView.kt` (Canvas). Any change to
  the mark has to land in all three. `AppColors.forBars` is duplicated in
  `SignalBubbleView.colourFor`.
- **mobile-qa-architect:** the whole engine is fake-driven; see
  `test/fakes/fake_probe_client.dart`. Never use `pumpAndSettle` on the home
  screen — the measurement timer and the freshness ticker are both periodic and
  it will hang rather than fail. Untested on real hardware: the background
  Flutter engine actually booting inside the service, the notification small
  icon rendering across OEM skins, and the overlay's window behaviour. Those
  need a device.
- **store-publisher:** screenshot harness is
  `integration_test/screenshots_test.dart` with the driver at
  `test_driver/integration_test.dart`; run it with
  `--dart-define=SCREENSHOT_MODE=true` (add `SCREENSHOT_TIER=free` for the
  paywall and locked states). Demo mode is ANDed with `!kReleaseMode`, so a
  release binary can never be switched into fake data.
- **release-manager:** Play Console needs the `specialUse` foreground-service
  declaration (text in §9) and a `SYSTEM_ALERT_WINDOW` justification. The app is
  iPhone-only; `TARGETED_DEVICE_FAMILY = 1`, portrait only, iOS 15 minimum.
- **Still to do before release:** generate the per-app upload keystore and
  `android/key.properties` (the Gradle config is already wired and falls back to
  debug signing until they exist), push the repo to `mksoft-ltd`, and confirm
  the privacy-policy URL returns 200.
