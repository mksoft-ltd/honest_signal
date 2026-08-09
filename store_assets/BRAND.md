# Honest Signal — Brand & Design System

Stage 2 (design) artifact. Written by ui-designer, 2026-08-08.
Source of truth for the palette, typography, icon and store creative. If this
file and the code disagree, this file is wrong — fix it.

Publisher: Froggy Eye Ltd. Studio line: *useful apps, no ads, no dark patterns.*

---

## 1. What the design has to do

Honest Signal's whole claim is **"bars that don't lie"**. Everything visual either
supports that or undermines it:

- **The number must look measured, not decorative.** Tabular figures, plain
  units, a stated timestamp on every reading. No needles, no gauges, no
  animated "scanning" theatre that implies work the app is not doing.
- **The method is on show.** "How the score works" is a first-class screen, not
  a legal footnote, and the store creative sells it as a feature.
- **Nothing is hidden to create pressure.** Pro features are named and
  explained before the price is mentioned; locked screens say what the feature
  does rather than only "upgrade".
- **Honest about limits.** The freshness line and the iOS background caveat are
  UI, not fine print.

Tone: **plain, specific, unhurried.** Short sentences. Real units. No
exclamation marks, no "boost", no "supercharge", no emoji. The app is allowed
one dry joke (the paywall's "check your connection and try again — which,
admittedly, is the whole point of this app") and no more.

---

## 2. Palette

### Brand

| Token | Hex | Use |
|---|---|---|
| Brand green (`AppColors.seed`) | `#1FA97A` | Seeds the Material scheme; the icon and store-creative accent. **Not** a UI foreground. |
| Ink (plate top) | `#12211C` | Icon plate, feature graphic, screenshot backgrounds |
| Ink (plate bottom) | `#08120F` | Gradient end |
| Ink flat | `#0D1915` | Android adaptive-icon background |
| Mint | `#45E0A6` | Store-creative accent text, icon gradient top |
| Slate | `#94A79E` | Store-creative body text on ink |

The app ships no bespoke UI palette beyond the score ramp — surfaces, text and
controls come from `ColorScheme.fromSeed(AppColors.seed)` in both brightnesses,
so the app inherits Material 3's contrast guarantees for free and there is one
fewer thing to keep in step.

### The score ramp

Five colours, 0–5 bars, with 2 and 3 sharing a band because the distinction a
user acts on is *usable vs not*.

**There are two sets, and there has to be.** The ramp is defined per brightness
in `lib/core/theme/app_theme.dart` (`AppColors.light` / `AppColors.dark`) and
reached through `AppColors.of(context)`.

| Bars | Verdict | Dark set | Light set |
|---|---|---|---|
| 0 | No usable connection | `#E0483C` | `#C0271B` |
| 1 | Barely usable | `#E8863B` | `#A85A0A` |
| 2–3 | Slow / Workable | `#D8B22E` | `#8A6B00` |
| 4 | Good | `#4FA83D` | `#357A27` |
| 5 | Excellent | `#1FA97A` | `#0E7A57` |

Same hues throughout; only lightness moves, so the app looks like itself in
either theme.

### Contrast audit (stage 2, WCAG 2.1)

The ramp is not decoration. It carries the verdict headline, the bar mark, the
metric-tile emphasis, the history chart and the onboarding label — so it was
measured against the two surfaces the app actually paints on, not against white.

The single-set palette inherited from stage 1 was tuned for dark and failed on
light, including on the bar mark that leads the store screenshots:

| Token | Old hex | on `surface` #F5FBF5 | on `surfaceContainerLow` #EFF5EF | Verdict |
|---|---|---|---|---|
| dead | `#E0483C` | 3.87 | 3.68 | fails 4.5 as tile emphasis |
| poor | `#E8863B` | 2.53 | 2.40 | fails 3.0 and 4.5 |
| fair | `#D8B22E` | 1.94 | 1.84 | fails 3.0 |
| good | `#4FA83D` | 2.86 | 2.71 | fails 3.0 |
| great | `#1FA97A` | 2.85 | 2.71 | fails 3.0 |

Replaced with, on the same two surfaces:

| Token | New hex | on #F5FBF5 | on #EFF5EF |
|---|---|---|---|
| dead | `#C0271B` | 5.64 | 5.35 |
| poor | `#A85A0A` | 4.84 | 4.59 |
| fair | `#8A6B00` | 4.78 | 4.54 |
| good | `#357A27` | 5.04 | 4.79 |
| great | `#0E7A57` | 5.08 | 4.82 |

Every light value clears **4.5:1** on both surfaces, which covers the small-text
uses (metric-tile emphasis at 16 px/w600; the onboarding label at 11 px/w700) as
well as the 3:1 non-text floor the bars, the chart swatches and the 24 px verdict
headline need.

The dark set was already 4.21–9.09 on `#0F1511`/`#171D1A` and is unchanged —
which matters, because `SignalBubbleView.colourFor` in Kotlin is a copy of it.

### Where a colour is allowed to mean something

A score colour is never the *only* carrier of meaning. The bar count, the
verdict word and the numeric metrics all say the same thing, so the app is
usable with any form of colour blindness and in greyscale — which is also how
the Android status-bar icon renders, since the system tints small icons itself.

---

## 3. Typography

No bespoke font ships. The platform face (Roboto on Android, SF on iOS) via
Material 3's default `textTheme` — it is the most legible option at small sizes
on each platform, it costs nothing in binary size, and it keeps the app looking
native, which suits a utility that lives next to the OS status bar.

| Role | Style | Notes |
|---|---|---|
| Screen title | `titleLarge` w600 | AppBar, no centre-align |
| Verdict | `headlineSmall` w700 | Tinted by the score ramp |
| Section header | `labelSmall` w700, +1.1 letter-spacing, uppercase, `primary` | Settings only |
| Card/step title | `titleSmall` w600 | |
| Body | `bodyMedium` | `onSurface` |
| Secondary body | `bodySmall` / `bodyMedium` on `onSurfaceVariant` | Captions, explanations |
| Metric value | `titleMedium` w600, **tabular figures** | |

**Tabular figures are mandatory on any figure that updates in place** — metric
values, stat rows, the weight percentages and the daily-budget counter. Without
them a number re-rendering every few seconds shuffles sideways and the app looks
unstable, which is precisely the impression this product cannot afford.

Store creative uses **SF Pro Display** (the macOS render host's system face) at
w700 for headlines and w400 for body.

## 4. Shape, spacing and elevation

| Token | Value | Applies to |
|---|---|---|
| `AppRadius.pill` | 999 | Progress tracks (budget meter, weight bars) |
| `AppRadius.control` | 14 | Buttons, metric tiles, banners, swatches |
| `AppRadius.card` | 18 | Cards |
| `AppSpacing.page` | `20, 12, 20, 32` | Every scrolling screen's padding |

Onboarding keeps a wider `28` gutter: it is the one screen of centred prose, and
centred text wants a narrower measure.

**Tiles size to their content, never to a `childAspectRatio`.** A ratio is a
guess about height expressed in units of width, so it only holds at the width it
was chosen for: the home metric grid's `1.85` gave each tile 71.6 dp of content
box at 411 dp wide against the 80 dp it needs, and lowering it far enough to
clear a 411 dp phone still overflowed a 360 dp one. The grid is now rows of
`IntrinsicHeight` + `Expanded`, which also survives accessibility text scaling —
verified clean at 360/393/411/430 dp and at 1.0×/1.3×/1.6× text scale. Any future
tile grid should follow the same rule.

**Elevation is drawn, not tinted.** Material's tonal elevation is effectively
invisible in the light scheme — `surfaceContainerLow` measures **1.03:1** against
`surface` — so cards and metric tiles carry a hairline
`outlineVariant @ 70%` border as well as the fill. The same border is applied in
dark, so both themes read as one design rather than two.

The Android launch window uses `@color/window_background`
(`#F5FBF5` light / `#0F1511` dark) instead of the template's hardcoded white, so
a dark-themed phone no longer flashes white on every cold start. It lives in its
own `values*/window_background.xml` because `flutter_launcher_icons` owns
`colors.xml`.

---

## 5. The icon

**Concept: bars, verified.** Five ascending signal bars occupy the lower-right of
the plate; ascending bars leave an empty upper-left triangle, and a bold white
tick sits in it. Two shapes, no badge, no overlap.

Why this and not something else:

- It has to say *connectivity* instantly, and the ascending-bar cluster is the
  one glyph that does that in every market — but drawn alone it would be the OS
  status-bar icon, which the store will not thank us for. The tick is the whole
  differentiator, and it is also the product claim: this reading is checked.
- The tick and the bars never touch, so the mark survives Android 13's
  monochrome themed-icon path as a single readable silhouette.
- No wordmark, no gloss, no carrier-style waves.

| Element | Spec |
|---|---|
| Plate | Vertical gradient `#12211C` → `#08120F` (flat `#0D1915` for the adaptive background) |
| Bars | One gradient **across the cluster**, `#189C70` → `#45E0A6`, so the ascent itself brightens. Per-bar gradients make all five identical and the ramp vanishes. |
| Tick | `#FFFFFF`, 76-unit round-capped stroke |
| Mark span | 74% of the plate |

Sources and the regeneration recipe: `store_assets/icon/` (`build_icon.py` emits
the SVGs, `render.sh` rasterises them, `dart run flutter_launcher_icons` wires
them in). See `store_assets/README.md` for the two generator quirks that must be
reverted after every regeneration.

**Adaptive-icon coverage** is computed rather than eyeballed, because this mark
has content at opposite corners and an empty bounding-box centre:

```
0.68 * r_source <= (SAFE_DP / 108) / 2
coverage = (SAFE_DP/108) / 0.68 * half_span / max_radius
```

with `max_radius` the distance from the mark's centre to the farthest *drawn*
point. At `SAFE_DP = 58` that gives **0.644**. For a circular mark the same
algebra returns ~0.78, which is the check that it is right. `render.sh` emits
`preview_adaptive.png` (the foreground at the 16% inset inside the round mask)
and `preview_48.png` — look at both before believing the arithmetic.

---

## 6. Store creative

### Play feature graphic — 1024 × 500

`store_assets/feature_graphic/`. Ink gradient plate with a soft green radial
lift; the bare mark at 208 px on the left; to its right **"Honest Signal"** at
72 px w700 white, **"Bars that don't lie."** at 34 px in mint `#45E0A6`, and
**"Measures the connection, not the radio."** at 25 px in slate `#94A79E`.

The title is `white-space: nowrap` on purpose. At the original 82 px the
two-characters-longer name silently reflowed to two lines, stranding "Signal"
on its own and unbalancing the block against the mark; the gutter, the gap and
the mark all gave up a little width to hold one line. Nowrap means a future
name that does not fit fails as a visible overflow instead of quietly
rewrapping.

Nothing meaningful sits in the outer 100 px — Play crops this asset on some
surfaces. `render.sh` emits `proof_crop.png` with those margins shaded; look at
it rather than assuming.

### Screenshots

Framing template, shot list, headline copy and the per-shot app state:
**`store_assets/screenshot_specs.md`** and `store_assets/screenshots/`.

Two rules that constrain the copy, both learned the hard way:

- **A headline must be true on every storefront the set ships to.** "A live
  score in your status bar" is a Play-only shot — the status-bar indicator is
  Android-only, and the claim would be false above an App Store listing.
- **No currency figures in screenshot art.** A GBP price baked into a picture is
  wrong on every other storefront. The paywall capture is therefore excluded
  from both marketing sets; it exists only as App Store Connect's IAP review
  screenshot.
