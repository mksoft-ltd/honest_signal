# Play Console — Data safety, App content and IARC answers (Honest Signal)

Console-only forms; `supply` cannot upload any of them. Answer exactly as below.

App: **Honest Signal** · `com.froggyeye.honestsignal` · v1.0.0 (**versionCode 1**) ·
Play app id `4973053518256217291` · Froggy Eye Ltd · first release, nothing live.

Written by release-manager 2026-08-09 from `docs/PRODUCT_SPEC.md` §9/§10 and
`docs/audits/security.md` (stage 4b, **Verdict: PASS**, re-verified after the fix
round). The permission list below was parsed from the **release merged manifest**
at `build/app/intermediates/merged_manifest/release/processReleaseMainManifest/AndroidManifest.xml`,
not grepped from source.

Release merged manifest, in full — **nine permissions, one of them a runtime
permission**:

| Permission | Declared by | Runtime prompt? |
|---|---|---|
| `android.permission.INTERNET` | us | No (normal) |
| `android.permission.ACCESS_NETWORK_STATE` | us | No (normal) |
| `android.permission.POST_NOTIFICATIONS` | us | **Yes** (Android 13+) |
| `android.permission.FOREGROUND_SERVICE` | us | No (normal) |
| `android.permission.FOREGROUND_SERVICE_SPECIAL_USE` | us | No (normal) |
| `android.permission.SYSTEM_ALERT_WINDOW` | us | **Yes**, via system settings — Pro-only, off by default |
| `android.permission.RECEIVE_BOOT_COMPLETED` | us | No (normal) |
| `com.android.vending.BILLING` | `in_app_purchase` (transitive) | No |
| `com.froggyeye.honestsignal.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` | AndroidX core (signature-level, internal) | No |

No location, camera, microphone, contacts, calendar, storage, media, phone-state,
exact-alarm, full-screen-intent, all-files-access, `QUERY_ALL_PACKAGES` or
**`AD_ID`** permission of any kind. Play Billing pulls `play-services-location`
and `com.google.android.datatransport` as transitive libraries; neither adds a
permission and neither is called by this app.

`android:allowBackup="false"` with `backup_rules.xml` and
`data_extraction_rules.xml` both excluding `domain="root"` — confirmed by the
security auditor with `aapt2 dump xmltree` on the **packaged** APK, so the Hive
boxes under `app_flutter/` are excluded from cloud backup and device-to-device
transfer.

---

## 1. Data safety — overview answers

| Question | Answer |
|---|---|
| Does your app collect or share any of the required user data types? | **No** |
| Is all of the user data collected by your app encrypted in transit? | **Not applicable** — the form stops asking once "collect or share" is No. If a console variant asks anyway, answer **Yes**: every request the app makes is HTTPS. |
| Do you provide a way for users to request that their data is deleted? | **Not applicable**, same reason. Free-text answer below if one is offered. |
| Does your app comply with the Families policy? | Not applicable — target audience is 18+, not opted into Designed for Families (§4) |
| Privacy policy URL | `https://mksoft-ltd.github.io/honest_signal/privacy_policy.html` — GitHub Pages, **verified 2026-08-09: HTTP 200, `content-type: text/html; charset=utf-8`**, by extracting the string from `AppConstants.privacyPolicyUrl` and fetching that, so the binary and the listing cannot disagree. Rendered HTML rather than the raw `.md`, which GitHub serves as `text/plain`. See the risk note in §9. |

**Deletion answer, in the free-text box if one is offered:** "The app has no
account and no backend, and holds no user record. Everything it stores —
connection measurements, settings, and a flag recording the Pro purchase — is
written to the app's own private storage on the device, is excluded from Android
cloud backup and from device-to-device transfer, and is deleted when the app is
uninstalled. Measurement history can also be cleared from the History screen, and
is pruned automatically after 25 hours regardless."

### 1.1 Why "No data collected" is right, and the two things that ship anyway

Play's form asks about data **collected or shared** — transmitted off the device
by the app — not data stored on it. This app transmits nothing about the user.

There is **no analytics, advertising, attribution or crash-reporting SDK** in the
binary, and Froggy Eye Ltd operates no server. Two components do send traffic,
and both sit outside the form's scope. Recording them here so the answer is given
from evidence rather than discovered mid-review:

1. **The measurement probes.** Anonymous HTTPS GETs to four public
   connectivity-check and speed-test endpoints — `www.gstatic.com`,
   `connectivitycheck.gstatic.com` (Google), `cp.cloudflare.com`,
   `speed.cloudflare.com` (Cloudflare) — the same class of endpoint Android
   itself polls for captive-portal detection. They carry no identifier, cookie,
   account or user data; the only parameter added is a cache-buster, and nothing
   comes back but timing. As with any web request the endpoint operator
   necessarily sees the originating IP address, which `PRIVACY_POLICY.md` states
   explicitly rather than glossing over. The app neither collects nor receives
   that IP: it is not app-collected data and is not declarable here.
2. **Play Billing's own telemetry.** The stage-4b audit found
   `com.google.android.datatransport`'s CCT backend live in the release dex —
   `CctBackendFactory` plus `TransportBackendDiscovery`, `JobInfoSchedulerService`
   and `AlarmManagerSchedulerBroadcastReceiver`, all `exported="false"` — posting
   to `https://firebaselogging-pa.googleapis.com/v1/firelog/legacy/batchlog`. It
   is a transitive dependency of `in_app_purchase` → `billing:8.0.0` and cannot be
   excluded without breaking Play Billing. A plain hostname grep of the dex finds
   **zero** hits because the endpoint is stored character-interleaved; do not
   conclude from a clean grep that R8 stripped it. **"No data collected" still
   holds**: this is Google Play's own client reporting Play Billing events to
   Google, and Play's Data safety scope excludes data Google Play collects to
   process a purchase. It is not the app collecting anything.

   Related timing fact, so no answer or store text contradicts the binary:
   `PurchaseController.init()` contacts the store at **every cold start**
   (`isAvailable`, `queryProductDetails`, `restorePurchases`), not only at
   purchase time.

### 1.2 Data types — if the console still walks the list

Every category: **not collected, not shared.** Location, Personal info, Financial
info, Health and fitness, Messages, Photos and videos, Audio files, Files and
docs, Calendar, Contacts, App activity, Web browsing, App info and performance
(no crash logs, no diagnostics, no performance SDK), Device or other IDs (no
advertising ID, no device ID, no installation ID is read or sent).

## 2. Data safety — security practices

| Question | Answer |
|---|---|
| Is data encrypted in transit? | Not applicable (nothing collected). If forced: **Yes**, HTTPS only. |
| Can users request data deletion? | Not applicable. If forced: **Yes** — uninstall, plus in-app clear on the History screen. |
| Committed to Play Families Policy? | **No** (not a Families app) |
| Independent security review | **No** — do not claim one. The stage-4b audit is an internal audit, not a third-party review, and ticking this without a published report is a misrepresentation. |

## 3. Ads and in-app purchases

| Question | Answer |
|---|---|
| Contains ads | **No** — there is no `google_mobile_ads` or any ad SDK in `pubspec.yaml`, and no ad permission in the merged manifest |
| In-app purchases | **Yes** — one product, `com.froggyeye.honestsignal.pro`, one-time non-consumable, **£2.99–£2.99** |
| Uses advertising ID | **No** — no `AD_ID` permission, no ad or attribution SDK. Answering Yes here blocks Play's pre-review quick checks for no reason. |

**IAP price mechanics (house-facts #18):** `convertRegionPrices` takes
**tax-exclusive** input. For a £2.99 shelf price with 20% UK VAT, feed
**£2.4917** (`2.99 ÷ 1.2`). Feeding `2.99` ships a £3.59 shelf price.

## 4. Target audience and content

| Question | Answer |
|---|---|
| Target age groups | **18 and over** only |
| Is your app designed for children? | **No** |
| Could it unintentionally appeal to children? | **No** — no game mechanics, no characters, no cartoon art; the icon is signal bars, the content is latency and throughput figures |
| Store presence for children | Not applicable |

**Why 18+ and not 13+.** Both avoid the Designed for Families programme, and the
app would comply with the Families policy comfortably (no ads, no data
collection, no UGC). 18+ is chosen because it is the honest description of who
this is for — people diagnosing their own broadband or mobile connection — and
because it keeps the app out of the Families policy surface entirely. Note this
is orthogonal to the content rating, which is **Everyone**; a broadly-rated app
targeted at adults is normal and correct. If the founder prefers wider reach,
13+ is defensible and changes nothing else on these forms.

Other App content declarations:

| Declaration | Answer |
|---|---|
| News app | **No** |
| COVID-19 contact tracing or status | **No** |
| Government app | **No** |
| Financial features | **None of these** — a one-off IAP is not a financial feature |
| Health apps | **No** |
| Data safety | see §1 |
| App access (login credentials) | **All functionality is available without special access.** There is no account, no sign-in and no server. Pro features are behind a one-time in-app purchase, not behind credentials, so no reviewer login is needed. |

## 5. Content rating — IARC questionnaire answer sheet

Expected outcome: **Everyone** (IARC), matching **4+** on the App Store.

Questionnaire category: the **non-game** questionnaire — "All other app types"
(the console sometimes words it "Utility, Productivity, Communication or Other").
**Do not pick a Games category**; the questionnaire branches differently and the
answers below will not match.

| Question | Answer |
|---|---|
| Violence — realistic, fantasy, or against humans/animals | **No** |
| Sexual content, nudity, suggestive themes | **No** |
| Profanity or crude humour | **No** |
| Controlled substances — drugs, alcohol, tobacco | **No** |
| Gambling — real or simulated, casino themes | **No** |
| Horror, fear, disturbing content | **No** |
| Discrimination or hate content | **No** |
| Does the app allow users to interact or exchange content? | **No** — no accounts, no messaging, no comments, no sharing, no UGC of any kind |
| Does the app share the user's physical location with other users? | **No** — the app never reads location |
| Does the app allow users to purchase digital goods? | **Yes** — one non-consumable unlock at £2.99 |
| Does the app provide unrestricted access to the internet (e.g. a built-in browser or search)? | **No** — there is no browser and no WebView. The only links (privacy policy, support) hand a fixed URL to the user's own browser |
| Does the app contain user-generated content or user-to-user communication? | **No** |
| Miscellaneous — does it share user data with third parties for advertising? | **No** |

Contact email for the IARC certificate: `info@froggyeye.com`.

## 6. Foreground service permissions declaration — REQUIRED, and it needs a video

`FOREGROUND_SERVICE_SPECIAL_USE` triggers Play Console's **App content →
Foreground service permissions** declaration. This is mandatory and will surface
as a release-preview error until it is filed. It asks for the permission's
purpose **and a link to a video demonstrating the feature** — see the blocker in
§9, because no such video exists yet.

**Manifest subtype string (already in the binary as
`android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE`) — paste verbatim:**

> Continuously measures real network throughput and latency so the live
> connection-quality indicator in the status bar stays accurate while the app is
> not open. The measurement must run on the user's own schedule and cannot be
> deferred to a background job without the indicator going stale.

**Supporting justification, for the declaration's description field:**

> The foreground service's only output is the status-bar notification the user
> explicitly switched on: the notification's small icon *is* the live 0-5
> connection score, so the service and the user-visible feature are the same
> thing. It does no work at all while the app is in the foreground — the UI
> isolate publishes its readings to the service under a renewable lease, so the
> two never measure in parallel and no data is spent twice. Its interval is
> user-controlled (5 minutes by default, 1-60 minutes on Pro) and clamped to a
> 30-second floor, and its total data cost is hard-capped by a user-visible daily
> budget shown on the home screen. The user can switch the indicator off at any
> time, which stops the service.

**Why `specialUse` and not `dataSync`** (state this if Play pushes back, which is
the most likely rejection on this app): from Android 15 a `dataSync` foreground
service is capped at **6 hours per day**. A persistent connection indicator that
dies part-way through every day — silently, at a different time depending on
usage — is worse than no indicator, because the user cannot distinguish "the
indicator stopped" from "the connection is fine". No other declared FGS type
describes continuous user-requested network measurement. `specialUse` is the
correct type, not a convenience.

## 7. `SYSTEM_ALERT_WINDOW` justification

There is **no App content declaration form for "Display over other apps"** —
unlike the FGS types, Play has no console questionnaire for it. This text exists
for two purposes: to answer any policy correspondence, and because the same
argument is what the in-app `/settings/overlay` screen tells the user before it
offers the system settings link. Source: `PRODUCT_SPEC.md` §9.

> The optional floating bubble draws the live connection score over other apps,
> so the user can watch the real signal *while using the app that is struggling*
> — which is the only moment the information is useful. It is constrained as
> follows. It is a **Pro feature and off by default**, so it can never appear on
> a fresh install. It **requires the status-bar indicator to be on**, because
> that service supplies its live score; the app stops the overlay rather than
> showing a stale bubble. **The permission is never requested until the user
> turns the feature on**, on a dedicated screen that explains what will be drawn
> before offering the system settings link, and Android's grant is revocable
> there at any time — the service re-checks it on every start. The bubble is
> about **44 dp**, roughly a status-bar icon, and semi-transparent. It is
> `FLAG_NOT_FOCUSABLE`, so it never takes input from the app underneath except
> on the bubble itself; keyboards and gestures behave normally. Drag to move, tap
> to open Honest Signal, long-press to switch it off without opening anything. It
> displays only the score: no ads, no promotions, no content from anywhere else,
> and it never overlays a system permission dialog.

## 8. Declarations that must NOT be filed, and why

Filing a declaration for a permission the app does not hold is a rejection risk
in its own right, and each of these has its own console form that must be left
alone:

| Form | Leave it | Because |
|---|---|---|
| Exact alarm (`USE_EXACT_ALARM` / `SCHEDULE_EXACT_ALARM`) | Not filed | Neither permission is in the merged manifest. Nothing in this app schedules an alarm or a local notification; the one ongoing notification is the foreground service's own. |
| Full-screen intent (`USE_FULL_SCREEN_INTENT`) | Not filed | Not in the manifest. The notification is `IMPORTANCE_LOW`, silent and ongoing. |
| Photo and video permissions (`READ_MEDIA_IMAGES` / `_VIDEO`) | Not filed | Not in the manifest; no media, camera or file picker anywhere in the app. |
| All files access (`MANAGE_EXTERNAL_STORAGE`) | Not filed | Not in the manifest. |
| Package visibility (`QUERY_ALL_PACKAGES`) | Not filed | Not in the manifest. |
| Accessibility / VPN / device admin | Not filed | No such service is declared. |
| SMS or Call Log | Not filed | No such permission. |
| Advertising ID | **Declared as not used** (§3) | No `AD_ID` permission, no ad SDK. |

## 9. Predicted release-preview blockers and open items

1. **The FGS declaration video (§6) does not exist.** Play asks for a link to a
   video showing the foreground service feature in use. This needs a short screen
   recording of the status-bar indicator updating with the app closed, hosted
   somewhere durable (unlisted YouTube is the usual choice). It cannot be
   captured on an emulator convincingly and it is the single most likely thing to
   stall the Play submission. Not an App Store issue.
2. **No upload keystore exists yet** — `android/upload-keystore.jks` and
   `android/key.properties` have not been generated, so a release build currently
   falls back to debug signing. The Gradle config is already wired for the house
   pattern (house-facts #7).
3. **The IAP product does not exist on Play yet.** Creating it requires a
   billing-permission artifact **active in some track** (internal counts; a draft
   does not) — house-facts #18. Feed the price as **£2.4917** ex-VAT.
4. **Privacy policy is a raw-Markdown URL.** It is the house convention
   (house-facts #5) and it returns 200, but raw GitHub Markdown renders as plain
   text and has been treated as a rejection risk on both stores in this
   portfolio. The blessed alternative is the GitHub Pages HTML variant. Changing
   it is **not** a metadata-only edit: `AppConstants.privacyPolicyUrl` is compiled
   into the binary and asserted in `test/release_invariants_test.dart`, so it is a
   code change and a rebuild. Flagged for stage 6 (compliance) to rule on.
5. **Store listing locale.** The Play record was created **en-GB**. Write release
   notes for exactly the locales the listing has — house-facts #19: notes for a
   locale the listing does not have are accepted by the API and silently never
   shown, and the phantom locale pollutes later reads. `GET /edits/<id>/listings`
   before uploading.
6. **Not verifiable without hardware** (carried from stages 1 and 4a, and
   relevant if Play review asks): the background Flutter engine booting inside
   the service, the notification small icon rendering across OEM skins, and the
   overlay window's behaviour all need a real device.
