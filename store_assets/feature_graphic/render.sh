#!/bin/bash
# Google Play feature graphic, 1024x500. Headless Chrome renders the HTML;
# this Mac has no ImageMagick or rsvg-convert.
set -euo pipefail
cd "$(dirname "$0")"

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

# The mark the graphic composites must exist first.
[ -f ../icon/icon_mark.png ] || ../icon/render.sh

"$CHROME" --headless=new --disable-gpu --hide-scrollbars \
  --force-device-scale-factor=1 --window-size=1024,500 \
  --allow-file-access-from-files \
  --screenshot=feature_graphic.png "file://$PWD/feature_graphic.html" >/dev/null 2>&1

# Crop proof: Play covers or crops the outer edges on some surfaces, so render
# the finished PNG with the outer 100 px shaded and look at it.
"$CHROME" --headless=new --disable-gpu --hide-scrollbars \
  --force-device-scale-factor=1 --window-size=1024,500 \
  --allow-file-access-from-files \
  --screenshot=proof_crop.png "file://$PWD/crop_proof.html" >/dev/null 2>&1

echo "rendered: feature_graphic.png (1024x500)"
echo "proof:    proof_crop.png"
