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
| 4a | code-review | mobile-code-reviewer | done — **PASS**. 1.0.0: 2 Critical + 3 Major + N1/N2 fixed and re-verified; 13 Minor open. **1.0.1 (vc3) round re-reviewed 2026-08-14: PASS** — 0 Critical, 0 Major, 7 Minor (N4–N10), gates re-run and all 5 new regression tests confirmed to bite | 2026-08-14 |
| 4b | security | mobile-security-auditor | done — **PASS** (0 Critical, 0 High, 3 Medium, 3 Low); SEC-1/2/3/4 fixed and re-verified 2026-08-09 | 2026-08-09 |
| 5 | metadata | growth-monetization → release-manager | done — ASO (`docs/ASO.md`) + fastlane metadata written both stores | 2026-08-09 |
| 6 | compliance | app-store-review-auditor | done — **PASS** re-verified (C-1/C-2/H-1/H-4 closed; H-2/H-3/M-1/M-2/M-3 carried as stage-7 gate conditions) | 2026-08-09 |
| 7 | publish | store-publisher | uploaded both stores; **awaiting console-only steps before submit** (Apple: privacy label + IAP "Add for Review"; Play: declarations + first rollout). Play listing screenshot `03_statusbar` recaptured from vc3 and re-uploaded 2026-08-15 (images-only edit; no track touched) | 2026-08-15 |
| 8 | website | general-purpose (froggyeye-website skill) | done — page LIVE at https://honestsignal.froggyeye.com (brought forward; clears compliance C-2). Post-publish follow-ups: refresh_store_urls + postprocess once listings live; drop screenshot1.png after recapture; edit hero meta 'Launching on iOS & Android' | 2026-08-09 |

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
  `ephemeral/*.env` — generated files holding the absolute project path. A blind
  rename here would have broken the iOS build. **Confirmed self-healing:** after
  the directory was renamed to `/Users/kevinlam/projects/honest_signal`, the next
  `flutter build ios --simulator --debug` regenerated them with the new path and
  succeeded. No manual edit was ever needed.
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

## Rename completion + URL liveness (conductor, 2026-08-09)
- Directory renamed: `~/projects/true_signal` → `~/projects/honest_signal` (iOS generated xcconfigs regenerate on next build).
- Repo pushed public: https://github.com/mksoft-ltd/honest_signal (sensitive-file scan clean; no keystore exists yet).
- Privacy policy URL LIVE (200): https://raw.githubusercontent.com/mksoft-ltd/honest_signal/refs/heads/main/PRIVACY_POLICY.md
- Subdomain LIVE (200, SSL): https://honestsignal.froggyeye.com (content = stage 8; placeholder acceptable for review).
- Resequence per ASO finding: subdomain + repo push were pre-stage-7 blockers (both URLs are compiled into the binary) — DONE. Stage 8 keeps only promo-page content/SEO/site-grid work.
- Stage 7 must RECAPTURE screenshots from the renamed binary (design deleted raw/ deliberately — old captures showed "True Signal" in-app).

## Stage 5b (store metadata) — completed 2026-08-09 (release-manager)

Store text written into the fastlane layouts, **en-GB only on both stores** —
the Play record was created en-GB and the ASC record's `primaryLocale` was
confirmed `en-GB` by live API read of app `6799269422`. No en-US mirror was
written: house-facts #19 (release notes for a locale the listing does not have
are accepted, never shown, and pollute later reads).

Files written:

- `ios/fastlane/metadata/en-GB/` — `name`, `subtitle`, `keywords`,
  `promotional_text`, `description`, `release_notes`, `support_url`,
  `marketing_url`, `privacy_url`
- `ios/fastlane/metadata/` — `copyright.txt` (`© 2026 Froggy Eye Ltd`),
  `primary_category.txt` (`UTILITIES`), `secondary_category.txt`
  (`PRODUCTIVITY`)
- `ios/fastlane/metadata/review_information/` — `notes.txt`, `first_name`,
  `last_name`, `email_address`, `phone_number` (`+447415533188`),
  `demo_account_required` (`false`)
- `ios/fastlane/app_privacy_details.json` — `DATA_NOT_COLLECTED`
- `android/fastlane/metadata/android/en-GB/` — `title`, `short_description`,
  `full_description`, `changelogs/1.txt` + `changelogs/default.txt`
  (versionCode 1, from `pubspec` `1.0.0+1`; nothing is live on either store, so
  there is no drift to reconcile under house-facts #20)
- `android/fastlane/data_safety_answers.md` — Data safety, App content, IARC
  questionnaire, the `specialUse` FGS declaration text, the
  `SYSTEM_ALERT_WINDOW` justification, and the declarations that must **not** be
  filed

No `video.txt` was written for Play. There is no promo video, and the sibling
shipped apps omit the file rather than shipping it empty; an empty file makes
`supply` write an empty string to the listing.

Every length-capped field was checked programmatically. **Three fields sit at
exactly their limit and must not be edited without a re-count:** both titles
(30/30) and the App Store subtitle (30/30). Keywords 97/100, promotional text
167/170, App Store description 3982/4000, review notes 3984/4000, Play full
description 3973/4000, Play changelog 445/500.

Copy constraints honoured: no absolute network claim (Play Billing's Firelog
client ships — security audit SEC-5); no background-measurement claim on iOS,
which the App Store description states outright as a limitation; the Android
status-bar indicator and floating bubble appear only in the Play listing; no
occurrence of the rival's strings (`TrueSignal` unspaced, "bars lie"); and no
new data-retention figure — 25 hours stays single-sourced in
`PRIVACY_POLICY.md` and the data-safety sheet, while the "last 24 hours" in
store copy is the History *view range*, not retention.

**Open for stages 6/7** (detail and reasoning in `data_safety_answers.md` §9):

1. Play's foreground-service declaration needs **a link to a video** showing the
   status-bar indicator working with the app closed. No such recording exists.
   Most likely thing to stall the Play submission; does not affect Apple.
2. `android/upload-keystore.jks` + `key.properties` still not generated.
3. IAP `com.froggyeye.honestsignal.pro` not created on either store. Play needs
   a billing-permission artifact **active in a track** first; feed the price as
   **£2.4917** ex-VAT for a £2.99 shelf price.
4. Apple's privacy nutrition label must be **published in ASC by the founder**
   (the API 404s on `appDataUsages`) — the JSON here is the source of truth for
   what to enter.
5. Privacy-policy URL is raw Markdown. It is the house convention and returns
   200, but it renders as plain text; the blessed HTML alternative is GitHub
   Pages. Switching is a **code change** (`AppConstants.privacyPolicyUrl` is
   compiled in and asserted in `release_invariants_test.dart`), so stage 6 should
   rule on it rather than stage 7 discovering it.
6. Uploading `name.txt` renames the ASC record from "Honest Signal" to the full
   30-char title "Honest Signal: Network Quality". Apple checks name uniqueness
   at that point, so a `deliver` failure there is a name collision, not a
   formatting error.

## Stage 6 (store compliance) — FAILED 2026-08-09

Full report: `docs/audits/store-compliance.md`. **Verdict: FAIL** — 2 Critical,
4 High, 3 Medium, 3 Low. Audited against the built artifacts (merged release
manifest parsed as XML, the release APK, the built `Runner.app`, the resolved pub
cache, the live GitHub API and live URLs), not against the stage notes.

**Blocking:**

- **C-1 (Apple 2.3.1 / 3.1.1)** — iOS Pro sells a feature the iOS build does not
  implement. `_ThemePicker` is the only writer of `barTheme` anywhere in `lib/`
  and it sits inside `if (Platform.isAndroid) ...[ … ]` in `settings_screen.dart`
  (lines 30–62), so on iPhone the theme is permanently `bars` and a £2.99 unlock
  changes nothing about it. Advertised in three places, and the third points the
  reviewer straight at it: `ios/fastlane/metadata/en-GB/description.txt:37`,
  `paywall_screen.dart:94-98` (not platform-gated, unlike the "Floating
  indicator" bullet directly above it), and
  `review_information/notes.txt:33`. The capability exists — `home_screen.dart:90`
  already themes the iOS mark — so the preferred fix is to ungate the picker and
  make its subtitle platform-aware, not to delete the claim.
- **C-2 (Apple 1.5)** — `support_url.txt` and `marketing_url.txt` both hold
  `https://honestsignal.froggyeye.com`, which returns **200 serving Hostinger's
  default parking page** ("All you have to do now is upload your website files").
  The 200 is why stage 5 and the "placeholder acceptable for review" note above
  both recorded it as live; **it is not acceptable** — a reviewer reads the page
  and sees another company's onboarding instructions. `luckynumbers.froggyeye.com`
  serves a real page, so the subdomain exists with an empty docroot. Fix: bring
  stage 8's page forward, or fall back to `https://froggyeye.com` (metadata-only —
  `AppConstants.supportUrl` has **no consumer in `lib/`**, only a test assertion,
  so the binary is unaffected either way).

**Also required before submission:** H-1 (paywall claims "as rarely as once an
hour" — Android-only — and "set your own daily data budget", which
`clampedForTier` never restricts on either tier, contradicting both store
descriptions); H-2 (Play FGS demo video still does not exist); H-3 (the release
APK is **debug-signed**, `CN=Android Debug`, verified with `apksigner`); H-4 (the
privacy-URL ruling below).

> **⚠ H-3 above is SUPERSEDED — do not act on it.** The upload keystore was
> generated at the start of stage 7 (2026-08-09 09:46) and every release artifact
> since is signed `CN=Froggy Eye Ltd`; see "Signing (closes compliance H-3)" in
> the stage-7 section for the certificate read-back. **Never run
> `keytool -genkeypair` against `android/upload-keystore.jks` again** — an
> artifact has already been uploaded to Play under that key, so overwriting it
> makes every future AAB fail Play's upload-certificate check, recoverable only
> by an upload-key reset request to Google. This pointer exists because the stale
> line above already misled one agent into reporting H-3 as open.

**Privacy-policy URL — RULED: switch to rendered HTML before the submission
build.** On its own the raw `.md` is a soft risk (200, `text/plain` with
`nosniff`, so it displays inline and is legible, and its content is adequate for
5.1.1) and I would have passed it with a recommendation. What makes it required
is that C-1 and H-1 both change compiled Dart, so **a code round is mandatory
anyway** — the marginal cost of one constant plus one test assertion is ~zero and
it retires a recurring portfolio risk. Target
`https://mksoft-ltd.github.io/honest_signal/privacy_policy.html`: it is
independent of stage 8's timing, unlike a froggyeye.com path. Note
`gh api repos/mksoft-ltd/honest_signal` reports **`has_pages: false`** and the
HTML file is not in the tree — enabling Pages is a separate step that has been
skipped after a "successful" push before (ByeByeJob). Update the constant,
`release_invariants_test.dart:35`, `privacy_url.txt` and
`data_safety_answers.md` §1 together, then curl the URL **extracted from the
constant** and confirm 200 `text/html`.

**Verified clean, so stage 7 need not re-litigate:** 16 KB page alignment (all
nine `.so` ≥16384 `p_align` — a Play requirement for targetSdk 35+ that nothing
else in this pipeline had checked), Play Billing **8.0.0** in the dex, targetSdk
36 / minSdk 24, the nine-permission merged manifest with no `AD_ID`,
`allowBackup="false"` + the four `domain` excludes, cleartext disabled,
`ITSAppUsesNonExemptEncryption=false` in the **built** plist, `MinimumOSVersion
15.0`, `TARGETED_DEVICE_FAMILY = 1` in all three configs, zero privacy-class
symbols in the built binary, no app-level `PrivacyInfo.xcprivacy` needed
(`path_provider_foundation` resolved to 2.6.0, which is FFI-based and ships no
plugin), and **no IAP bypass in a release binary** — `ScreenshotMode.isEnabled`
is `_flag && !kReleaseMode` and `debugForcePro()` is inside `assert(() { … }())`.

I agree with SEC-5's stage-6 note: **"No data collected" holds on both stores**
and `data_safety_answers.md` says the right things. Checked rather than
inherited — the datatransport CCT backend is Play Billing's own client inside
Play's purchase-processing carve-out, the probes carry no identifier, and
`pubspec.yaml` genuinely holds no analytics/ads/attribution/crash SDK.

**iOS 2.5.4 is not engaged at all** (no `UIBackgroundModes` in source or in the
built plist). **4.2 is Low** — the iOS free tier is live measurement, five
metrics, a verdict, freshness, a budget counter and the published method, with
history charts on Pro. The description's "HONEST ABOUT ITS LIMITS" section and
the in-app staleness copy are what keep it low and **must not be edited away**.

**`specialUse` assessment: probably survives, Medium risk, expect one round of
correspondence.** The 6-hour `dataSync` cap rebuttal is correct and should be
filed verbatim. Three additions are in the report: lead with "the notification's
icon *is* the feature", state that the user can stop it from inside the app, and
pre-empt the likelier counter-argument — not "use dataSync" but "use WorkManager
and a plain notification" — with WorkManager's 15-minute floor and Doze
deferral, which for an app whose claim is that the number is honest makes the
reading not degraded but false.

**Additions to the stage-5 checklist:** the two Criticals and H-1; re-run
analyze + suite and rebuild both platforms after the code round; capture
screenshots from the post-C-1 binary (`raw/` holds only `.gitkeep`) and open
every rendered PNG; check `05_pro` — ASC's IAP review screenshot — for the
Android-only "Floating indicator" bullet, since the harness is Android-only by
design (M-1); generate the **512×512 Play icon**, which does not exist while the
1024 masters make the set look complete; and create both fastlane image
directories, neither of which exists.

## Stage 6 fix round — C-1 / H-1 / H-4 — 2026-08-09 (flutter-architect)

Gates: `flutter analyze` clean · `flutter test` **273/273, 0 skipped** (2 new) ·
`flutter build apk --release` ✅ 52.9 MB · `flutter build ios --simulator
--debug` ✅. Both platforms rebuilt as required.

**C-1 (Critical).** `_ThemePicker` moved out of the `if (Platform.isAndroid)`
block in `settings_screen.dart`; the `Indicator` section header now renders on
both platforms with the two Android-only tiles gated inside it. The picker takes
a `description` that is platform-true — "in the app and in the status bar" on
Android, "in the app" on iOS — because there is no status bar to theme on
iPhone. Nothing else changed: `home_screen` already fed `barTheme` to
`SignalBars` on iOS, so the capability existed and only the control was missing.

**H-1 (High).** Both offending paywall bullets are now platform-specific. The
daily-data-budget claim is **gone entirely** — `clampedForTier` never touches
`dailyBudgetMb`, so it is free on both tiers and both store listings say "on
every tier" out loud. The interval bullet no longer promises a background rate
on iOS, where there is no background measurement.

**Regression tests — verified to bite.** There was no `SettingsScreen` widget
test at all. Added two, in `screens_test.dart`. Widget tests run with
`Platform.isAndroid == false`, which *is* the iPhone path, so they test exactly
the case that failed. Confirmed by reintroducing both defects: the C-1 test fails
`Found 0 widgets with text "Indicator style"`, and the H-1 test fails
`Found 1 widget with text containing daily data budget`. Both restored.

**H-4 (High).** Privacy-policy URL moved to the rendered-HTML variant in all
four places — `AppConstants.privacyPolicyUrl`, `release_invariants_test.dart`,
`ios/fastlane/metadata/en-GB/privacy_url.txt`,
`android/fastlane/data_safety_answers.md` — verified byte-identical across all
four. The doc comment on the constant, which still described it as the raw
Markdown URL, was corrected. The test now also asserts the URL ends in `.html`,
so a future edit cannot quietly go back to raw Markdown.

Verified by extracting the string **from the constant** and fetching that:

```
https://mksoft-ltd.github.io/honest_signal/privacy_policy.html
  status=200  content-type=text/html; charset=utf-8
```

The rebuilt release APK contains that URL and **zero** occurrences of the old
`raw.githubusercontent.com` one.

**`privacy_policy.html` is now generated, not hand-written.** The committed copy
rendered every hard-wrapped source line as its own `<p>` — 47 paragraphs for 25
Markdown blocks, and no `<ul>` at all. `scripts/build_privacy_html.py`
(dependency-free) now renders it: 8 `<h2>` for 8 Markdown headings, 3 `<ul>`
holding 9 `<li>` for 9 bullets, inline bold/italic/code/links, and paragraphs
joined properly. `PRIVACY_POLICY.md` remains the source of truth; re-run the
script after any edit.

### ⚠ Outstanding — needs a push, not a code change

**The live page still serves the OLD rendering.** The improved
`privacy_policy.html` is regenerated locally but **not committed or pushed**, so
`mksoft-ltd.github.io` still returns the 47-paragraph version (confirmed by
diffing the live response against the local file). H-4's *requirement* — 200,
`text/html` — is already satisfied by the live page, so this is a quality gap
rather than a compliance gap, but it should ship before submission.

I did not push: the repo is **public**, and the working tree carries a lot of
uncommitted pipeline output (`ios/fastlane/`, `android/fastlane/`,
`docs/audits/store-compliance.md` are all untracked). Deciding what becomes
public belongs to the conductor, and the security audit's own advice is to check
what a `git add .` would sweep in before the first push.

## Stage 6 — re-verified PASS 2026-08-09

Fix round by flutter-architect (C-1, H-1, H-4) re-verified by
app-store-review-auditor. Stage 8 incidentally closed C-2. **Verdict: PASS** —
every defect in code and metadata is closed. Detail in the "Re-verification"
section of `docs/audits/store-compliance.md`.

Gates re-run by the auditor rather than quoted: `flutter analyze` clean ·
`flutter test` **273/273, 0 skipped**.

- **C-1** — `_ThemePicker` is out of the `Platform.isAndroid` block and genuinely
  functional on iOS (Pro gate routes a locked tap to the paywall; `onChanged`
  writes through the real controller). Their regression test was **checked, not
  trusted**: re-gating the picker reproduces `Found 0 widgets with text
  "Indicator style"`, and the file was restored to `md5
  06402cf76d7fc93121ab012f90b51f60`. Their point about widget tests running with
  `Platform.isAndroid == false` — the same branch an iPhone takes — is correct
  and is why this test is meaningful rather than decorative.
- **H-1** — both bullets checked against the constants, not the prose: iOS "every
  2 seconds… instead of the standard 5" matches `minForegroundInterval`/
  `defaultForegroundInterval`; Android "once a minute to once an hour" matches
  60/3600 s. Deleting the data-budget claim rather than rewording it was right.
  Test bites (`Found 1 widget with text containing daily data budget`); restored.
- **H-4** — all four copies agree; the URL was **extracted from the constant and
  that string fetched**: 200 `text/html`. **Their caveat is stale** — commit
  `70e696c` is on `main`, `main` is in sync with `origin/main`, and the live page
  is **byte-identical** to the local file (4,547 bytes, 15 `<p>`, 8 `<h2>`,
  3 `<ul>`), with viewport/charset/title. No push decision is outstanding; the
  fastlane trees, `scripts/` and the audit remain untracked and private.
- **C-2** — `honestsignal.froggyeye.com` now serves the real promo page. Body
  read, not just the status code: Android-only features are qualified in place
  and the FAQ says outright that the status-bar indicator does not work on
  iPhone. Its unqualified "Indicator themes" Pro line is correct **because** C-1
  was fixed by ungating rather than by deleting the claim.

**Carried into stage 7 as gate conditions** (not compliance defects — stage 7
produces these): H-2 the FGS demo video, which needs a signed build on a device
and is therefore downstream of H-3; H-3 the upload keystore — checked the hazard
of generating one in a now-public repo, and `android/.gitignore` already excludes
`key.properties`, `**/*.keystore` and `**/*.jks` (confirmed with
`git check-ignore -v`), so it is safe; M-1 the `05_pro` IAP review screenshot vs
the Android-only paywall bullet; M-2 the 512×512 Play icon and the fact that no
screenshots exist at all; M-3 the `specialUse` declaration wording.

> **All five were produced in stage 7 — none is outstanding.** H-3 the keystore
> (2026-08-09 09:46; **never re-run `keytool -genkeypair` against it** — see the
> superseded note in the stage-6 FAILED block above for why), H-2 the demo video
> (live), M-1 the IAP review screenshot (recaptured on iOS — the Android one
> showed "billed by Google Play"), M-2 the 512×512 icon and both screenshot sets,
> M-3 filed with the declaration text. Detail in the stage-7 section.

**Trap for whoever re-checks a `Platform.isX ?` fix in the APK — the Android
artifact cannot verify an iOS branch.** Two mechanisms, both of which look like a
broken build: any literal containing a non-Latin-1 character (an em-dash, so most
of this app's copy) is stored as a Dart **TwoByteString** and is invisible to an
ASCII byte grep — search UTF-16LE instead; and `Platform.isAndroid` is
`@pragma("vm:platform-const")` in this SDK, so AOT folds the ternary and
tree-shakes the dead branch, meaning the iOS strings are *supposed* to be absent
from `libapp.so`. Verify iOS-branch copy in the widget suite or an iOS build.

## Critical Android fix — status-bar icon hidden by IMPORTANCE_LOW — 2026-08-09

The channel used `IMPORTANCE_LOW` on the belief, recorded in a comment, that it
was "visible in the status bar but never intrusive". That was true before
Android 11 and false since: anything below `IMPORTANCE_DEFAULT` gets **no
status-bar icon** and lands in the shade's Silent section only. The status-bar
icon is the product's headline Android feature, so the app was shipping without
it. Comment corrected in place.

**Fix.** Channel raised to `IMPORTANCE_DEFAULT` and kept genuinely silent —
`setSound(null, null)`, `enableVibration(false)`, `vibrationPattern = null`,
`enableLights(false)` on the channel, plus `setSilent(true)` on the builder.
Channel ID bumped to `honest_signal_indicator_v2` because **importance is fixed
at creation and cannot be raised by a later update**; the v1 channel is deleted
by ID on setup. `setPriority(PRIORITY_LOW)` is kept deliberately: it applies only
below API 26, where a low-priority notification *does* show a status-bar icon.

**Verified by running it, on the stock emulator (API 36 / Android 16,
`sdk_gphone64_arm64`), release build, real network — not by reading.**

| Check | Evidence |
|---|---|
| Bug reproduced first | Rebuilt with v1/`IMPORTANCE_LOW`, clean install: `mImportance=2`, **no icon** in the status bar. Confirms the publisher's finding independently. |
| (a) Icon renders | 5-bar icon present after the clock. Proven by A/B: `am force-stop` removes it and the neighbouring icons shift left; restart brings it back. |
| (b) No sound / vibration | `isNoisy=false`, `sound=null`, `vibrate=null`, channel `mSound=null`, `mVibrationEnabled=false`, notification flag `SILENT`. |
| (b) No heads-up peek | `headsUpContentView=null`, no HeadsUpManager entries, and **six rapid screenshots across a live score change show no banner**. |
| (c) Icon updates with score | Killing the network changed the drawable `0x7f060023` → `0x7f06001e`, confirmed visually (solid 5 bars → dimmed mark) and back again on restore. |
| Upgrade path | Installed the broken v1 build, then upgraded **over it** without uninstalling: icon appears, `v2 mImportance=3 mDeleted=false`, `v1 mImportance=2 mDeleted=true`. This is the case the ID bump exists for. |

One field worth not misreading: the record shows `requestedImportance=2`
alongside `naturalImportance=3`. The 2 is `NotificationCompat`'s mapping of the
pre-O `PRIORITY_LOW`; from API 26 the channel governs and the effective
`importance=3`. Likewise `mIsInterruptive=true` appears on a content update —
that is Android's ranking bookkeeping, not a peek; `isNoisy=false` and the frame
captures are the alerting evidence.

**Version.** `pubspec.yaml` → `1.0.0+2`; merged release manifest confirms
`versionCode="2"`, `versionName="1.0.0"`, `foregroundServiceType="specialUse"`.
**iOS was not rebuilt** — build 1 is already uploaded and valid.

Gates: `flutter analyze` clean · `flutter test` **273/273, 0 skipped** ·
`flutter build appbundle --release` ✅ 51.9 MB.

## Stage 7 (publish) — 2026-08-09 (store-publisher)

Both stores hold the build, the listing and the IAP. **Nothing is submitted for
review yet** — what is left is console-only on both sides and is listed at the
bottom.

Every store write below was confirmed by reading it back from the API. Exit
codes were not treated as evidence: `deliver` in particular reports success
while its own read-back is still lagging.

### Signing (closes compliance H-3)

`android/upload-keystore.jks` generated per house pattern §7 (alias `upload`,
RSA 2048, 10000 days, `CN=Froggy Eye Ltd`), with `android/key.properties`. Both
confirmed git-ignored by `git check-ignore -v` before anything was built.

Verified on the **packaged artifact**, not the Gradle config: the AAB's
`META-INF/UPLOAD.RSA` certificate SHA-256 is
`0A:B1:B0:CE:39:C7:E6:AB:7A:92:45:53:09:C1:70:87:0A:08:4B:98:13:B1:19:2F:41:2C:C8:44:3A:1B:A9:0E`,
byte-identical to the keystore's, and `jarsigner -verify` reports `jar verified`.

### Screenshots — the App Store and Play sets come from different devices

Compliance M-1 flagged the Android-only bullet on `05_pro`. Opening every
capture showed the problem is wider: **three shots carried Android-only text
into the App Store set**, and two of them are the first two things a reviewer
sees. The app's code is platform-correct in all three cases — only the captures
were wrong.

| Shot | Android capture says | iOS actually renders |
|---|---|---|
| `00_onboarding` (App Store #1) | "Next, **Android** will ask whether Honest Signal may show notifications… status bar" | nothing — the paragraph is inside `if (Platform.isAndroid)` (`onboarding_screen.dart:47`) |
| `01_home` (App Store #2) | "As reported by **Android**" | "As reported by iOS" (`home_screen.dart:266`) |
| `05_pro` (Apple's IAP review screenshot) | "Floating indicator" bullet, "…in the status bar", "billed by **Google Play**" | bullet absent, "in the app", "billed by **Apple**" |

So the App Store set is now captured on an **iPhone 17 Pro Max simulator** (the
same 6.9" 1320x2868 panel as the 16 Pro Max), light appearance, status bar
pinned to 09:41. The committed harness cannot do this — `binding.takeScreenshot`
returns the launch storyboard on the iOS simulator, which is why it is
Android-only by design. The captures were taken host-side with
`xcrun simctl io screenshot`, synchronised by a stdout marker from a temporary
test file that was deleted afterwards. The committed harness is untouched.

`render.sh` now frames the Play set from `raw/` and the App Store set from
`raw_ios/` (`RAW_DIR` overrides; `frame.html` takes a `dir` parameter). Before
this, both sets framed from `raw/` — the trap that produced the problem above.

All nine rendered PNGs were opened and looked at, and all are md5-distinct.
Play gets 5 shots with the status-bar shot at #2, App Store gets 4 with
how-it-works at #3 — the order in `docs/ASO.md` §4, not the one in
`screenshot_specs.md`.

Also generated the **512x512 Play icon** from `store_assets/icon/icon_master.png`
(M-2 — it did not exist) and wired in the 1024x500 feature graphic.

### The status-bar indicator did not work (found here, fixed by flutter-architect)

Recording the H-2 demo video exposed that the foreground service posted its
notification but **no status-bar icon appeared** — the app's headline Android
feature, and the whole basis of the `specialUse` declaration.

Proven on the stock emulator with a control, not inferred: our notification
(`IMPORTANCE_LOW`) had no status bar icon and sat in the shade's "Silent"
group, while a `DEFAULT`-importance notification posted via
`cmd notification post` showed its icon immediately. Since Android 11, stock
Android hides status-bar icons for silent notifications;
`HonestSignalService.kt` carried a comment asserting the opposite.

Fixed by flutter-architect (channel `honest_signal_indicator_v2`,
`IMPORTANCE_DEFAULT`, still silent) and **re-verified here independently** on
the release APK: icon present in the status bar, `mImportance=3`, `sound=null`,
`vibrate=null`, `headsUpContentView=null`.

### FGS demo video (closes compliance H-2)

**https://honestsignal.froggyeye.com/fgs-demo.mp4** — live, HTTP 200,
`video/mp4`, 2,133,646 bytes, valid `ftypisom`. 85 s, 1080x2400, h264,
faststart.

Captioned so it stands on its own without narration. It shows the live reading
in the app; the ongoing notification with its "Turn off" action; leaving the app
by Home **and** by swiping it out of Recents; the icon still updating with the
app closed; Wi-Fi and mobile data cut so the score and icon fall; and both
recovering. Recorded with `adb screenrecord`, captions composited with ffmpeg
`overlay` (this ffmpeg has no `drawtext`). Frames from the finished encode were
sampled and checked.

Recorded twice — the first take had a leftover debug notification in the shade.

### Apple — staged, 2 console steps from submission

| Item | State |
|---|---|
| Build | 1.0.0 (1), `processingState VALID`, attached to the version |
| IPA identity | `MinimumOSVersion 15.0`, `UIDeviceFamily [1]`, `ITSAppUsesNonExemptEncryption false`, signed `Apple Distribution: Froggy Eye Ltd (696939LPWV)` |
| Version | 1.0.0, `PREPARE_FOR_SUBMISSION`, `releaseType AFTER_APPROVAL` |
| Name | "Honest Signal: Network Quality" — **no collision**; the rename went through |
| Metadata | en-GB only; description 3981, keywords 97, promo 167 chars |
| Screenshots | exactly 4, `APP_IPHONE_67`, all `COMPLETE` — counted server-side, not trusted from the log |
| Categories | UTILITIES / PRODUCTIVITY (`deliver` left these null; set via API) |
| Price | free — price schedule created and read back as `customerPrice 0.0` |
| Territories | 175, `availableInNewTerritories: true` |
| Age rating | all-`NONE` / all-`false`, no override (expect 4+) |
| Content rights | `DOES_NOT_USE_THIRD_PARTY_CONTENT` |
| Review contact | Kevin Lam, `+447415533188`, `info@froggyeye.com`, notes 3983 chars |
| IAP | `com.froggyeye.honestsignal.pro`, NON_CONSUMABLE, **READY_TO_SUBMIT**, GBR £2.99 read back, iOS-captured review screenshot `COMPLETE` |
| Review submission | `8dd8f497-16a9-4c7b-8352-a34df5944a93`, empty, waiting |

iOS export needed a manual App Store profile — the App Manager API key is
refused for Xcode cloud signing. `HonestSignal App Store` was created via
`POST /v1/profiles` and `ios/ExportOptions.plist` is committed so the lane is
reproducible.

### Play — uploaded, declarations outstanding

AAB **versionCode 2** on the internal track, `status: completed` (deliberately
not `draft`: a draft artifact does not grant billing permission, and the IAP
needs it). Listing read back with title, short and full description, 1 icon,
1 feature graphic, 5 phone screenshots, en-GB only, changelog on `changelogs/2`.

IAP `com.froggyeye.honestsignal.pro` is **ACTIVE**, `legacyCompatible: true`,
GB shelf price **£2.99** across 173 regions — fed as £2.4917 ex-VAT, and the GB
shelf price was checked in the conversion response before the product was
written.

The production track is deliberately untouched: a new app's first production
rollout has to happen in the console, and staging a half-release would only
confuse the publishing overview.

### Console-only work left

Neither store has an API for these. Answers are pre-written in
`android/fastlane/data_safety_answers.md`; the FGS text is §6, the
`SYSTEM_ALERT_WINDOW` justification §7.

**Apple** — 2 steps, then one command:
1. *Founder only.* App Privacy → "Data Not Collected" → **Publish** (the
   separate Publish button matters). The API exposes no privacy relationship at
   all — `appDataUsages`, `appDataUsagesPublishState` and `appPrivacyDetails`
   all 404. Until it is published the version cannot join a review submission.
2. On the **IAP's own page**: "Add for Review" → pick the existing Draft
   submission. There is no API for this: `POST /reviewSubmissionItems` rejects
   both `inAppPurchase` and `inAppPurchaseV2`; `appStoreVersion` is the only
   reviewable relationship it accepts.
3. Then `ruby scripts/asc_finish_submission.rb` — it adds the version, **refuses
   to submit unless the submission holds both items**, and submits.

**Play** — all in App content / Store settings, then the first rollout:
privacy policy URL, App access (no login needed), Ads = No, Data safety (no
collection), Content rating (IARC non-game questionnaire — **the IARC Terms of
Use acceptance is a legal acceptance and needs the founder**), Target audience
18+, News/COVID/Government/Financial/Health all No, **Foreground service
permissions** (text from §6 plus the video URL above), **Advertising ID = No**
(the hidden quick-checks blocker), Store settings, and **Countries/regions,
which are empty by default and will silently block the release**. Then a
production release from versionCode 2 and Publishing overview → Send for review.

One finding for the portfolio: `POST /androidpublisher/v3/applications/{pkg}/dataSafety`
**does** exist and would file Data safety without the console, but its
`safetyLabels` field takes Play's Data-safety **CSV**, not JSON ("Invalid header
row. Download the sample CSV file"), no sibling app has one to copy, and there
is no GET to read the result back. Not worth guessing a schema for a compliance
declaration that cannot be verified.

### Repeating the release

```bash
cd ios     && bundle exec fastlane release          # build, upload, submit
cd android && bundle exec fastlane internal_upload   # AAB -> internal
cd android && bundle exec fastlane promote           # internal -> production
```
`ios/fastlane/metadata_only` re-uploads text and screenshots without a build.
Both `deliver` and `supply` overwrite server state, so re-running a stage is the
normal fix rather than something to avoid.

## Stage 7 completion — BOTH STORES SUBMITTED FOR REVIEW (conductor, 2026-08-09)
- APPLE: privacy label published (founder-delegated click-through: Data Not Collected); IAP attached to draft submission via console "Add for Review"; scripts/asc_finish_submission.rb added the version, verified 2 items, submitted → version state WAITING_FOR_REVIEW.
- PLAY: all declarations completed in console (privacy policy URL, app access=no restrictions, ads=no, IARC content rating [ESRB E/PEGI 3; Brazil 14 via purchases — expected], target audience 18+, data safety=no collection, advertising ID=no, government=no, financial=none, health=none, FGS specialUse declaration with video https://honestsignal.froggyeye.com/fgs-demo.mp4); store settings: Tools, info@froggyeye.com, honestsignal.froggyeye.com; countries: all (176 + rest of world); production release "2 (1.0.0)" from versionCode 2 with copied en-GB notes; Publishing overview → 11 changes SENT FOR REVIEW (banner: "Changes in review"; quick checks auto-transmit on pass).
- Post-approval follow-ups (when apps go LIVE): website store buttons (refresh_store_urls.py + postprocess.py --only honestsignal + deploy), drop screenshot1.png onto the promo page, edit hero meta "Launching on iOS & Android", delete old True Signal Play draft (founder, optional).
- Re-release one-liners: `cd ios && bundle exec fastlane release` · `cd android && bundle exec fastlane internal_upload` then `promote`.

## 1.0.1 (versionCode 3) — user-feedback round on the Android indicator (build, 2026-08-14)

Four items of user feedback about the status-bar indicator, relayed by the
founder. Android-only round; nothing touched that the waiting iOS submission
(1.0.0 build 1, WAITING_FOR_REVIEW) depends on, and the version bump is
Android's alone.

**1. "The bars need a contrasting background so they're clear against any
wallpaper." — done.** A status-bar small icon is an alpha mask: Android picks
the colour and uses the drawable for shape and opacity only, so contrast can
only come from mass and relative alpha. The default icon now draws the mark on
a 44%-alpha plate with lit elements at 100% and a transparent moat cut between
them. Unlit slots keep their interior at plate alpha rather than being cut
through — the first design cut them out, and over a pale patch of wallpaper an
*empty* bar then lit up as brightly as a full one. `AppSettings
.highContrastIndicator` (free, default on, Android only) switches back to the
original mark. The 36 masks are generated by
`android/tools/generate_indicator_icons.py`; the plain 18 regenerate
byte-for-byte identically apart from float formatting.

**2. "Could the bars be green/amber/red?" — impossible where they asked,
delivered everywhere it is possible.** A coloured status-bar icon cannot be
done on modern Android at all. `SignalColours.forBars` (extracted from
`SignalBubbleView` so the bubble and the notification cannot drift) is now
`setColor` on the notification, and below Android 16 the shade entry is
`setColorized(true)` — a red / amber / green card that tracks the score.
On Android 16 the notification is promoted instead, and colorized is a
documented disqualifier for promotion, so the two are an either/or.

**3. "It's confusing which bar is Honest Signal." — done, two ways.** The plate
is a silhouette the system's radio bars never have, and on Android 16 the
promoted chip carries `setShortCriticalText("HS")`. "HS" lettering *inside* the
24dp mask was prototyped and rejected on the evidence: at status-bar size the S
reads as a 5 and the bars lose half their height.

**4. "It gets deprioritised when the status bar is crowded." — the available
half.** No API pins icon order; the ranking is the system's and importance is
its dominant term. Raising the channel to IMPORTANCE_HIGH would have cost a
third channel ID, every existing install's channel settings (importance is
fixed at creation) and a heads-up card nobody asked for — declined. Android 16's
promoted ongoing notification is the sanctioned answer: `POST_PROMOTED
_NOTIFICATIONS` in the manifest, `setRequestPromotedOngoing(true)`, and a
per-post `canPostPromotedNotifications()` check because the user can revoke it.
The chip sits beside the clock, outside the icon row that gets culled. Below
Android 16 this remains OS-controlled and the founder should say so.

### Verified by running, on the stock `Medium_Phone_API_36.1` emulator

- **Upgrade path** (the path every live user takes): installed the live
  versionCode 2 release APK, enabled the indicator, then installed versionCode 3
  over it. Channel stayed `honest_signal_indicator_v2` across the upgrade, the
  indicator kept working, and the small icon changed from `ic_signal_bars_5` to
  `ic_signal_bars_plate_*` — read out of `dumpsys notification` and mapped back
  through `aapt2 dump resources`, not judged by eye.
- **Silence**: `isNoisy=false`, `headsUpContentView=null`, `sound=null`,
  `vibrate=null`, `flags=…|SILENT`, `mImportance=DEFAULT`. The
  `requestedImportance=2 / naturalImportance=3` pair is the known false alarm.
- **Promotion**: the system set `FLAG_PROMOTED_ONGOING` itself, and the chip
  renders with the "HS" label — screenshotted with ten other notifications
  posted, where it survives.
- **Live updates**: taking the network away moved the icon to `plate_0` and the
  colour to `0xffe0483c`; the settings switch moved it between plated and plain.
- **Colorized fallback**: forced `canPromote()` false in a throwaway debug build
  to reach the Android 15-and-below path on this API 36 device — the shade card
  renders in the score colour. Reverted; not a real API 34 device.
- Light and dark status bars both captured. The captures and what each one
  proves are in `docs/verification/1.0.1/`.

### Gates

`flutter analyze` clean · `flutter test` 279/279 · `flutter build appbundle
--release` 52.0MB · Kotlin compiled (the new NotificationCompat calls needed an
explicit `androidx.core:core-ktx:1.17.0` — the compile classpath resolved 1.13.1
while the runtime classpath was already on 1.17.0) · merged manifest re-parsed:
package, FGS `specialUse` + subtype property and the transitive BILLING /
DYNAMIC_RECEIVER pair unchanged, `POST_PROMOTED_NOTIFICATIONS` the only
addition, justified in PRODUCT_SPEC §9.

New regression tests, each verified to fail against the reintroduced defect:
settings written before 1.0.1 upgrade with the plate on; the plate survives
free-tier clamping; every theme × level has both masks; `IndicatorIcons` maps
all 36; each plated mask still carries its even-odd plate path.

### For a later stage

- **`store_assets/screenshots/out/play/03_statusbar.png` is now stale** and
  should be recaptured: it is framed from the settings capture, which has gained
  the "High-contrast icon" row, and its status bar shows the old plain mark.
  Deliberately not recaptured here.
  **— done 2026-08-15 (store-publisher); superseded, do not act on this again.**
  See "Play listing screenshot recaptured" below. One correction to the note
  above: the shot has no status bar in it at all. The harness captures the
  Flutter surface only (`convertFlutterSurfaceToImage`), so no system status bar
  is ever in a raw capture — which is exactly why `screenshot_specs.md` §3 frames
  the *control* that turns the indicator on rather than the indicator itself.
  Only the missing "High-contrast icon" row was actually stale.
- Play changelog for versionCode 3 written at
  `android/fastlane/metadata/android/en-GB/changelogs/3.txt` (496 chars, en-GB
  only — house rule 19: notes for a locale the listing lacks are swallowed).

### Stage 4a — 1.0.1 round re-reviewed 2026-08-14 (mobile-code-reviewer)

**Verdict: PASS.** 0 Critical, 0 Major, 7 Minor (N4–N10). Full detail in
`docs/audits/code-review.md` under "1.0.1 feedback round review — 2026-08-14".
Nothing blocks the versionCode 3 upload.

Gates re-run by the reviewer rather than taken from the author's note: `flutter
analyze` clean · `flutter test` **279/279, 0 skipped** · `flutter build
appbundle --release` **exit 0, 52.0 MB**.

Checked by executing code, not by reading:

- **All five new regression tests bite.** Each defect was reintroduced, the
  suite run, the file restored and its MD5 re-checked; each failure was
  isolated to the test that owns it. `git status` is clean at `409e0fb`.
- **The 36 masks were verified against a checker written from PRODUCT_SPEC §8
  prose, not from `generate_indicator_icons.py`**, so a generator bug could not
  agree with the check. Alpha counts, plate subpath structure, element-for-
  element matching and the 0.42-unit moat are correct on all 3 themes × 6
  levels, including wave, whose lit arcs are strokes and whose plate cuts are
  their filled outlines. All 36 survive R8 resource shrinking in the AAB.
- **Channel untouched** (`honest_signal_indicator_v2`, IMPORTANCE_DEFAULT, v1
  still deleted); **API boundary correct** (35 → colorized, 36 → chip, 36 with
  promotion revoked → colorized); **plate × Pro theme orthogonal** in both
  directions; **merged manifest from the built AAB gains only
  `POST_PROMOTED_NOTIFICATIONS`**; **no iOS exposure** (nothing under `ios/`
  changed and both new Dart blocks are inside `Platform.isAndroid`); **changelog
  496 chars, en-GB only, no false claims**.
- **The core-ktx pin was checked both ways**: without it the release *runtime*
  classpath already resolves `androidx.core:core` to 1.17.0, so the pin only
  aligns the compile classpath and does not change the library that ships.

The Minor worth taking first is **N4**: the high-contrast toggle has no test
that proves it does anything. Hardcoding `highContrast: true` at both Dart call
sites leaves 279/279 green, and so does deleting the `if (highContrast)` branch
from all three arms of `IndicatorIcons.resourceFor`. The
`'highContrast': true` assertion in `indicator_controller_test.dart` looks like
coverage but the fixture leaves the field at its default, so it pins agreement
rather than behaviour. The shipped behaviour is correct — the device capture
proves it — but nothing stops the next change from silently severing it.

## 1.0.1 released to Play production (conductor, 2026-08-14)

- Code review: **PASS** (0 Critical/Major, 7 Minor N4–N10) — see the section above and `docs/audits/code-review.md`.
- **History scrub before the public push:** the baseline commit had swept the previously-untracked fastlane trees into the tree — including `ios/fastlane/metadata/review_information/` (founder name + portfolio phone number) and both `report.xml` fastlane logs. Local-only commits were rewritten to exclude those paths, `.gitignore` now pins all three, and after the push the phone-number raw URL was confirmed **404** while the rest of the metadata is public as per house convention. The files remain on disk for `deliver`/local use.
- Pushed as `195dedc` (rewritten hashes: baseline `9d2840d`, release `e5c26ae`, captures `d61845c`).
- **Play:** vc3 AAB uploaded via the raw androidpublisher path (34 s; house-facts §28) with the en-GB changelog → internal `completed`, then promoted: production track PUT + plain commit **accepted** (no console click needed for an update, unlike the first rollout). Track read-back: production = `1.0.1 (3) completed`. Google's review/quick checks run automatically; users update when it clears.
- **Apple:** untouched; 1.0.0 build 1 still WAITING_FOR_REVIEW. The 1.0.1 changes are Android-only — no iOS release is owed for this round.
- Follow-ups in flight: Play listing screenshot `03_statusbar` recapture from the vc3 build (store-publisher); N4 + minor nits N5/N6/N9/N10 (flutter-architect, point release — no store upload owed until the next release rides); Lucky Numbers promo-page Play button (founder-approved hand edit, website session).

## Play listing screenshot recaptured from vc3 (store-publisher, 2026-08-15)

`03_statusbar` — the only Play listing image the 1.0.1 round left stale — was
recaptured from the current source and re-uploaded. Nothing else on either store
was touched: no track, no release, no metadata text, and the App Store set and
`raw_ios/` were not opened (1.0.0 build 1 is still with Apple).

- **What was actually stale.** The settings screen gained the "High-contrast
  icon" row in 1.0.1, and the shipped artwork predated it. The 1.0.1 note also
  said "its status bar shows the old plain mark" — it does not, and could not:
  the harness captures the Flutter surface, so no raw capture has a system status
  bar in it. That is the premise of `screenshot_specs.md` §3, which frames the
  control rather than a composited mock-up of the icon.
- **Capture.** `flutter drive` + `integration_test/screenshots_test.dart` with
  `--dart-define=SCREENSHOT_MODE=true` on `Medium_Phone_API_36.1`, light
  appearance, 1080 × 2400, tier marker `pro` written by the driver.
- **Only `raw/03_settings.png` was adopted.** The other four captures were
  restored to the versions that produced the live artwork, because a fresh
  capture of them differs only in clock-dependent pixels (the history chart's
  axis label reads the capture time) and the brief was to change one shot. The
  new "About the status-bar icon" section that 1.0.1 added to How-it-works sits
  below the fold and does not reach the framed shot. `./render.sh play` then
  reproduced `01_lying`, `02_home`, `04_history` and `05_method`
  **byte-for-byte identical** to the live set — which also demonstrates the
  framing pipeline is deterministic on this machine.
- **Upload.** Raw androidpublisher edit, not `supply`: Play orders screenshots by
  upload order, so preserving position means deleting and re-uploading the whole
  set, and the raw path makes it visible that no track or listing text is in the
  edit. Staged set was SHA-1-matched against the local files *before* commit.
- **Server read-back (fresh edit, after commit):** 5 phone screenshots, order
  preserved, position 2 (0-indexed) now `62704ba776aac1a9a437e418309e662f8a1790d0`
  = local `3_03_statusbar.png`; the other four SHA-1s unchanged; icon and feature
  graphic unchanged; production track still `1.0.1 (3) completed`.
- **Emulator hazard worth knowing:** two capture runs were spoiled by the shared
  emulator's display size and dark/light appearance changing *mid-run* (captures
  came out 1320 × 2868, and dark). Neither idle time nor a plain app launch
  reproduced it, so something outside this session touches `emulator-5554`.
  Re-asserting `cmd uimode night no` and `wm size reset` immediately before the
  run, and checking the geometry and appearance of the resulting PNGs rather than
  trusting the green test result, is the guard.
