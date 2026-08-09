#!/bin/bash
# Rasterises the icon sources. This Mac has no ImageMagick / rsvg-convert, so
# headless Chrome does the SVG -> PNG step and `sips` does the downscales
# (Chrome crops rather than scales when the window is smaller than the SVG).
set -euo pipefail
cd "$(dirname "$0")"

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
shot() { # shot <svg> <png> <size>
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars \
    --force-device-scale-factor=1 --window-size="$3","$3" \
    --default-background-color=00000000 \
    --screenshot="$2" "file://$PWD/$1" >/dev/null 2>&1
}

python3 build_icon.py

shot icon_master.svg     icon_master.png     1024
shot icon_foreground.svg icon_foreground.png 1024
shot icon_background.svg icon_background.png 1024
shot icon_monochrome.svg icon_monochrome.png 1024
shot icon_mark.svg       icon_mark.png       1024

# Small-size proofs. Always look at these before believing the geometry maths.
for s in 180 120 48; do
  cp icon_master.png "preview_${s}.png"
  sips -z "$s" "$s" "preview_${s}.png" >/dev/null
done

# Round-mask proof: the foreground at the 16% inset inside the launcher circle.
"$CHROME" --headless=new --disable-gpu --hide-scrollbars \
  --force-device-scale-factor=1 --window-size=432,432 \
  --default-background-color=00000000 --allow-file-access-from-files \
  --screenshot=preview_adaptive.png "file://$PWD/mask_proof.html" >/dev/null 2>&1

echo "rendered: icon_master.png icon_foreground.png icon_background.png"
echo "proofs:   preview_180.png preview_120.png preview_48.png preview_adaptive.png"
