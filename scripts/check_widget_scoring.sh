#!/bin/sh
# Regenerate the widget scoring fixture from the Dart scoring model and check
# the Swift port (ios/HonestSignalWidget/WidgetScoring.swift) against it.
# Run after changing lib/features/measurement/domain/scoring.dart.
set -e
cd "$(dirname "$0")/.."
dart run scripts/widget_scoring_fixture.dart
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp ios/HonestSignalWidget/Fixtures/CheckScoring.swift "$tmp/main.swift"
xcrun swiftc -O -o "$tmp/check" ios/HonestSignalWidget/WidgetScoring.swift "$tmp/main.swift"
"$tmp/check" ios/HonestSignalWidget/Fixtures/scoring_fixture.json
