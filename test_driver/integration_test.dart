import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Writes the screenshots the harness captures into
/// `store_assets/screenshots/raw/`, which is where `render.sh` looks for them
/// before framing each set into `out/ios/` and `out/play/`.
///
/// Alongside the PNGs it records `raw/tier.txt` — `pro` or `free` — reported by
/// the harness. `render.sh` refuses to frame the marketing set from a free-tier
/// capture, because on a free run the history route renders the Pro lock and
/// framing that under a headline promising a chart would ship a misleading
/// listing.
Future<void> main() async {
  const rawDirectory = 'store_assets/screenshots/raw';
  const tierMarker = '$rawDirectory/tier.txt';

  // The marker is written only once a run has finished, and any marker left by
  // an earlier run is cleared before the first new capture lands. Otherwise an
  // interrupted free-tier run would leave fresh free-tier PNGs sitting beside a
  // stale `pro` marker, which is the one combination that defeats the guard.
  // Absent, `render.sh` warns; wrong, it would happily frame the paywall.
  var clearedStaleMarker = false;

  await integrationDriver(
    onScreenshot: (String name, List<int> bytes, [Map<String, Object?>? args]) async {
      try {
        await Directory(rawDirectory).create(recursive: true);

        if (!clearedStaleMarker) {
          final marker = File(tierMarker);
          if (marker.existsSync()) await marker.delete();
          clearedStaleMarker = true;
        }

        await File('$rawDirectory/$name.png').writeAsBytes(bytes, flush: true);
        return true;
      } on Object catch (error) {
        // Returning false fails the drive. Swallowing the error and returning
        // true would let a full disk or a read-only path produce a green run
        // with missing captures, and the first sign of it would be a store
        // submission short of screenshots.
        stderr.writeln('Could not write screenshot "$name" to $rawDirectory: $error');
        return false;
      }
    },
    responseDataCallback: (Map<String, dynamic>? data) async {
      final tier = data?['tier'];
      if (tier is String && tier.isNotEmpty) {
        await Directory(rawDirectory).create(recursive: true);
        await File(tierMarker).writeAsString(tier, flush: true);
      }
    },
  );
}
