# Honest Signal (formerly True Signal) — ship-app pipeline tracker

App: **Honest Signal** — a signal indicator that measures *real* connectivity (transfer sampling), not radio bars.
Decisions (founder, 2026-08-07): **free + £2.99 Pro IAP** (native `in_app_purchase`); **iPhone-only** on iOS; Android indicator = **status-bar notification icon by default + optional floating overlay** (SYSTEM_ALERT_WINDOW); iOS = in-app view (+ widget/Live Activity if feasible).

**RENAMED 2026-08-09** (founder decision): "True Signal" → **"Honest Signal"** after ASO found an App Store rival `TrueSignal` (one word, id6760624783, David Schwind) shipping the same positioning. New IDs: package/bundle `com.froggyeye.honestsignal`, IAP `com.froggyeye.honestsignal.pro`, website slug `honestsignal` → https://honestsignal.froggyeye.com, store title "Honest Signal: Network Quality" (30 chars).

## Store records (current, post-rename)
- iOS bundle ID `com.froggyeye.honestsignal` registered via ASC API: resource `P8KPF57SH4`, team `696939LPWV` — done 2026-08-09
- ASC app record Apple ID `6799269422`: bundle ID switched to `com.froggyeye.honestsignal` and name changed to "Honest Signal" via API (PATCH /v1/apps + appInfoLocalizations) — done 2026-08-09. SKU remains `truesignal` (immutable, user-invisible).
- Play app record created for **Honest Signal** / `com.froggyeye.honestsignal` (en-GB, App, Free, both declarations): app ID `4973053518256217291` — done 2026-08-09
- Legacy: old bundle ID `com.froggyeye.truesignal` (`2965V5KTG2`) unused; old Play draft "True Signal" (`4972146908238602643`, package `com.froggyeye.truesignal`) abandoned — founder may delete it in Play Console (draft, nothing uploaded).

## Stages
| # | Stage | Agent | Status | Date |
|---|-------|-------|--------|------|
| 1 | build | flutter-architect | done — stage-4 fix round applied 2026-08-09 | 2026-08-07 |
| 2 | design | ui-designer | done | 2026-08-08 |
| 3 | test | mobile-qa-architect | done | 2026-08-08 |
| 4a | code-review | mobile-code-reviewer | done — **PASS** re-verified (2 Critical + 3 Major + N1/N2 fixed; 13 Minor open) | 2026-08-09 |
| 4b | security | mobile-security-auditor | done — **PASS** (0 Critical, 0 High, 3 Medium, 3 Low); SEC-1/2/3/4 fixed and re-verified 2026-08-09 | 2026-08-09 |
| 5 | metadata | growth-monetization → release-manager | in-progress — ASO done (`docs/ASO.md`), release-manager next | 2026-08-09 |
| 6 | compliance | app-store-review-auditor | pending | |
| 7 | publish | store-publisher | pending | |
| 8 | website | general-purpose (froggyeye-website skill) | pending | |

## Stage 1 (build) — completed 2026-08-07

MVP built. Spec: `docs/PRODUCT_SPEC.md` (scoring model, screen map, data model,
and every permission with its justification — the `specialUse` foreground-service
and `SYSTEM_ALERT_WINDOW` rationales are written for store review).

Gates: `flutter analyze` clean · `flutter test` 81/81 · debug + release APK
(R8 minify) · iOS simulator build · release AOT retains the background
entrypoint in all 3 ABIs · merged manifest has no unexpected permissions · iOS
binary links zero privacy-class API symbols.

Carried forward for later stages:
- Generate `android/upload-keystore.jks` + `android/key.properties` (Gradle
  already wired; falls back to debug signing until they exist).
- Push repo to `mksoft-ltd` and confirm the privacy-policy raw URL returns 200.
- Play Console needs the `specialUse` FGS declaration and a SYSTEM_ALERT_WINDOW
  justification — text is in PRODUCT_SPEC §9.
- Not verifiable without hardware: background Flutter engine booting inside the
  service, notification small-icon rendering on OEM skins, overlay window
  behaviour.

## Stage 2 (design) — completed 2026-08-08

Artifacts: `store_assets/BRAND.md` (palette, typography, shape scale, tone, icon
rationale), `store_assets/screenshot_specs.md` (shot list + headline copy),
`store_assets/README.md` (regeneration recipes and the generator quirks to
revert), plus scripted sources under `store_assets/{icon,feature_graphic,screenshots}/`.

**Icon** — "bars, verified": five ascending signal bars with a white tick in the
void they leave. Wired into both platforms via `flutter_launcher_icons` (iOS
AppIcon set, opaque; all Android mipmap densities, adaptive foreground/background,
and an Android 13 monochrome layer). The pbxproj line the package corrupts was
reverted and the fix documented.

**Palette fix (the one substantive code change).** The stage-1 score ramp was a
single set tuned for dark and it failed WCAG on light surfaces — including on the
bar mark that leads the store screenshots:

| Token | Old | on #F5FBF5 | New | on #F5FBF5 |
|---|---|---|---|---|
| dead | `#E0483C` | 3.87 | `#C0271B` | 5.64 |
| poor | `#E8863B` | 2.53 | `#A85A0A` | 4.84 |
| fair | `#D8B22E` | 1.94 | `#8A6B00` | 4.78 |
| good | `#4FA83D` | 2.86 | `#357A27` | 5.04 |
| great | `#1FA97A` | 2.85 | `#0E7A57` | 5.08 |

The ramp is now per-brightness (`AppColors.of(context)`); the **dark set is
unchanged**, so the Kotlin copy in `SignalBubbleView.colourFor` still matches and
the 18 status-bar drawables (monochrome by design) were untouched. Also: hairline
borders on cards/tiles (light-scheme tonal elevation measures 1.03:1 and is
invisible), a shared radius/spacing scale, tabular figures on the live budget
counter, and a themed Android launch window so dark-themed phones stop flashing
white on cold start.

Gates after the design changes: `flutter analyze` clean · `flutter test` green
(157 tests — stage 3 grew the suite concurrently).

Carried forward:
- Screenshot capture runs with the device in **light** appearance
  (`screenshot_specs.md` §2 — changed from dark on the evidence of framing real
  captures: a dark screenshot disappears into the dark plate), then
  `store_assets/screenshots/render.sh`.
- The marketing set must come from a **`pro`-tier** capture. A free run renders
  `ProLock` on the history route, and framing that under "Prove the drop-outs
  are real" ships a paywall where the artwork advertises a graph. `render.sh`
  now hard-fails on `raw/tier.txt` != `pro`.
- The paywall capture (`05_pro`) is excluded from both marketing sets — it shows
  a GBP price — but is still needed as ASC's IAP review screenshot.
- The Play-only "status bar" shot must never appear in the App Store set.

## Stage 4b (security) — completed 2026-08-08

Full audit: `docs/audits/security.md`. **Verdict: PASS** — 0 Critical, 0 High,
3 Medium, 3 Low. Nothing blocks the gate; the app has no accounts, no backend,
no credentials, no PII and no analytics, all confirmed against the built release
APK rather than the spec.

Recommended for flutter-architect **before stage 7**, none gate-blocking:

- **SEC-1 (Medium)** — `HttpProbeClient.transfer` reads an unbounded response
  body. `Stream.timeout` is an inter-chunk timeout, so a responder that keeps
  sending never trips it. Measured against a local server: **3,072,000 bytes
  accepted against a 120,000-byte request, over 13.6 s against an 8 s timeout**,
  returned as a successful sample. The daily budget is read before a cycle and
  charged after it, so it bounds how many cycles run, never how much one cycle
  spends — PRODUCT_SPEC §6's "hard stop" does not hold inside a cycle. `probe()`
  is correctly bounded; the two methods differ only in where `.timeout` is
  applied. Fix is a byte cap plus a wall-clock deadline.
- **SEC-2 (Medium)** — `android:allowBackup` is unset (defaults **true**) with
  no `dataExtractionRules`, verified in the release merged manifest. The Pro
  entitlement flag, 25 h of connectivity history and all three SharedPreferences
  files go to Google Drive backup and to device-to-device transfer. Also sits
  awkwardly against `PRIVACY_POLICY.md:26-27`.
- **SEC-3 (Medium)** — Pro entitlement is an unverified local bool that never
  downgrades. Accepted house design, logged as proportionate hardening. One part
  is worth taking regardless: the comment at `settings_repository.dart:37-39`
  claims the store stream "overwrites this on every launch", which is false —
  `_unlock()` only ever writes `true`.
- **SEC-4 (Low)** — privacy policy says history is kept 24 h; the code keeps 25.
- **SEC-6 (Low)** — no explicit network security config. Pinning is *not*
  recommended for this app; an explicit system-CA + no-cleartext config is.

For stage 6 (compliance), not a defect: **SEC-5** records that Play Billing's
Firelog telemetry client is live in the release dex — endpoint reconstructed
from its character-interleaved form as
`https://firebaselogging-pa.googleapis.com/v1/firelog/legacy/batchlog`. A plain
hostname grep finds nothing and misleadingly suggests R8 stripped it. "No data
collected" still holds on both stores, but answer the Data Safety form knowing
those components ship. `PurchaseController.init()` also contacts the store at
every cold start, so no store text may imply contact happens only at purchase.

## Stage 4a (code review) — FAILED 2026-08-08

Full report: `docs/audits/code-review.md`. **Verdict: FAIL** — 2 Critical,
3 Major, 12 Minor. Quality score 6.5/10, performance risk Medium. Baseline at
review time: `flutter analyze` clean, `flutter test` 255/255.

Every finding was verified by running code, not by reading; the probes were
temporary and removed, and the commands and outputs are quoted in the report.

**Blocking:**
- **C1** — `measurementControllerProvider` (`providers.dart:102`) `ref.watch`es
  `effectiveSettingsProvider`, so *any* settings change disposes and rebuilds
  `MeasurementController`. `start()` is only ever called from `HomeScreen`'s
  `initState`, which does not run again, so the replacement never starts: no
  timer, no connectivity subscription, and `setUiActive(false)` is never sent, so
  the Android service stays suppressed too. Both isolates stop until the process
  restarts, while the notification keeps showing a stale reading as live.
  Reproduced end to end: 12 probes in the 12 s before a theme change, **0** in
  the 36 s after. Also throws `A MeasurementController was used after being
  disposed` in debug/profile from `applySettings`.
- **C2** — `SignalScoring.bars` (`scoring.dart:157`) tests an upward move against
  the destination threshold instead of the boundary being crossed, so any jump of
  more than one level is rejected outright and held indefinitely. From 0 bars, a
  composite of **0.86 — a five-bar connection — reports "No usable connection"**.
  Worst-case error 5 bars. QA had this as medium (TEST_PLAN §5.1) on the 0.51
  case only. Fix verified by sweep: 0 changes to single-step flicker suppression,
  303 multi-step cases corrected.
- **M1** — the service's `uiActive` flag is an unacknowledged one-shot latch with
  no expiry; three separate paths lose it and freeze the indicator permanently.
- **M2** — the Pro floating bubble is only ever fed from `HonestSignalService`, so
  with the status-bar indicator off it shows 0 bars forever. The two settings are
  presented as independent.
- **M3** — with no throughput sample the composite cannot fall below 0.40 on a
  lossless link: a 5000 ms-latency connection reports 3 bars, "Workable".
  Reachable on background cycles between transfer samples and on every cycle
  after the daily budget is spent.

Notes for the fix round (flutter-architect):
- `test/scoring_boundaries_test.dart` pins C2's current behaviour deliberately;
  those assertions are the specification of the bug and must be rewritten.
- No test currently changes a setting through the real provider graph while a
  controller is running, which is why C1 survived 255 tests. Add one.
- C2's re-verification must use a sweep written from PRODUCT_SPEC §5, not a
  helper shared with the model — a shared helper lets code and tests agree while
  both are wrong.
- Any change to the scoring model must land in three places: the model,
  PRODUCT_SPEC §5, and the in-app "How the score works" screen.

## Stage 4 fix round — completed 2026-08-09 (flutter-architect)

Applied against `docs/audits/code-review.md` (FAIL) and `docs/audits/security.md`
(PASS with mediums). Per-finding detail, including how each was checked, is
appended to those two files above their verdict lines. **The 4a/4b rows above are
deliberately untouched** — the auditors flip them after re-verifying.

Fixed: C1, C2, M1, M2, M3, SEC-1, SEC-2, SEC-3 (comment only), SEC-4, SEC-6, plus
the two minors (probesSent, throughput formatter).

Three things the re-verification should know:

- **C1's regression test was itself broken and weak.** It failed with
  `Binding has not yet been initialized` — it omitted the `iapGatewayProvider`
  override, so `effectiveSettingsProvider → isProProvider →
  purchaseControllerProvider` built the real Play Billing gateway. It also proved
  liveness by calling `measureNow()`, which does not check `_started` and so
  passes against exactly the stranded controller C1 produced. It now waits out
  the real foreground timer and emits a transport change instead, and was
  confirmed to fail when `ref.read` is reverted to `ref.watch`.
- **M3 was fixed with two caps, not one.** ≥600 ms caps at 2 bars, ≥1,000 ms at
  1 bar. The 700 ms case the reviewer called out now reads "Slow" rather than
  "Workable". PRODUCT_SPEC §5's blend paragraph described only the 1,000 ms cap
  and contradicted its own "Composite → bars" section; that was corrected, so
  the model, §5 and the in-app screen now agree.
- **C2 was re-verified against a hand transcription of §5**, not a shared helper:
  112,560 cases over previousBars × latency × loss × cap × composite, 0
  mismatches.

Gates: `flutter analyze` clean · `flutter test` **268/268, 0 skipped** ·
`flutter build apk --release` ✅ 52.9 MB · SEC-2/SEC-6 confirmed in the release
**merged** manifest, not the source.

Still open (all Minor, from code-review §8, none gate-blocking): slider debounce,
history screen re-parse per notification, notification freshness, overlay
position clamping, `BootReceiver` notification re-check, connectivity change
dropped during an in-flight cycle, dead `loadBudget`/`saveBudget`, `verdict(-1)`,
`BackgroundMeasurementHost`'s direct `DateTime.now()`.

## Stage 4a (code review) — re-verified PASS 2026-08-09

Fix round by flutter-architect re-verified by mobile-code-reviewer. **Verdict:
PASS.** All five blocking findings (C1, C2, M1, M2, M3) fixed and confirmed by
executing code against the tree, not by reading the fix notes. The C2/M3 checker
was written from PRODUCT_SPEC §5 prose rather than from the model, so the two
could not be wrong together: ~196k cases swept, 0 mismatches.

- **C1** — 28 new probes in the 36 s after three successive settings changes
  (was 0), controller instance survives, and `setUiActive(false)` reaches the
  service on backgrounding. Their regression test was checked rather than
  trusted: reinstating `ref.watch` makes it fail, restoring `ref.read` makes it
  pass; the file was restored and the gates re-run.
- **C2** — 0.86 from 0 bars now reads 5, "Excellent"; the sticky case is
  `[3,3,3,3,3,3]`; flicker suppression bit-for-bit unchanged.
- **M3** — 700 ms → 2 bars "Slow", 1500/5000 ms → 1 bar; a good link is
  untouched. Model, PRODUCT_SPEC §5 and the in-app screen all moved together —
  verified in all three.
- **M1/M2** — lease and watchdog correct on source review (the handshake still
  needs a device, per TEST_PLAN §3 M1/M3); the overlay now requires the
  status-bar indicator and both screens say so.

Gates confirmed by the reviewer: `flutter analyze` clean, `flutter test`
**268/268**.

**15 Minor items remain open and are passed with recommendations** — the twelve
from the report's §8 plus three from the fix round. The one worth taking first
is **N1**: the new latency caps are step functions applied *after* hysteresis,
so a median RTT hovering near 600 ms or 1,000 ms alternates the reading every
cycle (`[3,2,3,2,…]`) with the composite perfectly steady — the flicker
hysteresis exists to prevent, now on the latency axis. Fix is a hysteresis band
on the caps, or applying them before the bar mapping. Also N2 (the 60 s UI lease
is too tight for the 60 s max Pro foreground interval) and N3 (cap RTT includes
connection setup on a cold pool).

### Stage 4b re-verification — 2026-08-09

flutter-architect fixed SEC-1, SEC-2, SEC-3 (comment) and SEC-4;
mobile-security-auditor re-verified all four independently. **Verdict unchanged:
PASS.** Nothing reopened, no new finding. Detail in the "Re-verification"
section of `docs/audits/security.md`.

- **SEC-1** confirmed fixed by executing the real client, not by reading it:
  a 120,000-byte request against a continuous stream now stops at 131,072 B
  (was 3,072,000 B), a slow drip stops at 2,005 ms against a 2 s timeout (was
  13.6 s past an 8 s timeout), and a well-behaved exactly-120,000-byte response
  still succeeds — the cap does not break the happy path.
- **SEC-2** confirmed in the **shipped APK**, not just the manifest: the built
  manifest post-dates the source edits, and `aapt2 dump xmltree` on the packaged
  `res/4j.xml` shows all four excludes under both `<cloud-backup>` and
  `<device-transfer>`, including `domain="root"` — the one that covers the Hive
  boxes in `app_flutter/`.
- **SEC-3 / SEC-4** confirmed by source review; SEC-4 is now single-sourced from
  `HistoryRepository.defaultRetention` with a test tying the published figure to
  the enforced one.

One **non-blocking test-robustness note** for whoever next touches the suite:
the committed assertion `bytes <= requested + 64 KB` in `release_invariants_test.dart`
passes because that test's server writes 16 KB and loopback coalescing lands at
128 KB — 64 KB is not a bound the code guarantees. Measured overshoot rises with
the peer's write size (200 KB write → 204,800 B accepted; 1 MB write → 1,048,576 B),
so the assertion can flake on different socket-buffer tuning while also missing a
real regression. Asserting `lessThan(2 * 1024 * 1024)` against the 64 MB on offer
is robust in both directions. The fix itself is sound; only the constant is worth
changing.

Suite at re-verification: `flutter test` **269/269**, `test/` clean of both
auditors' temporary probe files.

### N1 / N2 pass — 2026-08-09

From the 4a re-verification (PASS). **N1** (regression from the M3 fix): the
latency caps were step functions applied after hysteresis, so a median
oscillating 595/605 ms flapped the indicator `[3,2,3,2,…]` with the composite
steady. Fixed with release bands (engage 600/1000 ms, release 550/900 ms), cap
engagement inferred from `previousBars` so the model stays pure. Both sequences
now hold flat. The composite-clamp alternative was traced and does **not** work —
the discontinuity never reaches the composite; recorded in the audit file so it
is not re-suggested. **N2**: `publishSample` now carries the foreground interval
and the service leases `max(60 s, 3 × interval)`, closing the duplicate-probe gap
for a Pro user at a 60 s interval.

PRODUCT_SPEC §5 and the in-app "How the score works" screen both moved with N1,
since the release band changes a user-visible rule.

Gates: analyze clean · **271/271 tests, 0 skipped** · release APK ✅ 52.9 MB.

N3 (caps key off an RTT including connection setup) and the twelve §8 Minors are
deliberately left for a point release.

### Stage 4a — N1/N2 pass re-verified 2026-08-09

**Verdict stays PASS.** Both fixed and confirmed by executing code; Kotlin
compiled explicitly (`./gradlew compileDebugKotlin`, exit 0) since `flutter test`
does not cover it.

- **N1** — the latency caps now carry their own hysteresis band (engage 600/1000
  ms, release 550/900 ms). `595/605 ms` now reads `[3,2,2,2,2,…]` and
  `990/1010 ms` reads `[2,1,1,1,…]`, against `[3,2,3,2,…]` before. Caps still
  engage and release on the exact thresholds, a good reading is not
  retroactively capped inside the band, and C2/M3/loss/composite-flicker
  behaviour is unchanged.
- **N2** — the foreground interval now travels with each publish and the lease is
  `max(60 s, 3 × interval)`, so at the 60 s Pro maximum two publishes must be
  lost before it lapses.
- **I was wrong about one of my own suggested fixes**, and said so in the audit:
  clamping the composite before the bar mapping cannot damp this — reproduced
  across four clamp values, every one either stops the cap engaging at all or
  still flickers. The band on the latency thresholds was the only workable
  option of the two I offered.

Gates confirmed by the reviewer: `flutter analyze` clean, `flutter test`
**271/271**, `compileDebugKotlin` exit 0.

**13 Minor items remain open**, passed with recommendations: the twelve from the
report's §8 plus N3 (the cap RTT includes connection setup on a cold pool, so
the first cycle after opening the app is the most exposed — fold into P3 when
throughput calibration is revisited). Nothing blocks release.

The one wording nit raised in the audit was taken the same day: the in-app "How
the score works" screen now names both cap-release figures, interpolated from
the model constants rather than typed in, so the copy cannot quote a threshold
the model no longer uses. Verified by rendering the screen against hardcoded
literals — "550 ms and 900 ms" present, no stray "550.0". Model, PRODUCT_SPEC §5
and the screen all agree. Gates re-confirmed: analyze clean, 271/271.

## Repo rename True Signal → Honest Signal — 2026-08-09 (flutter-architect)

Complete across code, native identity, tests and docs. Gates: `flutter analyze`
clean · `flutter test` **271/271, 0 skipped** · `flutter build apk --release` ✅
52.9 MB (after `flutter clean`, so no stale artifact could mask the change) ·
`flutter build ios --simulator --debug` ✅.

**Verified in the built artifact, not the source:**

| Check | Result |
|---|---|
| Merged release manifest `package` | `com.froggyeye.honestsignal` |
| Merged manifest `android:label` | `Honest Signal` |
| Components | `.MainActivity`, `.HonestSignalService`, `.OverlayService`, `.BootReceiver`, all under the new package |
| Occurrences of `truesignal` anywhere in the APK | **0** |
| AOT snapshot retains `honestSignalBackgroundMain` | ✅ all three ABIs; `trueSignalBackgroundMain` absent from all three |
| Dart snapshot brand strings | `com.froggyeye.honestsignal.pro`, `.../background`, `.../budget`, `.../indicator`, privacy URL on `honest_signal` |
| Built iOS `CFBundleIdentifier` / `CFBundleDisplayName` | `com.froggyeye.honestsignal` / `Honest Signal` |

Also renamed: Kotlin package directory and `TrueSignalService` → `HonestSignalService`
(class, file and the manifest's `.TrueSignalService` reference — judged safe, all
in-repo); SharedPreferences names and the notification channel ID
(`true_signal_*` → `honest_signal_*`; safe because nothing has shipped, and the
new package ID means a fresh data directory regardless); Dart package
`truesignal` → `honestsignal` with every `package:` import; both `.iml` files and
`.idea/modules.xml`.

**Deliberately NOT touched:**

- `ios/Flutter/Generated.xcconfig`, `flutter_export_environment.sh` and
  `ephemeral/*.env` — generated files holding the absolute path
  `/Users/kevinlam/projects/true_signal`, which is still **correct** because the
  directory has not been renamed. A blind rename here would have broken the iOS
  build.
- `store_assets/` — design-truesignal's territory this round.
- `docs/audits/*.md` — signed, dated audit artifacts. They still say "True
  Signal" and cite `TrueSignalService.kt` / `com/froggyeye/truesignal/`. Left as
  the historical record; both still end with `Verdict: PASS`.

**Two decisions I made that need confirming before submission:**

1. **Privacy-policy URL** now points at `mksoft-ltd/honest_signal`
   (`AppConstants.privacyPolicyUrl`, asserted in `release_invariants_test.dart`).
   The GitHub repo does not exist yet, so this presumes the repo will be created
   under the new name. If it is created as `true_signal`, this URL 404s at
   submission and both the constant and the test must move back.
2. **Support URL** now `https://honestsignal.froggyeye.com`, matching the new
   website slug. The subdomain does not exist yet (stage 8).

**Carried into stage 6 (compliance):** the audits' identity-bearing findings were
verified against the *old* bundle ID and binary — merged-manifest applicationId,
the AOT entrypoint name and the iOS symbol scan all need re-confirming against
the renamed artifact. The manifest and AOT checks are re-done above, and the iOS
privacy-symbol scan has now been re-run on the renamed simulator build: zero
references to `AVCaptureDevice`, `PHPhotoLibrary`, `UIImagePickerController`,
`CLLocationManager`, `CNContactStore`, `ATTrackingManager` or
`CTTelephonyNetworkInfo`, so the "no purpose strings required" finding still
holds under the new identity.
