# Honest Signal — ASO, category and launch pricing

> **Renamed 2026-08-09, after this document was written.** The brand term is now
> **Honest Signal** (two words) and every occurrence below has been updated to
> it; the store title is **"Honest Signal: Network Quality"** (30 chars). The
> tagline **"Bars that don't lie."** is unchanged, and the keyword field, short
> description and categories stand exactly as decided here.
>
> `TrueSignal` (one word) in this document is always the **rival** app —
> `id6760624783`, David Schwind — never us. Do not "correct" it.

Stage 5 artifact (part 1). Written by growth-monetization, 2026-08-09.
Consumed by **release-manager** (writes the store text into
`ios/fastlane/metadata/` and `android/fastlane/metadata/android/`) and
**store-publisher** (uploads it, orders the screenshots, sets the price).

Inputs read: `docs/PRODUCT_SPEC.md`, `store_assets/BRAND.md`,
`store_assets/screenshot_specs.md`, `PIPELINE.md`, plus live store data pulled
2026-08-09 (iTunes Search/Lookup API for the App Store, Play listing pages).

Locked, not relitigated here: the name **Honest Signal**, the price **£2.99**,
iPhone-only on iOS, product ID `com.froggyeye.honestsignal.pro` (verified in
`lib/features/purchases/data/purchase_controller.dart:21`).

---

## 0. Stage-0 live check — what the stores actually say today

| Check | Result (2026-08-09) |
|---|---|
| App Store listing for `com.froggyeye.honestsignal` | `resultCount 0` — not live. Record exists (Apple ID `6799269422`), no published version. |
| App Store lookup by Apple ID `6799269422` | `resultCount 0` — consistent with the above. |
| Play listing for `com.froggyeye.honestsignal` | **HTTP 404** — record exists (app ID `4972146908238602643`), nothing published. |

So this is a genuine first launch on both stores, free-to-free, with no
paid→free conversion problem and no grandfathering requirement. Nothing in the
plan below is irreversible except the two called out in §7.

### The finding that changes the plan

**An App Store app called `TrueSignal` already exists, with our exact
positioning.**

| | Ours | Theirs |
|---|---|---|
| Name | Honest Signal (two words) | TrueSignal (one word) |
| Store ID | Apple ID 6799269422 (unpublished) | `id6760624783` |
| Publisher | Froggy Eye Ltd | David Schwind (indie) |
| Released / last updated | — | 2026-03-20 / **2026-08-05** (four days ago — actively developed, v3.0.5) |
| Model | Free + £2.99 one-time Pro | Free + Pro |
| Ratings (GB) | — | **0** |
| Category | Utilities (proposed) | Utilities + Productivity |
| Tagline | "Bars that don't lie." | **"TrueSignal: bars lie. This doesn't."** |

Their description opens *"TL;DR Your bars lie. TrueSignal measures the
connection you ACTUALLY have."* That is our product thesis, near-verbatim,
shipped five months ago.

**Superseded 2026-08-09 — as written this section concluded "this does not block
the launch, and the name stays", on the reasoning that Apple's uniqueness check
is on the exact string and that after five months the rival has zero ratings.
The founder overrode that and renamed the app to Honest Signal instead, for
clear water rather than a defensible-but-contested name.** The three
consequences below were written about the old name and still hold, because they
are about *their* brand term, not ours:

1. **Do not spend scarce metadata fighting for our own brand term.** A search for
   "true signal" on the App Store returns *their* app. We will not out-rank a
   five-month-old exact-string match on that query at launch, and trying would
   burn the title and keyword field on a term that converts almost nobody
   (brand search only matters once a brand exists). Brand traffic is won off-store
   — via `honestsignal.froggyeye.com` and direct links — not via ASO. Every
   character of the keyword field goes to *category* terms instead.
2. **Differentiate on mechanism, not on attitude.** "The bars lie" is now a
   contested claim, not a distinctive one. What is genuinely ours is *how* the
   number is produced — see §1.
3. **Keep their exact strings out of our metadata.** Specifically: never write
   "bars lie" (their literal tagline) and never write `TrueSignal` unspaced
   anywhere in our store text, screenshots or website copy. Our own
   `BRAND.md` line, "Bars that don't lie", is distinct and stays.

**Founder decision — made 2026-08-09.** This was flagged as a
trademark/brand-comfort call reserved for the founder, with a recommendation to
proceed under the old name after a register search. The founder instead chose to
rename to **Honest Signal**, which removes the question rather than answering it:
the string no longer resembles the rival's, so there is nothing to search the UK
IPO / USPTO registers *for* on this axis. Retained as the record of why the
rename happened.

### The differentiator that survives contact with them

They are **ping-only**: *"Real-time ping-based connection monitoring"*. We send
four latency probes **and a real 120 KB transfer sample**, and we cap the
displayed score at 2 bars when probes answer but the transfer will not complete
(`PRODUCT_SPEC` §5, transfer-failure cap).

That case — a link that replies to pings while no data moves — is *exactly* the
"full bars, no data" failure both apps claim to expose, and a ping-only tool
reports it as healthy. This is the one claim we can make that they cannot, it is
true, it is verifiable in our own "How the score works" screen, and it is the
spine of the store copy. Use it. It also justifies the price: they charge for
alerts and webhooks; we charge for history and an always-on indicator.

---

## 1. Keyword research

Method: pulled the live top-8 App Store results per term (GB storefront) with
rating counts as the competition proxy, and the live Play SERP per term. Terms
are graded on **intent × winnability**, not volume alone — a term we can rank for
but that attracts the wrong user is worse than no ranking, because this app has
no ads and lives on a one-time purchase, so a bouncing install is pure cost.

### App Store — the field, measured

| Term | Top competitors (rating count) | Verdict |
|---|---|---|
| **network quality** | Internet Quality (1), CRC Network Quality (0), Network Utility (43), Network Analyzer Pro (1,781) | **Target — primary.** Astonishingly soft for a term that literally describes the product. |
| **ping** | Ping – network utility (35), Ping – Network Tools (5), Ping Test+ (0) | **Target.** Near-empty field, exact function match. |
| **jitter** | no dedicated app in the top results | **Target.** Zero competition, perfect intent, low volume. |
| **connection test** | Speedtest (4,997), Opensignal (2,783), Speedcheck (11,688) | Contested but reachable long-tail via combination. |
| **network monitor** | Fing (16,829), Network Analyzer (1,368) | Long-tail only; Fing owns the head. |
| **signal strength** | Opensignal (2,783), Wifi Analizer (2,543), Wifi Signal Strength Meter (597) | **Deliberately excluded — see below.** |
| **internet speed test** | SpeedSmart (38,811), SpeedChecker (24,301), Speedcheck (11,688), Speedtest (4,997) | **Unwinnable.** Do not spend a character on the head term. |
| **dead zone** | DEAD TARGET (6,408), Into the Dead 2 (7,960), DEAD TRIGGER 2 (12,071) | **Polluted — excluded.** See below. |

Two exclusions worth writing down because they are counter-intuitive:

- **"dead zone" is a zombie-shooter query on the App Store.** The entire top-8
  is games with thousands of ratings each. It was on the brief's candidate list;
  it is unusable on iOS. (It behaves normally on Play, where the SERP is network
  tools — but see §2 for why it still does not earn a slot there.)
- **"signal strength" is an intent trap.** We would rank respectably, but people
  searching it want **dBm and radio readings**, which this app deliberately does
  not provide — the entire premise is that radio strength is the wrong number.
  Ranking for it buys installs that bounce and one-star reviews reading "doesn't
  show dBm". The same logic excludes "reception" and "coverage". Our brand word
  "Signal" is indexed from the title anyway, so we get the incidental long-tail
  without chasing the mismatched head.

### Paid comparables (price sanity, GB storefront)

Network Analyzer Pro **£3.99** · Antenna Finder **£0.99**. Everything else in the
measured set is free with IAP. £2.99 sits just under the established paid
utility in the category — a defensible position, not an outlier.

### Play — the field, measured

Every competitor pulled returns `applicationCategory: TOOLS`:
Signal Strength (`com.cls.networkwidget`), NetSpeed Indicator
(`com.nisargjhaveri.netspeed`), Network Monitor Mini Pro
(`info.kfsoft.android.TrafficIndicatorPro`), Opensignal, Pingmon, PingTools,
Network Analyzer Pro, Network Cell Info Lite, Netmonitor.

The important read: **status-bar indicator apps already exist on Play, and none
of them shows connection *quality*.** NetSpeed Indicator and Network Monitor
Mini Pro put **bytes/sec throughput** in the status bar; Signal Strength puts
**radio dBm** there. A live 0–5 *honest quality score* in the status bar is an
unoccupied slot, and it is our free-tier headline feature. Play copy should lean
on it much harder than iOS copy can.

---

## 2. Store metadata — recommended fields

All lengths verified programmatically against each store's limit.

### App Store

| Field | Value | Len |
|---|---|---|
| **Title** (≤30) | `Honest Signal: Network Quality` | **30 — exactly at the limit** |
| **Subtitle** (≤30) | `Speed, latency and packet loss` | 30 |
| **Keywords** (≤100) | `wifi,ping,jitter,test,monitor,meter,connection,internet,bandwidth,5g,checker,stability,dropout,4g` | 97 |

**Title.** The brand word "Signal" already indexes the whole signal family, so
the 15 spare characters go to the softest high-intent term found — "Network
Quality" — rather than repeating a word we already own. Do not append "Meter" or
"Checker"; both are cheaper to buy from the keyword field, where they cost 6–8
characters instead of 8 title characters at title weight.

**Subtitle.** This is the one place a spec list beats a slogan, and the reason is
specific: the subtitle sits directly above screenshot 1, whose headline is
already *"Full bars. No data."* The emotional hook is therefore delivered by the
artwork a centimetre below, and the subtitle's remaining job is the thing
artwork cannot do — index terms and prove technical substance to a user
comparing us against Opensignal. Four real measurements in thirty characters
does that, and it is on-brand per `BRAND.md` ("plain, specific, unhurried. Real
units."). The alternative, `Bars that don't lie` (19 chars), was rejected: it
indexes nothing, wastes 11 characters, and echoes the competitor's literal
tagline.

**Keywords.** No term repeats a word in the title or subtitle (verified — Apple
combines across fields, so `test` + subtitle `Speed` yields "speed test" free,
`meter` + title `Signal` yields "signal meter", `monitor` + title `Network`
yields "network monitor"). Three characters are left deliberately unused rather
than padded with a mismatched term. `stability` is in because it is what we
actually measure and it matches how users describe the problem; `checker`
combines broadly and carries no radio-mismatch risk.

### Google Play

| Field | Value | Len |
|---|---|---|
| **Title** (≤30) | `Honest Signal: Network Quality` | **30 — exactly at the limit** |
| **Short description** (≤80) | `Bars that don't lie: a real connection score, live in your status bar.` | 70 |

**Why the same title on both stores.** Play indexes the long description
generously, so the Android-specific terms ("status bar", "indicator", "floating",
"overlay", "background") can be earned there at no title cost. The title is the
scarcer surface and should carry the broad category term on both stores. Keeping
the strings identical also keeps the froggyeye.com page, the two listings and
the app's own display name in one voice — which matters more than usual given a
same-name app exists on one of the two stores.

Rejected Play alternative: `Honest Signal: Status Bar Meter` (29). It buys the
Android hero term in the title, but the long description buys it more cheaply,
and a store-specific title makes the brand look unsettled.

**Short description.** Carries the brand line *and* the Android differentiator in
70 characters. This field is indexed and is the only text most Play users read.

### Play long description — keyword angles for release-manager

I am not writing the description (that is release-manager's field), but these are
the angles and the density guidance:

1. **Open with the mechanism, not the attitude.** First paragraph should contain
   "connection quality", "latency", "throughput" and the transfer-sample claim.
   Given a same-pitched competitor exists, the differentiator has to be in the
   first two lines, not paragraph four.
2. **"Status bar" belongs in the description 2–3 times, naturally** — it is the
   Android-only hero, it is free, and no Play competitor occupies the
   quality-score-in-the-status-bar slot. Pair it with "indicator" and
   "notification icon".
3. **The honest-method angle.** "Every weight and threshold is written down, in
   the app" — links to the "How the score works" screen. Also picks up
   "how it works", "score", "method".
4. **The data-cost angle.** "A latency probe costs about 2.8 KB" / "hard daily
   data budget you can see". This is a real differentiator against speed-test
   apps that burn 200 MB, and it picks up "data usage", "data budget", "mobile
   data".
5. **The what-it-is-not paragraph.** "This is not a speed test." Names the
   category honestly, sets expectation, and reduces the refund/one-star risk from
   users arriving on speed-test-adjacent queries.

Terms to work in naturally across the description: *connection quality, network
quality, latency, jitter, packet loss, throughput, ping, wifi, mobile data, 5G,
status bar, indicator, dropout, outage, network monitor, connection test,
stability*.

Terms to keep **out** of all Play and App Store text: any competitor or carrier
brand name, `TrueSignal` (unspaced), "bars lie", "fastest", "#1", "best",
"guaranteed", and any claim of background measurement on iOS (`BRAND.md` copy
rules; the last one is a factual rejection risk — the app itself says iOS stops
measuring when closed).

---

## 3. Category recommendation

| Store | Recommendation | Evidence |
|---|---|---|
| **App Store** | **Primary: Utilities. Secondary: Productivity.** | Every measured network meter in the top results is Utilities — Opensignal, Speedtest, SpeedChecker, Network Analyzer Pro, Wifi Analyzer, the Ping utilities. The handful that chose Productivity (Fing, UniFi, iWifi) are network *management and inventory* tools, not meters — a different job. Productivity as secondary costs nothing and matches what the same-named competitor chose. |
| **Google Play** | **Tools.** | All nine Play competitors pulled return `applicationCategory: TOOLS`. Play's Productivity category is for notes/office/launcher apps; a connection meter filed there would sit among the wrong neighbours and lose the category browse traffic entirely. Play has no secondary category. |

---

## 4. Screenshot order

The six captures and their headlines are fixed in
`store_assets/screenshot_specs.md`. What follows is the **marketing order per
store**, which differs from that file's single global ordering — release-manager
should treat this section as authoritative for ordering and
`screenshot_specs.md` as authoritative for content, framing and copy.

### App Store — 4 shots

| Pos | Shot | Headline |
|---|---|---|
| 1 | `00_onboarding` | "Full bars. No data." |
| 2 | `01_home` | "See what it can actually do" |
| 3 | `04_how_it_works` | "No mystery score" |
| 4 | `02_history` (Pro badge) | "Prove the drop-outs are real" |

**Change from `screenshot_specs.md`:** history moves from position 3 to 4, and
how-it-works moves up. Reason: the App Store shows roughly the first three shots
in search results, and on **iOS the free tier is thinner than on Android** — no
status-bar indicator, no overlay, both being Android-only — so iOS Pro is
history, intervals and themes. Putting a Pro-badged screenshot in the third
search-visible slot on the platform with the thinner free tier reads as
"paywalled app" at exactly the moment a browsing user decides whether to tap.
The how-it-works shot is free, and it answers the top objection to a claim like
ours — *"how would it know?"* — which is the question a user asks after seeing
shot 2, not after seeing a chart.

### Google Play — 5 shots

| Pos | Shot | Headline |
|---|---|---|
| 1 | `00_onboarding` | "Full bars. No data." |
| 2 | `03_settings` **(Play only)** | "A live score in your status bar" |
| 3 | `01_home` | "See what it can actually do" |
| 4 | `04_how_it_works` | "No mystery score" |
| 5 | `02_history` (Pro badge) | "Prove the drop-outs are real" |

**Change from `screenshot_specs.md`:** the status-bar shot moves from position 3
to 2. Reason: Play surfaces about three shots in search, and this is the only
feature in the set that **no Play competitor offers** — the existing status-bar
apps show bytes/sec or dBm, not a quality score (§1). It is also free, so it
sells the free tier rather than the paywall. The Play search-visible three then
read as problem → the solution nobody else has → the proof.

### Excluded from both marketing sets

`05_pro` (paywall). Still captured, still required — it is App Store Connect's
**IAP review screenshot**. It renders a `£2.99` label, and a GBP figure baked
into artwork is wrong on every other storefront (`screenshot_specs.md` §3).

**Reminder carried forward for store-publisher:** the marketing set must come
from a **`pro`-tier capture** (no `SCREENSHOT_TIER=free`), or shot 5 frames a
`ProLock` panel under a headline promising a chart. `render.sh` now refuses this,
but the failure has happened once already.

---

## 5. Age rating

**Expect 4+ (App Store) and Everyone (Play IARC).** Both should fall out of the
questionnaires with every content answer set to none.

Supporting facts, all from `PRODUCT_SPEC.md` §10 and the stage-4 audits: no
user-generated content, no messaging, no ads, no web browser or unrestricted web
access, no social features, no accounts, no location, no gambling, no data
collection at all.

Two questionnaire answers that are *not* content-rating questions but sit on the
same forms and must be right — release-manager and the compliance stage own
these, flagged here so they are not missed:

- **Play "Contains ads" = No**, **"In-app purchases" = Yes** (£2.99–£2.99 range).
  There is no `google_mobile_ads` dependency in this app.
- **Data safety / privacy nutrition label = "No data collected"**, with the
  caveat that `PRIVACY_POLICY.md` already discloses honestly: the probe endpoints
  (Google and Cloudflare connectivity-check URLs) necessarily see the originating
  IP, as any web request would. That is not app-collected data, but the
  compliance auditor should confirm the wording rather than inherit my read.

---

## 6. Launch pricing within the locked £2.99

The price is settled. This section is the *mechanics* of applying it, and the
mechanics have bitten this portfolio before.

### Setting it

| Store | Action | Watch out |
|---|---|---|
| **App Store** | Set the IAP `com.froggyeye.honestsignal.pro` with **GBP as base currency at £2.99**, and accept Apple's automatic per-storefront prices. | Preview the full price schedule in ASC before saving — it lists every storefront, and it is the only place a bad conversion is visible. |
| **Play** | `convertRegionPrices` takes **tax-exclusive** input. For a £2.99 shelf price with 20% UK VAT, feed **£2.4917** (`2.99 ÷ 1.2`), not `2.99`. | Feeding `2.99` ships a £3.59 shelf price. This is house-facts #18 and it has caught the portfolio before. |

### Price parity across stores — a decision, not a default

**Recommendation: keep Play's honest auto-conversion; do not hand-set round
prices per storefront.** For a *subscription* the odd local number is worth
fixing, because the user re-reads it every month. For a one-time £2.99 unlock
seen once, at this portfolio's volume, per-storefront rounding is recurring
maintenance across 150+ storefronts that buys a rounding aesthetic. Revisit only
if a specific non-UK storefront turns out to drive real volume.

### No discounting mechanics

House style, and it is also the correct call for a product whose entire pitch is
that it does not manipulate you. Explicitly ruled out for launch: introductory
pricing, limited-time discounts, struck-through anchor prices, and any countdown
on the paywall. Apple's promotional offers are subscription-only and therefore
moot. Play promo codes are acceptable **only** as a small reviewer/press
allocation, never as a public discount.

The paywall already does the right thing — it names each Pro feature and explains
it before the price appears (`PRODUCT_SPEC.md` §11), and the price is read from
the store rather than hardcoded, so it is correct on every storefront.

### Unit economics, for reference

£2.99 shelf → **£2.49** ex-VAT → **~£2.12 net** at the 15% Small Business Program
rate (Froggy Eye Ltd qualifies on both stores). At the standard 30% rate it would
be ~£1.74. Confirm SBP enrolment is active on both accounts before modelling
anything on the 15% figure.

### What the price has to clear

Nothing, at launch — there is no marginal cost per user. The app has **no
backend, no accounts, no AI inference and no per-measurement cost to us**; the
probes are paid for by the user's own data allowance and hard-capped by the
in-app budget. That is unusual for this portfolio and it means the only real
constraint on pricing is perceived value, not margin. £2.99 against a £3.99
category comparable (Network Analyzer Pro) is well judged.

---

## 7. Irreversibles and risks

**Irreversible — needs the founder to proceed knowingly:**

1. ~~**Publishing under the name "True Signal" while `TrueSignal` exists on the
   App Store** (§0). Renaming after launch costs the listing's accumulated
   ranking and every inbound link. Recommendation: proceed, after a register
   search.~~ **RESOLVED 2026-08-09** — the founder took the stronger option and
   renamed the app to **Honest Signal** before launch, so nothing has accumulated
   to lose. This entry is kept struck through rather than deleted because it is
   the reasoning that produced the rename.
2. **Play free → paid can never be reversed.** Not applicable here — the app
   launches free with an IAP on both stores, which is the correct and reversible
   shape. Recorded so a future "just make it paid" suggestion is checked against
   it.

**Risks to manage:**

- **Intent-mismatch reviews.** The most likely one-star review is "doesn't show
  signal strength / dBm". Mitigated by excluding radio terms from the keyword
  field (§1) and by the "this is not a speed test" paragraph (§2), but it will
  still happen occasionally. The reply template should point at "How the score
  works" rather than argue.
- **iOS background expectation.** Users will expect the score to update while the
  app is closed, because Android's does. The app is honest about this in-app;
  the store copy must never imply otherwise, and the iOS widget + BGTaskScheduler
  work (`PRODUCT_SPEC.md` §3, "Later") is the real fix.
- **The competitor ships fast.** v3.0.5 in five months, updated four days ago.
  Assume they will add a transfer sample once they notice. The durable moat is
  not the measurement, it is the published method and the Android status-bar
  indicator — invest there.
- **Play `specialUse` foreground-service declaration and the
  `SYSTEM_ALERT_WINDOW` justification** are still outstanding console work
  (`PRODUCT_SPEC.md` §9 has the approved text). A rejection here delays the Play
  launch, not the App Store one.

---

## 8. Growth beyond the listing (short notes; ASO is the main channel)

This is a no-ads, no-tracking, one-time-purchase indie utility, so paid
acquisition is off the table and ASO plus community is the whole plan.

- **Highest leverage: the froggyeye.com page** at `honestsignal.froggyeye.com`.
  It should carry the scoring method in full — the weights table, the thresholds,
  the caps. That page is the only asset that can rank on Google for "why do I
  have full bars but no internet", which is the actual question our users type,
  and it is a question no app listing can rank for. This is worth more than any
  keyword tweak.
- **Where this audience already is:** r/NoContract, r/mobilenetwork, r/HomeNetworking,
  r/UKMobileNetworks, r/tmobile / r/EE-adjacent carrier subs, and ISP complaint
  threads. The honest posture — publishing the method, admitting the iOS
  background limit — is what plays well there; a launch post that leads with the
  method and the data cost will land, one that leads with the app will not.
- **Retention:** the Android status-bar indicator *is* the retention mechanism —
  a permanently visible, useful, silent notification. No streaks, no engagement
  notifications, and no local-notification campaigns; the app posts exactly one
  ongoing notification and should never post another (`PRODUCT_SPEC.md` §9).
  On iOS there is no equivalent hook until the widget ships, which is the
  strongest argument for prioritising the WidgetKit work.
- **Featuring:** the plausible angle is Apple's and Google's periodic
  privacy/utility collections. What makes this app featurable is the published
  scoring method and the "No data collected" label on an app that measures the
  network — worth saying explicitly in the App Review notes.

---

## 9. Handoff summary for release-manager

| Item | Value |
|---|---|
| App Store title | `Honest Signal: Network Quality` (28) |
| App Store subtitle | `Speed, latency and packet loss` (30) |
| App Store keywords | `wifi,ping,jitter,test,monitor,meter,connection,internet,bandwidth,5g,checker,stability,dropout,4g` (97) |
| App Store category | Utilities (primary), Productivity (secondary) |
| Play title | `Honest Signal: Network Quality` (28) |
| Play short description | `Bars that don't lie: a real connection score, live in your status bar.` (70) |
| Play category | Tools |
| Age rating | 4+ / Everyone |
| Price | Free app, one-time IAP `com.froggyeye.honestsignal.pro` at £2.99 (Play input: **£2.4917** ex-VAT) |
| iOS screenshot order | onboarding, home, how-it-works, history(Pro) |
| Play screenshot order | onboarding, status bar, home, how-it-works, history(Pro) |
| IAP review screenshot | `05_pro` — excluded from both marketing sets |

Free/Pro gate list is **not duplicated here** — `docs/PRODUCT_SPEC.md` §3 and §11
are authoritative, and a second copy would drift.
