# Honest Signal — store compliance audit (stage 6)

Written by app-store-review-auditor, 2026-08-09. Inputs: `PIPELINE.md`,
`docs/PRODUCT_SPEC.md`, `docs/ASO.md`, `docs/audits/code-review.md`,
`docs/audits/security.md`, every file under `ios/fastlane/` and
`android/fastlane/`, the Dart and Kotlin sources, and — where a claim could be
checked against an artifact rather than a document — the **built** release APK,
the **built** iOS simulator app, the **merged** release manifest parsed as XML,
the resolved pub cache, the live GitHub repo API and the live URLs.

House rule applied throughout: audit the artifact, not the annotation. Several
findings below contradict notes that earlier stages marked as resolved.

---

## APP REVIEW RESULT

**Approval probability:** iOS **Low** as it stands · Play **Medium** (blocked on
mechanics, not on policy) — both **High** once the four blockers close.
**Platforms analysed:** Apple App Store and Google Play.

Two blockers are new to this stage and neither is a documentation slip: the iOS
build sells a Pro feature it does not implement, and the support URL that both
listings will carry serves a hosting-provider parking page. Two more (the FGS
video, the upload keystore) were correctly predicted by stage 5 and remain open.

---

## REJECTION RISKS

| # | Risk description | Platform | Policy reference | Severity |
|---|---|---|---|---|
| C-1 | iOS Pro advertises "Indicator themes" in the listing, on the paywall and in the review notes. The only UI that can change `barTheme` is Android-gated, so an iPhone buyer gets 2 of the 3 features they paid for. | Apple | 2.3.1 (accurate metadata), 3.1.1 (IAP delivers what it sells) | **Critical** |
| C-2 | Support URL **and** Marketing URL `https://honestsignal.froggyeye.com` return 200 serving the **Hostinger default parking page** ("All you have to do now is upload your website files"). Same URL goes into Play's store-listing website field. | Both | Apple 1.5 (support URL must provide support); Play Store Listing | **Critical** |
| H-1 | Paywall copy claims two more things that are untrue on iOS: intervals "as rarely as once an hour" (background interval — Android only) and "set your own daily data budget" (free on both tiers). The second directly contradicts both store descriptions. | Apple | 2.3.1 | High |
| H-2 | Play's Foreground service permissions declaration requires a link to a video of the feature working. No recording exists. | Google | Play Foreground Service policy | High |
| H-3 | The only release artifact in the tree is **debug-signed** (`CN=Android Debug`). No `upload-keystore.jks`, no `key.properties`. | Google | Play upload requirement | High |
| H-4 | Privacy-policy URL serves raw Markdown as `text/plain`. See the ruling in §"Privacy-policy URL — ruling". | Both | Apple 5.1.1(i); Play Data safety | High |
| M-1 | ASC's IAP review screenshot (`05_pro`) can only be captured on Android, where the paywall renders the Android-only "Floating indicator" bullet. Uploading it shows Apple a feature the iPhone build lacks. | Apple | 2.3.1 / 3.1.1 | Medium |
| M-2 | No 512×512 Play icon exists, and **no screenshots exist at all** — `store_assets/screenshots/raw/` holds only `.gitkeep`, there is no `out/`, and neither fastlane screenshot directory exists. | Both | Play listing assets; Apple 2.3.3 | Medium |
| M-3 | `FOREGROUND_SERVICE_SPECIAL_USE` is reviewed manually and Play prefers a narrower type. The "why not dataSync" rebuttal is correct but incomplete. | Google | Play Foreground Service policy | Medium |
| L-1 | `data_safety_answers.md` preamble states `backup_rules.xml` and `data_extraction_rules.xml` both exist. Only the latter does. | Google | — (accuracy) | Low |
| L-2 | `docs/ASO.md` §9 handoff table reports both titles as "(28)". They are 30 — exactly at the cap. §2 of the same file has it right. | Both | — (accuracy) | Low |
| L-3 | Paywall carries no privacy-policy link. Not required for a non-consumable (3.1.2(c) binds auto-renewing subscriptions only); Settings has one. | Apple | 3.1.2(c) n/a | Low |

---

## REQUIRED FIXES (must close before submission)

### C-1 — iOS Pro sells a feature the iOS build does not have

**Problem.** `lib/features/settings/presentation/settings_screen.dart` puts the
indicator section — including `_ThemePicker` — inside a single
`if (Platform.isAndroid) ...[ … ]` block (lines 30–62). `_ThemePicker` is the
**only** writer of `barTheme` anywhere in `lib/`, so on iPhone the value is
permanently `BarTheme.bars` and a Pro purchase changes nothing about it. The mark
itself *is* themed on iOS — `home_screen.dart:90` passes `settings.barTheme` into
`SignalBars` — so the capability exists and only the control is missing.

It is advertised in three places, and the third is the one that hurts:

- `ios/fastlane/metadata/en-GB/description.txt:37` — `• Indicator themes: bars, dots or wave`
- `lib/features/purchases/presentation/paywall_screen.dart:94-98` — `Indicator themes` / `Bars, dots or wave — in the app and in the status bar` (not platform-gated, unlike the "Floating indicator" bullet immediately above it, which is)
- `ios/fastlane/metadata/review_information/notes.txt:33` — tells App Review that Pro on iPhone unlocks "indicator themes (bars, dots, wave)"

We are handing the reviewer a test script that points at the defect. A 3.1.1 pass
on a £2.99 unlock with three named features is exactly the check a reviewer runs.

**Fix — preferred (code, small).** Move `_ThemePicker` out of the
`Platform.isAndroid` block so it renders on both platforms, and make its subtitle
platform-aware ("in the app and in the status bar" on Android, "in the app" on
iOS). `barTheme` already flows to the iOS home screen, so nothing else changes.
Then fix the paywall bullet's wording the same way.

**Fix — alternative (metadata + code).** Delete the themes bullet from
`description.txt`, from `notes.txt`, and platform-gate the paywall bullet behind
`Platform.isAndroid`. This still needs a rebuild, and it leaves iOS Pro at two
features for £2.99, which is a weaker product. Prefer the first.

**Owner:** flutter-architect (paywall + settings), release-manager (description
and notes if the alternative is taken). **Platform:** Apple.

### C-2 — the support URL serves a hosting parking page

**Problem.** `ios/fastlane/metadata/en-GB/support_url.txt` and
`marketing_url.txt` both hold `https://honestsignal.froggyeye.com`. It returns
**200**, which is why stage 5 and the conductor's note both recorded it as live —
but the body is Hostinger's default page:

> Default page — You Are All Set to Go! All you have to do now is upload your
> website files and start your journey. How can I migrate a website to
> Hostinger? How to install WordPress using Auto Installer?

`PIPELINE.md` records this as "placeholder acceptable for review". It is not.
Apple 1.5 requires the support URL to provide support information, and a page
whose visible content is another company's onboarding instructions is a textbook
1.5 rejection — worse than a dead link, because the reviewer reads it and sees an
unfinished product. The same URL is typed by hand into Play's store-listing
website field.

For contrast, `https://luckynumbers.froggyeye.com` serves a real app page; the
two resolve to different IPs, so the subdomain exists but the docroot is empty.

**Fix, either of:**

1. **Bring stage 8 forward** and deploy the promo page to
   `honestsignal.froggyeye.com` before the build is submitted. This is the right
   answer — the page is needed anyway, and `AppConstants.supportUrl` already
   points there.
2. **Fall back to `https://froggyeye.com`** (verified 200, real studio site) in
   `support_url.txt` and `marketing_url.txt`. This is metadata-only and needs no
   rebuild: `AppConstants.supportUrl` has **no consumer anywhere in `lib/`** — it
   is declared and pinned by `test/release_invariants_test.dart:43` and never
   read by the app — so the binary is unaffected either way.

Do **not** submit against the parking page. **Owner:** conductor (option 1) or
release-manager (option 2). **Platform:** both.

### H-1 — two more inaccurate paywall claims on iOS

**Problem.** `paywall_screen.dart:88-93`, "Your own sampling rate":

> Measure as often as every 2 seconds, or as rarely as once an hour, and set your
> own daily data budget.

- *"as rarely as once an hour"* describes `backgroundIntervalSeconds`
  (`maxBackgroundInterval = 3600`). iOS has no background measurement, and the
  background interval tile in Settings is itself Android-gated. On iPhone the Pro
  range is 2–60 **seconds**.
- *"set your own daily data budget"* is **not a Pro feature on either platform**.
  `AppSettings.clampedForTier` (`app_settings.dart:75-83`) clamps
  `foregroundIntervalSeconds`, `backgroundIntervalSeconds`, `barTheme` and
  `overlayEnabled` — it does not touch `dailyBudgetMb`, and `_BudgetTile` in
  Settings takes no `isPro`. Both store descriptions say so out loud: "adjustable
  from 5 to 250 MB **on every tier**".

So the listing and the paywall contradict each other on the free/paid line. A
listing that contradicts itself is what 2.3.1 acts on, and it reads as a dark
pattern besides — which is off-brand for a studio whose tagline is "no dark
patterns".

**Fix.** Reword to "Measure as often as every 2 seconds" on iOS and "…, or as
rarely as once an hour in the background" on Android; drop the data-budget clause
entirely. **Owner:** flutter-architect. **Platform:** Apple (primary), Google
(the budget clause is wrong on Android too).

### H-2 — the Play foreground-service declaration video

Unchanged from `data_safety_answers.md` §9.1 and still the single most likely
thing to stall Play. Needs a screen recording of the status-bar indicator
updating with the app closed, hosted durably (unlisted YouTube). It cannot be
shot convincingly on an emulator and it cannot be shot at all until a signed
build is on a real device — so it is downstream of H-3. **Owner:** conductor /
store-publisher. **Platform:** Google.

### H-3 — the release artifact is debug-signed

Verified rather than inferred: `apksigner verify --print-certs` on
`build/app/outputs/flutter-apk/app-release.apk` reports

```
Signer #1 certificate DN: C=US, O=Android, CN=Android Debug
```

`android/upload-keystore.jks` and `android/key.properties` do not exist, and
`build.gradle.kts` falls back to the debug config when they are absent (lines
52–55), so the build succeeds and looks clean. Generate both per house-facts #7.
**Owner:** conductor / store-publisher. **Platform:** Google.

### H-4 — privacy-policy URL

See the ruling below. **Owner:** flutter-architect + conductor.

---

## Privacy-policy URL — ruling (the open question from stage 5)

**Ruling: switch to a rendered HTML page before the submission build. Not
acceptable as-is.**

The measured facts, not the convention:

| Check | Result |
|---|---|
| `https://raw.githubusercontent.com/mksoft-ltd/honest_signal/refs/heads/main/PRIVACY_POLICY.md` | **200**, `content-type: text/plain; charset=utf-8`, `x-content-type-options: nosniff`, 3,674 bytes |
| `https://mksoft-ltd.github.io/honest_signal/privacy_policy.html` | **404** |
| `gh api repos/mksoft-ltd/honest_signal` | public, `has_pages: false`, no `privacy_policy.html` in the tree |
| In-app consumer | `settings_screen.dart:148` opens it via `url_launcher` — the link is real, not just a declared constant |

Taken on its own this is a *soft* risk, and I want to be honest about that: with
`nosniff` and `text/plain` the page displays inline rather than downloading, it is
legible, its content is genuinely adequate for 5.1.1 (it names the publisher, the
contact, what is stored, the 25-hour retention, the four probe endpoints and the
IP-visibility caveat), and house-facts #5 records the pattern as already blessed
across the portfolio. On its own I would have rated it Medium and passed it with a
recommendation.

What makes it a required fix here is that **a code round is already mandatory**.
C-1 and H-1 both change compiled Dart, so a rebuild is happening regardless. The
marginal cost of also changing one constant and one test assertion is close to
zero, and it retires a recurring portfolio risk permanently. Deferring it means
carrying the risk into review to save work that is being done anyway.

**Do this:**

1. Add `privacy_policy.html` (rendered from `PRIVACY_POLICY.md`, keeping the two
   in sync) to the repo root and **enable GitHub Pages** — `has_pages` is `false`,
   and enabling it is a separate step that is easy to skip after a successful
   push. This has bitten the portfolio before (ByeByeJob: HTML pushed, Pages never
   enabled, the URL in the binary 404'd while the old raw URL served a stale
   policy).
2. Point `AppConstants.privacyPolicyUrl` at
   `https://mksoft-ltd.github.io/honest_signal/privacy_policy.html`, update the
   assertion in `test/release_invariants_test.dart:35`, and update
   `ios/fastlane/metadata/en-GB/privacy_url.txt` and
   `android/fastlane/data_safety_answers.md` §1 in the same change.
3. **Curl the new URL and confirm 200 with `content-type: text/html` before the
   submission build is cut**, by extracting the string from the constant and
   fetching *that* — not by fetching a URL typed into a message. The two drifting
   apart is the failure this check exists to catch.

The froggyeye.com route (`honestsignal.froggyeye.com/privacy`) is equally good and
would fold into the C-2 fix, but it couples the binary to stage 8's timing.
GitHub Pages is independent of stage 8 and can be verified today; prefer it.

Keep the raw `.md` URL working. Do not delete `PRIVACY_POLICY.md`.

---

## Assessments the conductor asked for

### Android — does `specialUse` survive Play policy review?

**Probably, at Medium risk, after at least one round of correspondence.** The
rebuttal in `data_safety_answers.md` §6 is factually right and unusually strong:
from Android 15 a `dataSync` foreground service is capped at 6 hours per rolling
24, and a connection indicator that dies silently part-way through each day is
worse than no indicator, because the user cannot distinguish "the indicator
stopped" from "the connection is fine". No other declared FGS type describes
continuous user-requested network measurement. That argument should be filed
verbatim.

Three things strengthen it, and none are currently in the declaration text:

1. **The service and the user-visible feature are literally the same object.**
   The notification's small icon *is* the score — there is no hidden work. Say
   this first; it is the criterion Play weighs hardest.
2. **It is user-initiated and user-terminable.** The Settings toggle stops the
   service; the notification is `IMPORTANCE_LOW`, silent and ongoing. The
   declaration should say the user can end it at any time from inside the app.
3. **Pre-empt the WorkManager counter-argument.** The likeliest reviewer response
   is not "use dataSync" but "use a periodic job to update a plain notification".
   The answer is that WorkManager's minimum period is 15 minutes and its
   execution is deferrable by Doze and by app-standby buckets, so the displayed
   score would be of unknown and unbounded age — which for an app whose entire
   product claim is that the number is honest is not a degraded feature but a
   false one. §6 gestures at this ("cannot be deferred to a background job"); make
   it explicit, with the 15-minute figure.

The manifest subtype string, the declaration text and the notification behaviour
were all verified in the merged release manifest and the Kotlin — they match what
§6 says will be filed.

### Android — `SYSTEM_ALERT_WINDOW`

**Low risk.** Play has no console declaration form for it, and the implementation
matches the justification at every point I could check in code: Pro-gated and
`overlayEnabled: false` in `clampedForTier`; off by default in `AppSettings`;
requested only from `/settings/overlay` after an explainer; blocked unless the
status-bar indicator is on; `FLAG_NOT_FOCUSABLE`; re-checks
`Settings.canDrawOverlays` on every start and on every resume. `BootReceiver`
correctly does **not** start `OverlayService` (a boot receiver may not start a
plain background service on Android 8+) and says so in a comment; the bubble is
restored from inside `HonestSignalService`, which is itself foreground, so the
`startService` call there is legal. Nothing to fix.

### Android — `POST_NOTIFICATIONS`, boot receiver, persistent notification UX

**Pass.** One runtime permission, requested from onboarding with the explanation
already on screen and an explicit "You can say no and still use the app". One
ongoing `IMPORTANCE_LOW` notification and no other. `RECEIVE_BOOT_COMPLETED`
restores only what the user had enabled. `notificationIndicatorEnabled` defaults
`true`, which is correct here — it is the advertised headline feature, it is free,
and it is one toggle away in Settings.

### iOS — 2.5.4 and 4.2 exposure

**2.5.4 is not engaged at all.** No `UIBackgroundModes` key in
`ios/Runner/Info.plist` and none in the built `Runner.app/Info.plist`. The app
declares no background mode and uses none.

**4.2 (minimum functionality) is Low risk, and the description is what makes it
low.** The iOS free tier is not thin: live measurement on a 5 s cadence, five real
metrics (latency, jitter, loss, throughput, transport), a verdict, a freshness
line, a live data-budget counter, and the complete scoring method published
in-app. Pro adds history charts. That is native, substantive, and nothing like a
web wrapper.

The real iOS risk was never 4.2 — it is a reviewer opening the app after
backgrounding it, seeing a stale number, and filing it as broken. Two things
already defend against that and **must not be edited away**: the in-app freshness
copy that states outright past ~2 minutes that iOS stops apps measuring in the
background and offers pull-to-refresh, and the "HONEST ABOUT ITS LIMITS" section
of the App Store description that says the same thing before the reviewer
downloads. The review notes also flag it under "ONE THING THAT MIGHT LOOK LIKE AN
ISSUE BUT IS NOT". That is the correct treatment and it is well executed.

The Android indicator's absence from iOS is not a 4.2 problem. It is only a
problem where iOS metadata sells Android behaviour — which is C-1 and H-1.

### Data safety / privacy label — do I agree with SEC-5's stage-6 note?

**Yes, "No data collected" holds on both stores, and the answer sheet says the
right things.** I checked the reasoning rather than inheriting it.

- The four probe endpoints in `probe_targets.dart` are the ones the policy and
  the sheet name, all HTTPS, cache-buster the only added parameter. The endpoint
  operator seeing the originating IP is true of any web request and is not data
  the app collects or receives; `PRIVACY_POLICY.md:40-45` discloses it explicitly
  rather than glossing it.
- Play Billing's `com.google.android.datatransport` CCT backend is in the merged
  manifest exactly as SEC-5 described — `TransportBackendDiscovery`,
  `JobInfoSchedulerService`, `AlarmManagerSchedulerBroadcastReceiver`, all
  `exported="false"` — and Play Billing **8.0.0** is confirmed in the dex. This is
  Google Play's own client reporting Play Billing events to Google, inside Play's
  own carve-out for data it collects to process a purchase. It is not the app
  collecting anything, and it cannot be excluded without breaking billing. The
  sheet's warning that a plain hostname grep returns zero hits (the endpoint is
  stored character-interleaved) is worth keeping — it stops the next reader
  concluding R8 stripped it.
- `pubspec.yaml` was checked rather than assumed, per the pipeline brief: nine
  direct dependencies, **no analytics, attribution, ad or crash-reporting SDK**,
  no `google_mobile_ads`. The merged manifest holds no `AD_ID` permission. The
  portfolio's analytics-free, local-first claim is true of this app.
- `PurchaseController.init()` does contact the store at every cold start
  (`isAvailable`, `queryProductDetails`, `restorePurchases`). No store text
  implies otherwise; the iOS review notes disclose it outright, which is the right
  call.

Apple's `app_privacy_details.json` (`DATA_NOT_COLLECTED`) is correct on the same
reasoning — StoreKit is Apple's own SDK.

### Metadata accuracy vs the binary

Every load-bearing claim was checked against code or the merged manifest, not
against the spec.

| Claim | Where | Verdict |
|---|---|---|
| Status-bar indicator is free | Play description | **True** — `clampedForTier` does not touch `notificationIndicatorEnabled` |
| Indicator keeps updating with the app closed | Play description | **True** — `specialUse` FGS hosting a background Flutter engine |
| Returns by itself after a restart | Play description | **True** — `BootReceiver`, gated on what the user had enabled |
| Pro intervals 2–60 s on screen, 1–60 min in background | Play description | **True** — 2/60 s and 60/3600 s constants |
| Budget 5–250 MB "on every tier" | both descriptions | **True** — and it is what H-1 contradicts |
| Excluded from cloud backup and device-to-device transfer | Play description | **True** — `allowBackup="false"` plus four excludes incl. `domain="root"` |
| Restore from paywall or Settings | both descriptions | **True** — plus a silent restore in `init()` |
| Transfer-failure cap at 2 bars | both descriptions | **True** — `PRODUCT_SPEC` §5 and `scoring.dart` |
| Titles exactly 30 chars | both | **True** — 30/30 both stores, re-counted in Python (`len`), not `wc -c` |
| No status-bar / overlay / floating / bubble / background / widget wording in iOS text | iOS | **True** — zero occurrences |
| No iOS background-measurement claim | iOS | **True** — the description states the limitation outright |
| No `TrueSignal` (unspaced), no "bars lie", no "best/fastest/#1/guaranteed" | both | **True** — clean across all metadata |
| **Indicator themes on iOS** | iOS description, notes, paywall | **FALSE — C-1** |

All twelve length-capped fields re-measured in Python: iOS name 30/30, subtitle
30/30, keywords 97/100, promotional 167/170, description 3981/4000, release notes
226/4000, review notes 3983/4000; Play title 30/30, short 70/80, full 3972/4000,
changelogs 444/500. Nothing over. The three at exactly 30 must not be edited
without a re-count.

### Screenshot plan vs metadata claims

`integration_test/screenshots_test.dart` captures six shots and its header states
plainly that capture is **Android-only** (`convertFlutterSurfaceToImage` is
Android-only; the iOS simulator hands `takeScreenshot` the launch-screen layer
while the assertions still pass). Consequences:

- The App Store set is framed Android captures. For four of the five that is
  invisible — the screens are pure Flutter and identical. The Play-only
  `03_settings` shot is already correctly excluded from the iOS set by `ASO.md`
  §4, which is the shot that would have exposed it.
- **`05_pro` is the exception and it is M-1.** It is ASC's IAP review screenshot,
  and captured on Android the paywall renders the `Platform.isAndroid` "Floating
  indicator" bullet — advertising to Apple's reviewer, on the IAP's own review
  artifact, a feature the iPhone build does not have. Once C-1 is fixed the
  remaining bullets match; until then this shot compounds C-1. Capture it from an
  iOS-shaped run, or hand-frame it, or fix C-1 and re-check the rendered PNG
  before upload.
- The harness's guards are sound and I verified them rather than trusting the
  notes: `ScreenshotMode.isEnabled` is `_flag && !kReleaseMode`, and
  `PurchaseController.debugForcePro()` is wrapped in `assert(() { … }())` so it is
  stripped from release entirely. **There is no IAP bypass in a release binary**,
  and the demo `£2.99` literal cannot reach one. `render.sh` hard-failing on
  `raw/tier.txt != pro` is the right guard.
- **Nothing has been captured yet** — that is M-2, and stage 7 owns it.

---

## Verified clean (recorded so stage 7 does not re-litigate)

Checks that passed, each against the artifact:

- **16 KB page alignment** — required by Play for new apps targeting Android 15+
  since 1 Nov 2025 and mentioned nowhere else in this pipeline. All nine `.so`
  files in the release APK have max `PT_LOAD` `p_align` ≥ 16384 (`libflutter.so`
  and both arm64 payloads at 64 KB). **Pass.**
- **Play Billing 8.0.0** confirmed in the dex and in
  `in_app_purchase_android-0.5.2`. Clears the 31 Aug 2026 deadline.
- **targetSdk 36, minSdk 24** in the merged manifest.
- **Merged release manifest**: `package="com.froggyeye.honestsignal"`,
  `versionCode 1`, `versionName 1.0.0`, exactly the nine permissions the answer
  sheet lists and no others — no location, camera, microphone, contacts, storage,
  media, phone-state, exact-alarm, full-screen-intent, `QUERY_ALL_PACKAGES` or
  `AD_ID`. All four of our components `exported="false"` except `MainActivity`.
- `allowBackup="false"`, `dataExtractionRules` with four excludes under both
  `<cloud-backup>` and `<device-transfer>`, `networkSecurityConfig` with
  `cleartextTrafficPermitted="false"` and system trust anchors. No `http://`
  anywhere in `lib/` or the Kotlin.
- **iOS**: `ITSAppUsesNonExemptEncryption = false` present in source **and** in the
  built `Info.plist` (no "Missing Compliance" stall on upload); no
  `NS*UsageDescription` in the source plist; `MinimumOSVersion 15.0` (clears the
  Spring 2027 floor); `TARGETED_DEVICE_FAMILY = 1` in **all three** build
  configurations; portrait only; app icon 1024×1024 with `hasAlpha: no`.
- **iOS privacy-symbol scan re-run on the renamed build**: zero references to
  `AVCaptureDevice`, `PHPhotoLibrary`, `UIImagePickerController`,
  `CLLocationManager`, `CNContactStore`, `ATTrackingManager`,
  `CTTelephonyNetworkInfo` or `ASIdentifierManager`. No purpose strings required,
  no ATT prompt required, no tracking. (House-facts #17: Apple scans linked
  symbols, so this was checked with `nm` on the binary.)
- **Privacy manifests** — no app-level `PrivacyInfo.xcprivacy` is needed.
  `Flutter.framework`, `connectivity_plus`, `in_app_purchase_storekit` and
  `url_launcher_ios` each ship their own. `path_provider_foundation` resolved to
  **2.6.0**, which is FFI-based and ships no plugin at all; its last
  plugin-based release (2.5.1) declared an empty `NSPrivacyAccessedAPITypes`
  array, so there is no required-reason API to declare. No ITMS-91053 exposure.
- **IAP** — native `in_app_purchase` only, no wrapper (house-facts #9). One
  non-consumable `com.froggyeye.honestsignal.pro`. Price read from the store via
  `queryProductDetails`, never hardcoded in a shipping path. Restore on the
  paywall, in Settings, and silently on launch. `pendingCompletePurchase` is
  acknowledged, so Android cannot auto-refund at three days. No external payment
  SDK anywhere — no Stripe, no PayPal, nothing.
- **Privacy-policy link is genuinely wired**, not merely declared:
  `settings_screen.dart:148` opens `AppConstants.privacyPolicyUrl` through
  `url_launcher`, which is in `pubspec.lock`.
- **No UGC, no accounts, no messaging, no browser or WebView** — the IARC and
  App-Access answers in §4/§5 of the answer sheet are correct, and no reporting,
  blocking or moderation surface is required.
- **Age rating** — 4+ / Everyone with Play target audience "18 and over" is
  coherent, not a conflict; it keeps the app out of the Families programme. The
  icon and content give no child appeal.
- `ios/fastlane/metadata/review_information/` is complete — `first_name`,
  `last_name`, `email_address`, `phone_number`, `demo_account_required`,
  `notes.txt` — which ASC requires before a version can be submitted.

---

## RECOMMENDED IMPROVEMENTS (not blocking)

1. Add the three arguments in "does `specialUse` survive" above to the Play
   declaration text before filing it.
2. Correct `data_safety_answers.md`'s preamble: `backup_rules.xml` does not
   exist. Only `data_extraction_rules.xml` does, and with `allowBackup="false"`
   the legacy file is moot — but a sheet that names a file Play could ask about is
   worth being right.
3. Correct `docs/ASO.md` §9's "(28)" to 30 for both titles, so nobody later
   "uses the spare characters" that do not exist.
4. Consider a privacy-policy link on the paywall. Not required for a
   non-consumable, but App Review does tap it on a 3.1.1 pass and it costs one
   `TextButton`.
5. `PRIVACY_POLICY.md` is dated **7 August 2026** and predates the rename; its
   body is already correct under the new name. Refresh the date with the HTML
   variant in the H-4 fix.

---

## FINAL SUBMISSION CHECKLIST

Stage 5's list was sound; items marked **[new]** are additions from this audit.

**Blocking — a binary cannot be submitted until these are done**

- [ ] **[new]** C-1: iOS can change the indicator theme, or the claim is removed
      from the description, the review notes and the paywall — then rebuild
- [ ] **[new]** C-2: `honestsignal.froggyeye.com` serves a real page, **or**
      `support_url.txt` + `marketing_url.txt` fall back to `https://froggyeye.com`
- [ ] **[new]** H-1: paywall interval/budget copy corrected on both platforms
- [ ] H-4: `privacy_policy.html` pushed, **GitHub Pages enabled**, URL curled 200
      as `text/html`, constant + `release_invariants_test.dart` + both metadata
      files updated, binary rebuilt
- [ ] H-3: `android/upload-keystore.jks` + `key.properties` generated
      (house-facts #7); re-run `apksigner verify --print-certs` and confirm the
      signer is **not** `CN=Android Debug`
- [ ] **[new]** Re-run `flutter analyze` + the full suite after the code round
      (271/271 at the last green run) and rebuild both platforms from clean

**Blocking for Play only**

- [ ] H-2: FGS demo video recorded on a real device, hosted durably, link filed
- [ ] Foreground service permissions declaration filed with the §6 text plus the
      three additions above
- [ ] IAP `com.froggyeye.honestsignal.pro` created — needs a billing artifact
      **active in a track** first; feed `convertRegionPrices` **£2.4917** ex-VAT,
      not £2.99 (house-facts #18)
- [ ] Data safety, App content, IARC and target-audience forms filed per
      `data_safety_answers.md`; **do not** file any declaration in §8
- [ ] `GET /edits/<id>/listings` before writing release notes — en-GB only
      (house-facts #19)

**Blocking for the App Store only**

- [ ] IAP created in ASC, GBP base £2.99, price schedule previewed before saving
- [ ] Privacy nutrition label answered **and Published** by the founder
      (`DATA_NOT_COLLECTED`); publishing it does not submit anything
- [ ] IAP added for review **from the IAP's own page** ("Add for Review" → the
      existing Draft submission), then verify the submission shows **2 items**
      before submitting (house-facts #15 — this stranded lucky_numbers)
- [ ] Uploading `name.txt` renames the record to the 30-char title; a `deliver`
      failure there is a **name collision**, not a formatting error

**Assets — blocking for both**

- [ ] **[new]** Screenshots captured from the **renamed, post-C-1** binary at
      `SCREENSHOT_TIER` pro (`raw/` is empty; design deleted the old captures
      deliberately because they showed "True Signal")
- [ ] **[new]** Open **every** rendered PNG before upload — confirm none is a
      "CAPTURE MISSING" card, none shows the old name, and none shows a failure
      state
- [ ] **[new]** `05_pro` (ASC IAP review screenshot) checked for Android-only
      paywall bullets — see M-1
- [ ] `03_settings` (status bar) appears in the **Play set only**
- [ ] **[new]** 512×512 Play icon generated — it does not exist; the 1024
      masters do, so it looks complete in `ls`
- [ ] Feature graphic 1024×500 — **present and correct**
- [ ] fastlane image directories created: `ios/fastlane/screenshots/en-GB/` and
      `android/fastlane/metadata/android/en-GB/images/{phoneScreenshots,featureGraphic.png,icon.png}`
      — none exists yet

**Sanity**

- [ ] Version/build numbers derived from **both** stores' live state, not from
      `pubspec.yaml` (house-facts #20 — nothing is live, so 1.0.0+1 stands, but
      re-confirm at upload)
- [ ] A failed iOS upload never becomes a `builds` resource — poll ~20 min, then
      look at TestFlight → Build Uploads (house-facts #16)

---

Blocking findings, verbatim, for the pipeline gate:

- **C-1** — iOS Pro advertises "Indicator themes" in the App Store description,
  on the paywall and in the App Review notes, but `_ThemePicker` — the only
  writer of `barTheme` — is inside `if (Platform.isAndroid)` in
  `settings_screen.dart`, so an iPhone buyer cannot change it. Apple 2.3.1 / 3.1.1.
- **C-2** — the Support URL and Marketing URL `https://honestsignal.froggyeye.com`
  return 200 serving Hostinger's default parking page ("All you have to do now is
  upload your website files"), not a support page. Apple 1.5.


---

# Re-verification — 2026-08-09 (same auditor)

flutter-architect fixed C-1, H-1 and H-4; stage 8 incidentally closed C-2. Every
finding below was re-checked by **executing code and fetching live URLs**, not by
reading the fix notes. Both regression tests were confirmed to *bite* by
reintroducing each defect myself and watching them fail, then restoring the tree
(`md5` on both touched files matches the pre-test backup byte for byte).

Gates re-run by me, not quoted: `flutter analyze` **No issues found** ·
`flutter test` **273/273, 0 skipped**.

## C-1 — RESOLVED

`_ThemePicker` now sits outside the `Platform.isAndroid` block; the `Indicator`
section header renders on both platforms with only the two Android-only tiles
gated inside it. The subtitle is platform-true ("— in the app and in the status
bar" on Android, "— in the app" on iOS). The control is genuinely functional on
iOS, not merely present: `locked: !isPro && !barTheme.isFree` keeps free users on
`bars` and routes a locked tap to the paywall, and `onChanged` writes `barTheme`
through the real settings controller.

**Their regression test was checked rather than trusted.** Re-gating
`_ThemePicker` inside the Android block reproduces the original defect exactly:

```
Expected: exactly one matching candidate
  Actual: _TextWidgetFinder:<Found 0 widgets with text "Indicator style": []>
```

Restored afterwards; file `md5 06402cf76d7fc93121ab012f90b51f60`, unchanged from
before the experiment. Their observation about *why* the test is meaningful is
correct and worth keeping: widget tests run on the host with
`Platform.isAndroid == false`, which is the same branch an iPhone takes, so this
is a real test of the failing path rather than a proxy for it.

## H-1 — RESOLVED

Both bullets are now platform-specific, and the numbers were checked against the
constants rather than against the prose: the iOS body ("every 2 seconds while the
app is open, instead of the standard 5") matches `minForegroundInterval = 2` and
`defaultForegroundInterval = 5`; the Android body ("once a minute to once an
hour") matches `minBackgroundInterval = 60` and `maxBackgroundInterval = 3600`
seconds. Deleting the data-budget claim outright was the right call over
rewording — `clampedForTier` never touches `dailyBudgetMb`, so it is free on both
tiers and both listings already say "on every tier".

Test bites — restoring the old body produces:

```
Expected: no matching candidates
  Actual: Found 1 widget with text containing daily data budget
```

Restored; file `md5 e2c6acb557de6007feab63a881baad46`.

## H-4 — RESOLVED, and the fix note's caveat is **stale**

All four copies of the URL agree (`AppConstants`, `release_invariants_test.dart`,
`ios/fastlane/metadata/en-GB/privacy_url.txt`, `data_safety_answers.md` §1). The
URL was **extracted from the constant and that string fetched**, per the house
rule: **200, `content-type: text/html; charset=utf-8`**. No
`raw.githubusercontent` reference survives anywhere in `lib/`, `test/` or either
fastlane tree — the only remaining hit is the dated stage-4b audit's historical
record, which is correct to leave alone. The `endsWith('.html')` assertion is a
good addition.

**Correction to the hand-off note:** it says the improved rendering "is **not
pushed**, so `mksoft-ltd.github.io` still returns the old version". That is no
longer true — it appears to have landed between their check and mine. Commit
`70e696c` ("Proper HTML rendering for the privacy policy") is on `main`, `main` is
in sync with `origin/main`, and **the live page is byte-identical to the local
file**: 4,547 bytes, 15 `<p>`, 8 `<h2>`, 3 `<ul>`, 9 `<li>`, 10 `<strong>`,
`last-modified: Sun, 09 Aug 2026 02:11:52 GMT`. The page also carries
`<meta name="viewport">`, `charset`, a `<title>` and readable inline styling, so
it renders properly on a reviewer's phone. Nothing further is needed here, and no
push decision is outstanding. `ios/fastlane/`, `android/fastlane/`, `scripts/`
and this report remain untracked and therefore still private — that part of their
caution stands.

## C-2 — RESOLVED by stage 8, not by this fix round

`https://honestsignal.froggyeye.com` no longer serves Hostinger's parking page. It
now returns a real Honest Signal promo page — the premise, the method, the metric
list, the scale, pricing and an FAQ, with a "See all our apps" link back to the
studio. That satisfies Apple 1.5.

I read the body rather than the status code, and the page is careful in exactly
the way the listing is: every Android-only capability is qualified in place ("On
Android the result lives in your status bar…"), and the FAQ answers "Does the
status-bar indicator work on iPhone? **No.**" and states the iOS
measure-while-closed limitation outright. Its Pro list names "Indicator themes:
bars, dots, wave" without a platform qualifier — which is now **correct on both
platforms precisely because C-1 was fixed**. Had C-1 been closed the other way
(by deleting the claim), this page would have contradicted the App Store listing.

One cosmetic note, not a finding: the scrolling feature-chip strip lists
"Status-bar indicator" and "Floating bubble" unqualified among otherwise
cross-platform chips. The surrounding prose and the FAQ qualify both
unambiguously, and the marketing URL is not the surface 2.3.1 acts on.

## Methodological note for stage 7 — do NOT read the APK as evidence about iOS

I nearly filed a false regression here, so it is worth writing down. Grepping the
release APK for the new strings gives a misleading result:

| String | ASCII grep | Truth |
|---|---|---|
| `Indicator style` | 1 hit | present |
| `Bars, dots or wave — in the app and in the status bar.` | **0 hits** | **present** — 1 hit as UTF-16LE |
| `Bars, dots or wave — in the app.` (iOS branch) | 0 hits | **correctly absent** from an Android build |

Two independent mechanisms, both easy to mistake for a broken build:

1. **Any literal containing a non-Latin-1 character is stored as a Dart
   `TwoByteString`** — every character in two bytes — so an ASCII byte grep
   cannot match it. The em-dash in the theme subtitles is enough to do this.
   Searching the UTF-16LE encoding finds the Android variant immediately. The
   same trap hides `'On — a small bubble is drawn over other apps.'` and every
   other em-dashed literal in this app, which is most of the UI copy.
2. **`Platform.isAndroid` is annotated `@pragma("vm:platform-const")`** in this
   Flutter SDK (`sky_engine/lib/io/platform.dart`), so AOT folds the ternary and
   tree-shakes the dead branch. The iOS strings are *supposed* to be missing from
   `libapp.so`.

Consequence: **the Android artifact can never verify an iOS-branch fix**, and the
absence of an iOS string in the APK is not a finding. The load-bearing evidence
for the iOS path is the widget suite, which runs with `Platform.isAndroid ==
false`. Verify iOS-branch copy there, or against an iOS build — never against the
APK.

## What remains open, and why it no longer blocks this gate

Every defect in **code and metadata** is closed. What is left is work stage 7
performs as part of its own job, and holding the gate shut would deadlock the
items that only stage 7 can produce:

- **H-2** (Play FGS demo video) — needs a signed build running on a real device,
  so it is downstream of H-3 and cannot be done before stage 7.
- **H-3** (upload keystore) — generating it *is* a publish step. I checked the
  hazard this creates in a now-public repo: `android/.gitignore` already excludes
  `key.properties`, `**/*.keystore` and `**/*.jks`, confirmed with
  `git check-ignore -v` against real files, so generating them in place is safe.
- **M-1** (`05_pro` IAP review screenshot vs Android-only paywall bullets),
  **M-2** (512×512 Play icon, and no screenshots captured at all), **M-3**
  (`specialUse` declaration wording) — all stage-7 artefacts.
- **L-1 / L-2 / L-3** — accuracy nits, unchanged.

These are carried as **gate conditions on stage 7** in the checklist above rather
than as a failed compliance verdict. Nothing may be submitted until they close.

Verdict: PASS
