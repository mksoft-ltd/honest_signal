#!/bin/bash
# Frames the raw captures into finished store screenshots.
#
#   1. store-publisher runs integration_test/screenshots_test.dart and drops the
#      captures in raw/  (00_onboarding.png, 01_home.png, 02_history.png,
#      03_settings.png, 04_how_it_works.png, 05_pro.png)
#   2. ./render.sh            frames every set
#      ./render.sh ios        frames one set
#
# Two capture directories, one per store — see raw_dir_for() below. The Play set
# frames raw/ (the Android harness); the App Store set frames raw_ios/ (captured
# on an iPhone simulator). They are not interchangeable.
#
# Output: out/ios/*.png (1320x2868) and out/play/*.png (1080x2160).
#
# Headlines and the shot list live in specs.json; the layout is frame.html.
# Nothing here is device-specific, so a re-run on a later release produces an
# identical set.
set -euo pipefail
cd "$(dirname "$0")"

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
SETS="${*:-ios play}"

# Which capture directory to frame from. The two sets come from different
# devices and are NOT interchangeable: several screens render platform-specific
# copy, so an Android capture in the App Store set ships text that is false on
# iPhone ("Next, Android will ask…", "As reported by Android", "billed by
# Google Play"). raw/ is the Android harness output; raw_ios/ is captured
# host-side on an iPhone simulator. Default per set, overridable with RAW_DIR.
raw_dir_for() {
  case "$1" in
    ios) echo "${RAW_DIR:-raw_ios}" ;;
    *)   echo "${RAW_DIR:-raw}" ;;
  esac
}

for set in $SETS; do
  raw="$(raw_dir_for "$set")"

  if [ ! -d "$raw" ] || [ -z "$(ls "$raw"/*.png 2>/dev/null)" ]; then
    echo "$raw/ has no captures — capture first:" >&2
    echo "  flutter drive --driver=test_driver/integration_test.dart \\" >&2
    echo "    --target=integration_test/screenshots_test.dart \\" >&2
    echo "    --dart-define=SCREENSHOT_MODE=true" >&2
    echo "Put the device in LIGHT appearance first (see screenshot_specs.md §2)." >&2
    exit 1
  fi

  # The marketing set must come from a `pro`-tier capture. On a free run the
  # history route renders ProLock, and framing that under "Prove the drop-outs
  # are real" ships a screenshot showing a paywall where it advertises a graph.
  # A free-tier run produced exactly that, so this is a guard rather than a note.
  #
  # The harness writes tier.txt. Absent, we warn rather than fail, so an older
  # capture set still frames; present and wrong, we stop.
  # `|| true`: under `set -e` an assignment whose command substitution fails
  # takes the whole script down, so a missing marker would exit 0 having
  # rendered nothing at all.
  TIER="$(cat "$raw/tier.txt" 2>/dev/null | tr -d '[:space:]' || true)"
  if [ -z "$TIER" ]; then
    echo "  ! $raw/tier.txt missing — cannot confirm these captures are pro-tier." >&2
    echo "    If 02_history.png shows 'History is a Pro feature', recapture" >&2
    echo "    without SCREENSHOT_TIER=free before shipping." >&2
  elif [ "$TIER" != "pro" ]; then
    echo "$raw/ holds a '$TIER'-tier capture; the marketing set needs 'pro'." >&2
    echo "The history shot would frame the Pro lock screen under a headline" >&2
    echo "promising a chart. Recapture without SCREENSHOT_TIER=free." >&2
    exit 1
  fi

  mkdir -p "out/$set"
  # One python call emits the per-shot render commands, so specs.json stays the
  # single source of truth for both the list and the copy.
  python3 - "$set" "$raw" <<'PY' | while IFS=$'\t' read -r out url w h; do
import json, sys, urllib.parse
spec = json.load(open('specs.json'))
name = sys.argv[1]
canvas = spec['canvases'][name]
for shot in spec['shots'][name]:
    q = urllib.parse.urlencode({
        'dir': sys.argv[2],
        'src': shot['src'],
        'head': shot['head'],
        'sub': shot.get('sub', ''),
        'badge': shot.get('badge', ''),
    })
    print(f"{shot['out']}\t{q}\t{canvas['width']}\t{canvas['height']}")
PY
    src_png="$raw/$(python3 -c "
import json,sys,urllib.parse
print(urllib.parse.parse_qs('$url')['src'][0])")"
    if [ ! -f "$src_png" ]; then
      echo "  MISSING $src_png — skipping $set/$out" >&2
      continue
    fi
    "$CHROME" --headless=new --disable-gpu --hide-scrollbars \
      --force-device-scale-factor=1 --window-size="$w","$h" \
      --allow-file-access-from-files \
      --screenshot="out/$set/$out.png" \
      "file://$PWD/frame.html?$url" >/dev/null 2>&1
    echo "  out/$set/$out.png (${w}x${h})"
  done
done
