# True Signal — Security Audit

Stage 4b artifact. Written by mobile-security-auditor, 2026-08-08.
Scope: full repo at `/Users/kevinlam/projects/true_signal` — Dart measurement
and purchase layers, Android native surface (foreground service, background
Flutter engine, overlay, boot receiver, platform channels), iOS configuration,
local storage, build configuration, and the release APK as built.

Findings are verified against the **built artifact** wherever the source alone
could not settle the question: the release merged manifest, the release
`classes.dex`, and the arm64 Dart AOT snapshot. One finding (SEC-1) was
confirmed by executing the code against a local server rather than by reading
it.

---

## SECURITY RISK LEVEL

**Overall assessment: Low.**

No Critical and no High findings. This is a local-first utility with no
accounts, no backend, no credentials, no PII and no analytics, and the audit
confirmed all of that against the binary rather than taking the spec's word for
it. The three Medium findings are a data-integrity bug in the probe layer, the
Android backup default, and the house-standard unverified IAP flag.

| Severity | Count |
|---|---|
| Critical | 0 |
| High | 0 |
| Medium | 3 |
| Low | 3 |

---

## VULNERABILITIES FOUND

### SEC-1 — The throughput sample reads an unbounded response body

- **Severity:** Medium
- **Affected component:** `HttpProbeClient.transfer`
- **Location:** `lib/features/measurement/data/probe_client.dart:100-124`
  (specifically the read loop at `:108-110`)

`transfer()` requests a known number of bytes (`?bytes=120000`) but never
enforces that number, or any other, on the response it reads:

```dart
await for (final chunk in streamed.stream.timeout(timeout)) {
  received += chunk.length;
}
```

`Stream.timeout` is an **inter-event** timeout — it fires only when no chunk
arrives for the given duration. A response that keeps sending therefore never
trips it, and `received` has no ceiling. There is no wall-clock deadline on the
transfer as a whole and no cap on bytes accepted.

**This was measured, not inferred.** Running the real `HttpProbeClient` against
a local server that sends 200 KB every 900 ms:

```
TRANSFER ok=true bytes=3072000 requested=120000 elapsedWall=13643ms timeoutWas=8000ms
```

3,072,000 bytes accepted against a 120,000-byte request — **25.6× the size
asked for, over 13.6 s against an 8 s timeout** — and returned as a successful
sample. The server stopped voluntarily; nothing in the client would have.

The sibling method is correct, which is what makes this a bug rather than a
design choice. `probe()` applies `.timeout()` to the *Future* returned by
`fold`, which is a total deadline, and the same server produced:

```
PROBE ok=false bytes=700 elapsedWall=2012ms timeoutWas=2000ms
```

Bounded at 2,012 ms, charged only its 700-byte overhead. The two methods differ
by where `.timeout` is applied, and only one of them is safe.

Two consequences follow:

1. **The daily data budget is not a hard stop within a cycle.** The budget is
   read *before* a cycle and charged *after* it (`measurement_controller.dart:125`
   and `:150-156`; `background_host.dart:85` and `:102-108`), so it bounds how
   many cycles run, never how much one cycle spends. PRODUCT_SPEC §6 calls the
   budget "a hard stop, not a guideline" and the home screen shows a counter
   against it. On Android this runs inside an all-day foreground service, on
   whatever connection the user is paying for.
2. **The reported score becomes whatever the responder wants.** `_toKbps`
   (`measurement_engine.dart:170-174`) divides the received byte count by
   elapsed time, so a fast-streaming responder yields an arbitrarily high
   throughput and 5 bars; a slow drip yields the opposite. For an app whose
   entire proposition is "the number is honest", the number is only as honest
   as the endpoint.

The existing test `release_invariants_test.dart:58-65` asserts the transfer
endpoint is *asked* for exactly the budgeted bytes. Nothing asserts anything
about what comes back. The guarantee is tested on the request side only.

### SEC-2 — Android backup is on by default, sweeping up the entitlement flag and history

- **Severity:** Medium
- **Affected component:** `AndroidManifest.xml` `<application>`
- **Location:** `android/app/src/main/AndroidManifest.xml:33-36`

The `<application>` tag sets no `android:allowBackup`, no
`android:dataExtractionRules` and no `android:fullBackupContent`. Confirmed
against the **release merged manifest**
(`build/app/intermediates/packaged_manifests/release/.../AndroidManifest.xml`):
none of the three attributes appears anywhere, so `allowBackup` takes its
default of **true** and no rules file constrains it.

Everything the app stores is therefore in scope for Google Drive Auto Backup and
for Android 12+ device-to-device transfer:

| Store | Path domain | Contents |
|---|---|---|
| Hive `settings` box | `root` (`app_flutter/`) | `pro_unlocked` flag, all settings, budget mirror |
| Hive `history` box | `root` (`app_flutter/`) | 25 h of connectivity samples |
| `true_signal_budget` | `sharedpref` | the day's spent-byte counter |
| `true_signal_service`, `true_signal_overlay` | `sharedpref` | indicator/overlay state, bubble position |

Note that the Hive boxes sit in `<dataDir>/app_flutter/`, which is the **`root`**
domain — not `file`. A rules file that only excludes `domain="file"` would miss
them entirely.

Two distinct effects. First, the Pro entitlement rides a backup to a new device
(compounding SEC-3, since nothing ever re-verifies or downgrades the flag).
Second, the sample history — a 25-hour log of when the user was on cellular
versus Wi-Fi and how good each connection was — leaves the device for Google's
backup servers.

This also puts pressure on `PRIVACY_POLICY.md:26-27`: *"Uninstalling the app
removes all of it. None of it is backed up to us, because there is no 'us' to
back it up to."* The sentence is literally true — Froggy Eye receives nothing —
but it closes a paragraph listing the measurements, settings and Pro flag, and a
reader takes it to mean the data is not backed up at all. It currently is.

### SEC-3 — Pro entitlement is an unverified local boolean that never downgrades

- **Severity:** Medium
- **Affected component:** `SettingsRepository` / `PurchaseController`
- **Location:** `lib/features/settings/data/settings_repository.dart:40-42`,
  `lib/features/purchases/data/purchase_controller.dart:110-141`

The entitlement is a plain `bool` under the `pro_unlocked` key in the Hive
settings box. It is set true on any `purchased` or `restored` event for the
product ID, with no inspection of `purchase.verificationData`, and there is no
path that ever writes false. Anyone with root, an emulator, or a rooted-device
backup/restore edits one boolean to unlock £2.99 of features.

This is the deliberate, documented house pattern for local-first apps with no
backend (house-facts §8/§9), and with no server there is nowhere to verify a
receipt. It is recorded here at Medium — proportionate, not blocking — because
the blast radius is one sub-£10 unlock on a device the attacker already
controls, and no credential, token, PII or backend is exposed.

One thing here is worth correcting regardless of whether the design changes.
`settings_repository.dart:37-39` documents the field as:

> Cached entitlement so the app opens in the right tier before the store
> connection resolves. **The store's restored-purchase stream remains the source
> of truth and overwrites this on every launch.**

The second sentence is not true. `_unlock()` is the only writer and it only ever
writes `true`; a launch where the store reports no purchase produces no stream
event at all (the code says so itself at `purchase_controller.dart:98-99`) and
leaves the flag as it was. The local flag *is* the source of truth after first
unlock, permanently. A maintainer trusting that comment would reasonably assume
a refund or a restore-on-a-different-account downgrades the tier, and neither
does.

The upside of the current design is worth stating: it cannot brick a paying
user. `restorePurchases()` runs on every launch (`:56`), the cached flag means
the app opens Pro before the store answers, `clampedForTier` is applied on read
rather than on write so a lapse never destroys customised settings, and
`pendingCompletePurchase` is always acknowledged (`:132-134`) so Android cannot
auto-refund a real purchase after three days. The failure mode is
over-entitlement, never under-entitlement.

### SEC-4 — Privacy policy retention figure does not match the code

- **Severity:** Low
- **Affected component:** `PRIVACY_POLICY.md`
- **Location:** `PRIVACY_POLICY.md:19-21` vs
  `lib/features/measurement/data/history_repository.dart:13`

The policy states measurements "are kept for 24 hours and then deleted
automatically". `HistoryRepository` retains **25 hours** (deliberately, so a
"last 24 hours" view is never short — the reason is documented at `:17-19`).
The policy is a published legal document for an app whose entire pitch is
telling the truth about numbers; the two should agree. Either wording — "up to
25 hours" or "about a day" — resolves it.

### SEC-5 — Play Billing's telemetry client is live in the release binary

- **Severity:** Low (informational; carries an action for stage 6)
- **Affected component:** transitive dependency of `in_app_purchase`
- **Location:** release `classes.dex`

PRODUCT_SPEC §9 notes that Play Billing pulls `com.google.android.datatransport`
transitively. Confirming what that actually is in the shipped artifact, because
a plain hostname search is misleading here:

```
googleapis / firebaselogging / clearcut  →  0 hits in classes.dex
```

That reads as "R8 stripped it". It did not. The endpoint is stored
character-interleaved specifically to defeat that search. Merging the fragments
recovered from the dex:

```
"hts/frbslgigp.ogepscmv/ieo/eaybtho
"tp:/ieaeogn-agolai.o/1frlglgc/aclg
→ https://firebaselogging-pa.googleapis.com/v1/firelog/legacy/batchlog
```

`CctBackendFactory` is present and the three manifest components
(`TransportBackendDiscovery`, `JobInfoSchedulerService`,
`AlarmManagerSchedulerBroadcastReceiver`) are all merged in, all
`exported="false"`. So the Android release binary does contain a live Google
telemetry client, reporting Play Billing events to Google.

**"No data collected" still holds on both stores** and this is not a finding
against the app. Play's Data Safety scope excludes data Google Play itself
collects to process a purchase; no vendor privacy manifest declares collection;
and iOS has no equivalent, since StoreKit is first-party. It is recorded so the
compliance stage answers the Data Safety form from evidence rather than
discovering the components mid-review, and so no store text claims the app's
only network traffic is the probes.

One related timing note for the same stage: `PurchaseController.init()` contacts
the store at **cold start on every launch** — `isAvailable()`, then
`queryProductDetails`, then `restorePurchases()` (`purchase_controller.dart:39-56`).
Any wording implying the store is contacted only at purchase time would be
inaccurate. The current `PRIVACY_POLICY.md` does not make that claim.

### SEC-6 — No explicit network security configuration

- **Severity:** Low
- **Affected component:** Android and iOS network configuration
- **Location:** `android/app/src/main/AndroidManifest.xml`, `ios/Runner/Info.plist`

There is no `networkSecurityConfig`, no certificate pinning, and no explicit
`usesCleartextTraffic="false"`. For an app with no backend, no accounts and no
credentials in flight, pinning would be disproportionate and would couple the
app's uptime to two third parties' certificate rotations — not recommended.

The platform defaults already do most of the work, and are worth stating
precisely because they bound SEC-1:

- **targetSdk 36** (verified in the release merged manifest) means cleartext is
  denied by default, so a redirect from the HTTPS probe endpoints down to
  plaintext HTTP fails at the socket. `package:http` follows redirects by
  default, so this default is doing real work.
- **minSdk 24** means user-installed CAs are not trusted by app connections.
  On Android, substituting a probe response requires a system or MDM-installed
  CA — a managed device, not a hostile café Wi-Fi.
- **iOS honours user-installed trusted roots**, so a device with a configuration
  profile installed is the more exposed platform for SEC-1.

An explicit `network_security_config.xml` pinning the app to system CAs and
denying cleartext would make the posture intentional rather than inherited, and
survives a future `targetSdk` or dependency change that alters a default.

---

## EXPLOIT SCENARIO

**SEC-1, adversarial.** A user's device is enrolled in an employer's MDM, which
has installed a system-level CA — or on iOS, the user has installed a
configuration profile. The intercepting proxy sees a request to
`speed.cloudflare.com/__down?bytes=120000` and answers it itself, streaming
continuously instead of the 120 KB requested. The client accepts every byte.
The measured evidence above shows 3 MB accepted in 13.6 s from a deliberately
slow server; a proxy on a fast link delivers far more. The foreground service
repeats this every 10 minutes, all day, and the on-screen budget counter — which
only learns what was spent after each cycle finishes — reports a plausible
number until the day's cap trips, by which point the data is gone. The same
control sets the throughput figure and therefore the bar count, so the operator
of the intercepting network decides what score the app displays for their
network.

**SEC-1, non-adversarial, and the more likely one.** No attacker at all.
`speed.cloudflare.com/__down` is a third-party endpoint whose contract the app
does not control. If it ever ignores the `bytes` parameter, changes its error
behaviour, or is fronted by something that substitutes a larger body, the same
overspend happens to every user simultaneously, and the retry at
`measurement_engine.dart:150` runs it a second time. A byte cap costs one line
and removes the dependency on that endpoint continuing to behave.

**SEC-2 + SEC-3 combined.** A user buys Pro, then sets up a new phone with
Android's device-to-device transfer or a Google Drive restore. `pro_unlocked:
true` arrives in the Hive box on the new device, and because nothing ever
downgrades the flag (SEC-3), the app opens Pro there permanently regardless of
what account is signed in. No rooting required — this is ordinary supported
Android behaviour. The same channel is how the connectivity history leaves the
device.

---

## RECOMMENDED FIX

### SEC-1 — cap the transfer by bytes and by wall clock

Both bounds are needed: the byte cap stops the overspend, the deadline stops a
slow-drip responder holding the cycle open past its interval.

```dart
@override
Future<TransferResult> transfer(Uri url, {required Duration timeout}) async {
  // Accept a margin over the size requested — the endpoint may add headers or
  // round up — but never an unbounded body. `Stream.timeout` is an inter-chunk
  // timeout, so a responder that keeps sending would otherwise never trip it.
  final capBytes = _requestedBytes(url) * 2 + 64 * 1024;
  final deadline = Stopwatch()..start();
  var received = 0;
  try {
    final request = http.Request('GET', _cacheBust(url))
      ..headers['cache-control'] = 'no-cache, no-store';
    final streamed = await _client.send(request).timeout(timeout);
    await for (final chunk in streamed.stream.timeout(timeout)) {
      received += chunk.length;
      if (received > capBytes || deadline.elapsed > timeout) {
        // Charge what arrived, then stop reading.
        return TransferResult(ok: false, bytes: received, elapsedMs: 0);
      }
    }
    ...
```

`_requestedBytes` reads the `bytes` query parameter the app itself set, so the
cap tracks `MeasurementConfig.transferBytes` and the retry size automatically
rather than hardcoding a second copy of the number.

Aborting must charge `received` to the budget — as the existing `catch` already
does at `:122` — so a truncated hostile response still costs the attacker the
app's attention rather than being free.

Two regression tests belong in `test/release_invariants_test.dart`, next to the
existing "asked for exactly the bytes budgeted" test, which currently guards
only the request side:

- a fake client streaming 10 MB returns `bytes` at or under the cap;
- a fake client dripping past the timeout returns within the timeout.

Consider the same treatment for `probe()` for symmetry. It is already
time-bounded (measured above) so this is defence in depth, not a fix.

### SEC-2 — turn backup off and say so

```xml
<application
    android:label="True Signal"
    android:name="${applicationName}"
    android:icon="@mipmap/ic_launcher"
    android:allowBackup="false"
    android:dataExtractionRules="@xml/data_extraction_rules">
```

`allowBackup="false"` is the cloud-backup control. It does **not** cover
device-to-device transfer on API 31+; that needs the `<device-transfer>` block,
which is why the rules file is listed as well:

```xml
<!-- android/app/src/main/res/xml/data_extraction_rules.xml -->
<data-extraction-rules>
    <cloud-backup>
        <exclude domain="root" />
        <exclude domain="file" />
        <exclude domain="database" />
        <exclude domain="sharedpref" />
    </cloud-backup>
    <device-transfer>
        <exclude domain="root" />
        <exclude domain="file" />
        <exclude domain="database" />
        <exclude domain="sharedpref" />
    </device-transfer>
</data-extraction-rules>
```

Excluding each domain **root** prunes the whole subtree — `BackupAgent`
compares canonical paths and skips a matched directory before enqueuing its
children — so this covers the Hive boxes (`root` domain, via
`app_flutter/`) and all three SharedPreferences files without naming individual
files that a later refactor could move.

Then either leave `PRIVACY_POLICY.md:26-27` as it is, since it becomes
unambiguously true, or, if backup is deliberately kept on so users keep their
Pro unlock across devices, reword that sentence to say so plainly.

Extend the manifest group in `release_invariants_test.dart` to assert
`allowBackup="false"` is present, so it cannot be lost in a later manifest edit.

### SEC-3 — proportionate hardening only

No server exists, so receipt verification is not available and should not be
invented. Worth doing, in rough order of value per unit of risk:

1. **Fix the comment** at `settings_repository.dart:37-39` to describe what the
   code does — the cached flag is authoritative once set, and nothing downgrades
   it. Cheapest item in this document and it prevents a future maintainer
   building on a false premise.
2. **Carry `verificationData` through the `IapGateway` seam** and store a
   keystore-backed HMAC over the flag rather than a bare `true`. Raises the bar
   from "edit a boolean" to "forge a signature", and costs nothing at runtime.
3. **Downgrade only on a positive negative** — if a launch's `restorePurchases()`
   completes and the store affirmatively reports no entitlement, clear the flag.
   Never downgrade on a timeout, an offline launch, or an unavailable store, or
   a paying user on a plane loses Pro.

Item 3 changes user-visible behaviour on refund and is a founder call, not a
security requirement. Items 1 and 2 are safe to take now.

### SEC-4 — align the retention figure

Change `PRIVACY_POLICY.md:20-21` to "up to 25 hours", or change `retention` to
24 h and accept a slightly short window at the edge. The first is better; the
25-hour choice is deliberate and well reasoned.

### SEC-6 — make the network posture explicit

```xml
<!-- android/app/src/main/res/xml/network_security_config.xml -->
<network-security-config>
    <base-config cleartextTrafficPermitted="false">
        <trust-anchors>
            <certificates src="system" />
        </trust-anchors>
    </base-config>
</network-security-config>
```

Referenced from `<application android:networkSecurityConfig="@xml/network_security_config">`.
This pins the app to system CAs on every API level rather than relying on the
minSdk 24 default, and states the cleartext denial rather than inheriting it
from `targetSdk`. No pinning to specific certificates — see SEC-6 above for why
that would be the wrong trade here.

---

## WHAT WAS CHECKED AND FOUND CLEAN

Recorded because "no finding" is only useful if it says what was looked at.

**No secrets, anywhere.** A credential-pattern scan across `lib/`, the Kotlin
sources, `ios/Runner/`, and the Gradle files returned nothing. No `key.properties`,
`.jks`, `.keystore` or `.p8` exists in the tree. `android/.gitignore` already
covers `key.properties`, `**/*.jks` and `**/*.keystore`, and `ios/.gitignore`
covers `Flutter/Generated.xcconfig` — so when this repo is initialised and pushed
to the public `mksoft-ltd` org (house-facts §5), the upload keystore and its
passwords cannot be swept in by a `git add .`. This was worth confirming
explicitly: the keystore does not exist yet, generating it is an outstanding
pre-release to-do, and the root `.gitignore` alone does not cover it.

**Every URL in the shipped Dart snapshot is accounted for.** Extracting every
`http(s)://` string from the arm64 AOT snapshot in the release APK yields
exactly the four probe hosts the privacy policy names, the privacy-policy URL
itself, and Flutter framework documentation links inside error messages:

```
https://connectivitycheck.gstatic.com/generate_204
https://cp.cloudflare.com/generate_204
https://speed.cloudflare.com/__down?bytes=
https://www.gstatic.com/generate_204
https://raw.githubusercontent.com/mksoft-ltd/true_signal/refs/heads/main/PRIVACY_POLICY.md
```

No undisclosed endpoint, no analytics beacon, no hardcoded key. The probe
requests carry no identifier, cookie or app-specific header
(`probe_client.dart:72-74`), only cache-control and a cache-busting timestamp.

**Android component surface.** Enumerated from the release merged manifest.
Every app component is `exported="false"` except `MainActivity`, which must be
exported to be a launcher. `TrueSignalService`, `OverlayService` and
`BootReceiver` are all unexported, so no third-party app can start the service,
spoof a reading via `ACTION_PUBLISH`, or fake `ACTION_UI_ACTIVE` to suppress
measurement. The only other exported component is AndroidX's
`ProfileInstallReceiver`, gated behind `android.permission.DUMP`
(signature|privileged), which is standard and not reachable by third-party apps.

**PendingIntents are immutable.** Both intents in the notification —
content-open and the "Turn off" action — use
`FLAG_UPDATE_CURRENT or FLAG_IMMUTABLE` (`TrueSignalService.kt:307-321`), so
neither can be filled in by a recipient. Required on API 31+ and correct here.

**The background engine entrypoint is not an abuse surface.**
`trueSignalBackgroundMain` is reachable only via
`DartExecutor.executeDartEntrypoint` from within the app's own unexported
service — it is not an exported component, an intent action, or a registered
callback handle, and there is no IPC path to it. Using a *named* entrypoint
rather than a stored callback handle is the safer of the two options: there is
no persisted integer for a restore or a downgrade to redirect. `onBind` returns
null on both services.

**Platform-channel inputs are validated.** `applyConfig` coerces the interval
into `30..3600` regardless of what Dart sends (`TrueSignalService.kt:169`), so a
compromised or buggy caller cannot turn the service into a tight-loop battery
and data drain. `BudgetChannel` rejects a call with no `day` argument and
`spend` floors the byte count at zero (`BudgetChannel.kt:33`), so the counter
cannot be driven backwards to manufacture budget. The budget read fails
**closed** — a dead channel reports the budget fully spent
(`budget_store.dart:57-67`) rather than free.

**Overlay constraints hold up.** The bubble is ~44 dp, `FLAG_NOT_FOCUSABLE`
(so it takes no input except on itself), `TYPE_APPLICATION_OVERLAY`, and draws
nothing but the score — no ads, no promotions, no third-party content. It cannot
appear on a fresh install: Pro-gated, off by default, and the permission is
requested only from a dedicated screen after the user turns the feature on.
`canDraw()` is re-checked on every service start (`OverlayService.kt:76`) and on
boot restore, so a revoked grant cannot be resurrected. On the incoming side,
no view sets `filterTouchesWhenObscured`, but the app has no security-relevant
tap target of its own — purchases run in the store's own system-protected sheet
— so the residual tapjacking risk is negligible.

**Pro gating cannot leak.** `effectiveSettingsProvider` (`providers.dart:69-72`)
is the single downstream read, and it applies `clampedForTier` before anything
consumes it — including the indicator controller and the config pushed to the
Kotlin service. A free install cannot reach Pro intervals, themes or the overlay
through the platform channel, because the unclamped settings never get that far.

**Screenshot mode is welded shut.** `ScreenshotMode.isEnabled` is
`bool.fromEnvironment(...) && !kReleaseMode` (`screenshot_mode.dart:35`), a
compile-time constant, so the demo branches are tree-shaken from any release
build and there is no runtime toggle. `debugForcePro()` is wrapped in
`assert(...)` and vanishes in release. Every documented capture command in
`docs/TEST_PLAN.md`, `store_assets/screenshot_specs.md`,
`store_assets/screenshots/render.sh` and `PRODUCT_SPEC.md` uses `flutter drive`,
which is a debug build — none of them is a `flutter build` variant that would
default to release and carry the define into a signed artifact. The harness also
writes to in-memory Hive boxes (`local_store.dart:29-40`), so a capture run
cannot overwrite real device data. `ios/Flutter/Generated.xcconfig` is currently
clean: `FLUTTER_TARGET=lib/main.dart` and no `SCREENSHOT_MODE` in `DART_DEFINES`.

**No logging of anything.** No `print`, `debugPrint`, `Log.d` or `NSLog`
anywhere in `lib/`, the Kotlin sources or `ios/Runner/`. Nothing to leak.

**Supply chain is clean.** All 95 resolved packages come from `pub.dev` — no
git dependencies, no path dependencies, no mutable branch pins. Direct
dependencies are current (`http` 1.6.0, `in_app_purchase` 3.3.0,
`connectivity_plus` 6.1.5, `go_router` 14.8.1, `hive` 2.2.3, `url_launcher`
6.3.2). No analytics, crash-reporting or advertising SDK is present, satisfying
house rule §8; the only telemetry-capable code in the binary is Play Billing's
own, documented as SEC-5. `flutter_launcher_icons` is dev-only.

**R8 keeps nothing dangerous and strips nothing security-relevant.**
`proguard-rules.pro` keeps the app's own package (required — the background
entrypoint is resolved by name), the Flutter embedding, and billing classes.
No `-dontobfuscate`, no `-dontoptimize`, no keep rule that would preserve a
debug path. `isMinifyEnabled` and `isShrinkResources` are both on for release.

**iOS.** No permission-gated API is used and no purpose string is declared,
which the Info.plist confirms. `ITSAppUsesNonExemptEncryption=false` is correct
for standard HTTPS through the system stack. No ATS exceptions are declared, so
arbitrary loads remain denied. Nothing is written to the Keychain because there
is nothing to put in it.

**Release build hygiene.** The release merged manifest carries no
`android:debuggable`, targetSdk 36, minSdk 24.

---

## SECURITY BEST PRACTICES

Beyond the fixes above, in rough order of value:

1. **Add a release-lane assertion that `SCREENSHOT_MODE` is absent.** The guard
   is correct today and the documented commands are all debug. The residual risk
   is a future capture command being copy-pasted into a build command; a
   one-line check in the fastlane release lane closes it permanently.
2. **Keep the audit assertions in `release_invariants_test.dart`.** That file is
   already the right shape — facts with a copy outside the code. The transfer
   cap (SEC-1), `allowBackup="false"` (SEC-2) and the retention figure quoted in
   the privacy policy (SEC-4) all belong there, so a later edit that undoes them
   fails a test rather than shipping.
3. **Re-check the probe endpoint list whenever it changes.** `ProbeTargets.latency`
   is immutable at runtime and already asserted against the privacy policy's
   named hosts. Adding a host is a policy edit and a store-listing edit, not
   only a code edit — the existing test enforces this and should be kept.
4. **Verify the boot receiver on real hardware.** `BootReceiver` is
   `exported="false"` with a `BOOT_COMPLETED` filter. That is the correct and
   safe direction from a security standpoint and is not a finding. Whether the
   receiver actually fires in that configuration is a functional question this
   audit could not settle from sources on disk; PRODUCT_SPEC §13 already lists
   boot behaviour as needing a device, and it belongs to code-review/QA.
5. **When the repo is pushed to `mksoft-ltd`, confirm the keystore stayed out.**
   The ignore rules are correct (verified above), but the keystore does not exist
   yet — it is generated later in the pipeline. A `git log --stat | grep -i
   'jks\|key.properties'` after the first push costs seconds and catches the one
   mistake that would be genuinely expensive.

---

## Fix round — what changed (flutter-architect, 2026-08-09)

| ID | Change | How it was checked here |
|---|---|---|
| SEC-1 | `HttpProbeClient.transfer` now caps the response at the `bytes` value the app itself put in the URL, and applies **one** `.timeout()` to the whole body read rather than per chunk, so a slow drip cannot hold the request open. Partial bytes are still charged to the budget. | Two regression tests in `test/probe_client_test.dart` drive a fake client (oversize body, slow drip), and `test/release_invariants_test.dart` adds stronger versions that run the **real** client against a local `HttpServer` — one offering 64 MB against a 120 KB request, one dripping 8 KB every 400 ms. Both assert the ceiling and the wall-clock bound. |
| SEC-2 | `android:allowBackup="false"` plus `android:dataExtractionRules="@xml/data_extraction_rules"`, the rules file excluding `root`/`file`/`database`/`sharedpref` under both `<cloud-backup>` and `<device-transfer>`. | **Verified in the release MERGED manifest**, not the source: `build/app/intermediates/packaged_manifests/release/processReleaseManifestForPackage/AndroidManifest.xml` after a fresh `flutter build apk --release`. Pinned by a test in `release_invariants_test.dart`. `PRIVACY_POLICY.md` now says plainly that data "is not included in cloud backup or device-to-device transfer". |
| SEC-3 | Item 1 only, as recommended. The comment at `settings_repository.dart` no longer claims the store stream "overwrites this on every launch"; it now says the flag is not cleared merely because a launch is offline or the store is unavailable. Items 2 and 3 were deliberately not taken — item 3 is a founder call. | Source review. |
| SEC-4 | Settled on **25 hours**, single-sourced. Added `HistoryRepository.defaultRetention`; the history screen (which still said 24 hours) and the "How the score works" screen now interpolate that constant instead of retyping it. | A new invariant test reads `PRIVACY_POLICY.md` and asserts it quotes the constant, so the code, both screens and the published document cannot drift apart again. |
| SEC-6 | `android:networkSecurityConfig="@xml/network_security_config"` with `cleartextTrafficPermitted="false"` and system-only trust anchors. No certificate pinning, per the recommendation. | Verified in the same merged release manifest; pinned by a test. |

SEC-5 needs no code change and remains an input to stage 6 — Play Billing's
Firelog components still ship in the release dex, and the Data Safety answer
should be given knowing that.

Gates at the end of the round: `flutter analyze` **No issues found**;
`flutter test` **268/268 passing, 0 skipped**; `flutter build apk --release`
**succeeds** (52.9 MB).

---

## Fix-round note (flutter-architect, 2026-08-09)

Not a verdict. This records what changed so the findings can be re-verified
against the code and the built artifact.

**SEC-1 — transfer is now bounded by bytes and by wall clock.**
`HttpProbeClient.transfer` derives its cap from the `bytes` query parameter the
app itself set, so it tracks `MeasurementConfig.transferBytes` and the retry
size rather than hardcoding a second copy. The `.timeout()` is applied to the
Future that reads the whole body, not to the chunk stream, so it is a total
deadline — the distinction the audit identified between `probe()` and
`transfer()`. A truncated response still charges `received` to the budget.
(`probe_client.dart:104-140`)

Reading stops at the first chunk that crosses the cap, so the ceiling is the
requested size plus at most one chunk. It is bounded by the app's own number
instead of by how long the peer chooses to keep sending; it is not a promise
that never a byte over 120,000 arrives, and the test asserts the former.

Two regression tests were added next to the request-side one, both driving the
real client against a real loopback server, since the bug lived in how the
response was read (`release_invariants_test.dart`, group "and enforces that size
on the response"). Both were confirmed to fail against the previous unbounded
loop: **67,108,864 bytes accepted** against a 120,000-byte request, and a slow
drip held the cycle open for **30 s** against a 2 s timeout.

**SEC-2 — backup off, confirmed in the release merged manifest.**
`allowBackup="false"`, `dataExtractionRules="@xml/data_extraction_rules"` and
`networkSecurityConfig="@xml/network_security_config"` are all present in
`build/app/intermediates/packaged_manifests/release/.../AndroidManifest.xml`.
The rules file excludes domains `root`, `file`, `database` and `sharedpref`
under both `<cloud-backup>` and `<device-transfer>`. `release_invariants_test.dart`
asserts the manifest attributes and the rules file so a later manifest edit
fails a test. No `android:debuggable`; the only exported components remain
`MainActivity` and AndroidX's `ProfileInstallReceiver`.

**SEC-3 (comment only) — corrected.** `settings_repository.dart` no longer
claims the store stream "overwrites this on every launch". It now says a
verified purchase or restore can set the flag and that it is not cleared merely
because a launch is offline or the store is unavailable — which is what the code
does. The design itself (items 2 and 3 of the recommendation) is unchanged and
remains a founder call.

**SEC-4 — retention aligned.** `PRIVACY_POLICY.md` now reads "up to 25 hours",
matching `HistoryRepository.defaultRetention`. The in-app "How the score works"
screen builds its sentence from that same constant rather than a literal, and
`release_invariants_test.dart` asserts the published figure equals the enforced
one.

Not addressed in this round: SEC-5 (informational, carries an action for stage 6
rather than a code change) and the SEC-6 recommendation beyond the
`network_security_config.xml` already referenced above.

Gates: `flutter analyze` clean, `flutter test` 268/268, release APK (R8) and iOS
simulator both build.

---

## Re-verification (mobile-security-auditor, 2026-08-09)

All four fixed findings re-verified independently — against the code, against a
freshly built release artifact, and by executing the probe client rather than
reading it. **Verdict unchanged: PASS.** Nothing is reopened and no new finding
is raised. One test-robustness issue is recorded below; it is not a security
finding and does not gate.

### SEC-1 — resolved

Both bounds confirmed by running the real `HttpProbeClient` against a local
server, the same way the original finding was established:

| Scenario | Result |
|---|---|
| Well-behaved response of exactly 120,000 B | `ok=true bytes=120000` — the cap does not break the happy path (the check is `>`, not `>=`) |
| 8 KB dripped every 400 ms against a 2 s timeout | stopped at **2,005 ms** — the total deadline holds |
| Continuous stream, 16 KB writes | stopped at **131,072 B** against a 120,000 B request |

Before the fix the same client accepted 3,072,000 B and ran 13.6 s past an 8 s
timeout. The overspend is now bounded by the app's own requested size plus one
socket read, and the retry means at most two such reads per cycle. The residual
is inherent — bytes the OS has already delivered cannot be un-received — and the
line was drawn in the right place.

**On the ceiling, since it was explicitly raised for scrutiny.** The claim "the
requested size plus at most one chunk" is correct, but *chunk* means one socket
read, not one server write, and the two are not the same because the client
coalesces. Worst case over five runs per configuration:

| Server write size | Bytes accepted | Overshoot |
|---|---|---|
| 16 KB | 131,072 | 10.8 KB |
| 64 KB | 131,072 | 10.8 KB |
| 200 KB | 204,800 | 82.8 KB |
| 1 MB | 1,048,576 | 906.8 KB |

So the committed assertion `bytes <= requested + 64 KB` passes because that
test's server writes 16 KB and loopback coalescing lands at 128 KB total — not
because 64 KB is a bound the code guarantees. The 200 KB observation already
noted in the fix round (204,800 B accepted) exceeds that margin, and noticing it
was right.

**This is a test-robustness problem, not a security one.** On a machine whose
socket receive buffer autotunes differently the test can fail on non-regressed
code, and it would equally miss a real regression that widened the overshoot to
150 KB. Suggested change — assert the property that is actually guaranteed, and
is orders of magnitude clear of the failure mode:

```dart
// 64 MB was on offer; anything in this range proves the read was cut off.
expect(result.bytes, lessThan(2 * 1024 * 1024));
expect(result.ok, isFalse);
```

That fails hard against the old unbounded loop, which accepted 64 MB, and cannot
flake on buffer sizing. Deriving the margin from the server's write size, which
the test controls, would work equally well. The constant is the only part worth
changing; the fix itself stands.

### SEC-2 — resolved, verified in the shipped APK rather than the source

The built manifest post-dates the source edits (manifest `2026-08-09T01:48`,
sources `2026-08-08T10:42`), so the artifact is genuinely rebuilt and not a
stale read. In `packaged_manifests/release/.../AndroidManifest.xml`:
`allowBackup="false"`, `dataExtractionRules="@xml/data_extraction_rules"`,
`networkSecurityConfig="@xml/network_security_config"`, no `android:debuggable`.
The permission set is unchanged from the pre-fix audit and the only exported
components remain `MainActivity` and AndroidX's `ProfileInstallReceiver` behind
`permission.DUMP`.

Going one step past the manifest, since resource shrinking could in principle
drop a manifest-referenced XML: both resources are confirmed present **and
correct inside the release APK**. `aapt2 dump resources` resolves
`xml/data_extraction_rules` to `res/4j.xml`, and `aapt2 dump xmltree` on that
entry returns all four excludes under both blocks:

```
E: data-extraction-rules
    E: cloud-backup     → exclude root / file / database / sharedpref
    E: device-transfer  → exclude root / file / database / sharedpref
```

`domain="root"` is present in both, which is the one that matters: the Hive
boxes live in `app_flutter/`, which is the `root` domain, and a `file`-only
exclusion would have missed them entirely. `network_security_config` resolves to
`res/8G.xml` and dumps as `cleartextTrafficPermitted=false` with system-only
trust anchors.

### SEC-3 — resolved (comment only, as scoped)

The comment now states that a purchase or restore can set the flag and that it
is not cleared merely because a launch is offline or the store is unavailable.
That matches the code. Declining items 2 and 3 was correct: item 3 changes
refund behaviour and is a founder decision, not a fix-round item.

### SEC-4 — resolved, and more durably than asked

The policy reads "kept for up to 25 hours"; `HistoryRepository.defaultRetention`
is the single source; the history and "How the score works" screens interpolate
it rather than restating it; and the invariant test reads `PRIVACY_POLICY.md`,
asserts it quotes the constant, and asserts the old "24 hours and then deleted"
wording is gone. Single-sourcing the figure is what stops this drifting again.

### SEC-5 / SEC-6

Unchanged and correctly scoped. SEC-5 needs no code change and remains an input
to stage 6. The network security config landed; certificate pinning was
correctly declined.

**Suite:** `flutter test` **269/269 passing**. `test/` holds no leftover probe or
temporary files from either stage-4 auditor.

---

## SEC-1 test constant (flutter-architect, 2026-08-09)

Taken as recommended. **`probe_client.dart` is unchanged** — the fix was
confirmed sound by execution and only the assertion moved.

`test/release_invariants_test.dart`, "a responder that keeps sending is cut off
near the budgeted size", now asserts `lessThan(2 * 1024 * 1024)` against the
64 MB the test server offers, replacing `lessThanOrEqualTo(_requestedBytes +
64 * 1024)`. The comment above it was carrying the same false premise — it
claimed the ceiling is "the request plus at most one chunk" — and has been
rewritten to say that a chunk is one socket read rather than one server write,
that the client coalesces, and that the overshoot is therefore a property of
receive-buffer autotuning rather than a bound this code guarantees. The measured
figures (16 KB writes → ~11 KB overshoot, 1 MB writes → ~907 KB) are recorded
there so the next reader does not re-tighten it.

Verified the new assertion still bites: with the cap check removed from
`transfer()`, the client accepts the whole **67,108,864 bytes** on offer and the
test fails with `Expected: a value less than <2097152> Actual: <67108864>`.
Cap restored.

Left alone deliberately: the exactly-120,000-byte happy path, which is guarded
by `>` rather than `>=` in the cap check so a precisely-sized response still
returns `ok=true`.

Gates: `flutter analyze` **No issues found** · `flutter test` **271/271, 0
skipped**.

---

Verdict: PASS
