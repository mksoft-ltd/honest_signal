#!/usr/bin/env python3
"""Generates Honest Signal's icon sources as SVG.

Run `./render.sh` afterwards to rasterise them (headless Chrome; this Mac has no
ImageMagick or rsvg-convert).

The mark: five ascending signal bars occupy the lower-right of the plate, which
leaves an empty upper-left triangle; a bold tick sits in it. Two shapes, no
badge, no overlap — it reads at 48 px, and it says "bars, verified" without
copying the OS status-bar glyph or any carrier's logo.
"""

import os

INK_TOP = "#12211C"
INK_BOTTOM = "#08120F"
INK_FLAT = "#0D1915"          # adaptive-icon background / launch background
GREEN_BOTTOM = "#189C70"
GREEN_TOP = "#45E0A6"
TICK = "#FFFFFF"

C = 1024.0                     # master canvas

# ---------------------------------------------------------------- mark geometry
# All coordinates are in master-canvas units and are scaled as a group, so the
# same routine serves the full-bleed master and the inset adaptive foreground.

BASELINE = 782.0
BARS_LEFT = 372.0
BARS_RIGHT = 872.0
BARS_SPAN = BARS_RIGHT - BARS_LEFT
BAR_COUNT = 5
BAR_GAP = BARS_SPAN * 0.055
BAR_W = (BARS_SPAN - BAR_GAP * (BAR_COUNT - 1)) / BAR_COUNT
BAR_FULL_H = 470.0

TICK_STROKE = 76.0
TICK_PTS = [(196.0, 436.0), (288.0, 532.0), (462.0, 312.0)]


def bars_paths():
    out = []
    for i in range(BAR_COUNT):
        factor = 0.32 + (i / (BAR_COUNT - 1)) * 0.68
        h = BAR_FULL_H * factor
        x = BARS_LEFT + i * (BAR_W + BAR_GAP)
        out.append(
            f'<rect x="{x:.2f}" y="{BASELINE - h:.2f}" width="{BAR_W:.2f}" '
            f'height="{h:.2f}" rx="{BAR_W * 0.3:.2f}" fill="url(#g)"/>'
        )
    return "\n    ".join(out)


def tick_path():
    d = "M {:.1f} {:.1f} L {:.1f} {:.1f} L {:.1f} {:.1f}".format(
        *[v for pt in TICK_PTS for v in pt]
    )
    return (
        f'<path d="{d}" fill="none" stroke="{TICK}" stroke-width="{TICK_STROKE:.1f}" '
        'stroke-linecap="round" stroke-linejoin="round"/>'
    )


# The drawn mark's true extent, used to centre it and to size the adaptive inset.
MARK_LEFT = TICK_PTS[0][0] - TICK_STROKE / 2
MARK_RIGHT = BARS_RIGHT
MARK_TOP = TICK_PTS[2][1] - TICK_STROKE / 2
MARK_BOTTOM = BASELINE
MARK_CX = (MARK_LEFT + MARK_RIGHT) / 2
MARK_CY = (MARK_TOP + MARK_BOTTOM) / 2


def gradients():
    return f"""  <defs>
    <linearGradient id="plate" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="{INK_TOP}"/>
      <stop offset="1" stop-color="{INK_BOTTOM}"/>
    </linearGradient>
    <!-- One gradient across the whole cluster rather than per bar, so the
         ascent itself brightens: the short bars sit in the deep green, the
         tallest reaches the mint. Per-bar (objectBoundingBox) gradients make
         all five identical and the ramp disappears. -->
    <linearGradient id="g" gradientUnits="userSpaceOnUse"
                    x1="{BARS_LEFT:.0f}" y1="{BASELINE:.0f}"
                    x2="{BARS_RIGHT:.0f}" y2="{BASELINE - BAR_FULL_H:.0f}">
      <stop offset="0" stop-color="{GREEN_BOTTOM}"/>
      <stop offset="1" stop-color="{GREEN_TOP}"/>
    </linearGradient>
  </defs>"""


def mark_group(scale, cx=C / 2, cy=C / 2, flat=None):
    """The mark, scaled about its own centre and re-centred on (cx, cy).

    `flat` paints every element in one colour, for the Android 13 themed-icon
    layer where the system supplies its own tint and a gradient would be lost.
    """
    tx = cx - MARK_CX * scale
    ty = cy - MARK_CY * scale
    bars = bars_paths()
    tick = tick_path()
    if flat:
        bars = bars.replace("url(#g)", flat)
        tick = tick.replace(f'stroke="{TICK}"', f'stroke="{flat}"')
    return (
        f'  <g transform="translate({tx:.2f} {ty:.2f}) scale({scale:.4f})">\n'
        f"    {bars}\n"
        f"    {tick}\n"
        "  </g>"
    )


def svg(body, size=C, background=None):
    bg = (
        f'  <rect width="{size:.0f}" height="{size:.0f}" fill="{background}"/>\n'
        if background
        else ""
    )
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{size:.0f}" '
        f'height="{size:.0f}" viewBox="0 0 {size:.0f} {size:.0f}">\n'
        f"{gradients()}\n{bg}{body}\n</svg>\n"
    )


def main():
    here = os.path.dirname(os.path.abspath(__file__))

    # 1. Full-bleed master — iOS AppIcon and the legacy Android launcher.
    #    The stores round the corners themselves, so the plate is a plain square.
    half_w = (MARK_RIGHT - MARK_LEFT) / 2
    half_h = (MARK_BOTTOM - MARK_TOP) / 2
    master_span = 0.74 * C
    master = svg(
        f'  <rect width="{C:.0f}" height="{C:.0f}" fill="url(#plate)"/>\n'
        + mark_group(master_span / (2 * half_w))
    )
    open(os.path.join(here, "icon_master.svg"), "w").write(master)

    # 2. Adaptive foreground — the mark only, on transparency.
    #
    #    flutter_launcher_icons wraps the source in a 16% inset, so the source
    #    canvas lands at 68% of the 108 dp layer. Launcher masks clip outside a
    #    66 dp circle; SAFE_DP is deliberately tighter than that. What must fit
    #    is the mark's farthest *drawn* point from its own centre — not the
    #    bounding-box corner, which for this mark (tick top-left, bars
    #    bottom-right) is empty plate.
    #
    #        0.68 * r_source <= (SAFE_DP / 108) / 2
    #        coverage = span/source = (SAFE_DP/108) / 0.68 * half_span/max_radius
    #
    #    For a circular mark (half_span == max_radius) that gives the familiar
    #    ~0.78 rule of thumb, which is the check that the algebra is right.
    SAFE_DP = 58.0
    max_radius = (half_w**2 + half_h**2) ** 0.5
    coverage = (SAFE_DP / 108.0) / 0.68 * (half_w / max_radius)
    scale = coverage * C / (2 * half_w)
    foreground = svg(mark_group(scale))
    open(os.path.join(here, "icon_foreground.svg"), "w").write(foreground)

    # 3. Adaptive background — flat ink, so it matches the plate without a
    #    gradient the mask would crop unevenly.
    open(os.path.join(here, "icon_background.svg"), "w").write(
        svg("", background=INK_FLAT)
    )

    # 4. The bare mark on transparency, filling its canvas — for the Play
    #    feature graphic and the froggyeye.com promo page, where it sits on a
    #    background of their own rather than on the icon plate.
    open(os.path.join(here, "icon_mark.svg"), "w").write(
        svg(mark_group(0.96 * C / (2 * half_w)))
    )

    # 5. Themed-icon (Android 13+) layer: the same mark, one flat colour, on
    #    transparency. The system tints it to the wallpaper palette, so the tick
    #    and the bars have to survive as a single silhouette — which they do,
    #    because they never touch.
    open(os.path.join(here, "icon_monochrome.svg"), "w").write(
        svg(mark_group(scale, flat="#FFFFFF"))
    )

    print(f"mark span      {2 * half_w:.0f} x {2 * half_h:.0f}")
    print(f"max radius     {max_radius:.1f}")
    print(f"coverage       {coverage:.3f}   (scale {scale:.3f})")


if __name__ == "__main__":
    main()
