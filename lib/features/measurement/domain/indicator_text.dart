import '../../../core/utils/formatters.dart';
import 'signal_sample.dart';

/// The one-line summary shown under the status-bar indicator and inside the
/// floating bubble's tooltip.
///
/// Shared by the foreground controller and the background isolate so the
/// notification text does not change wording depending on which one produced
/// the reading.
class IndicatorText {
  const IndicatorText._();

  static String detail(SignalSample sample) {
    if (sample.isOffline) return '${sample.kind.label} · no data getting through';
    final parts = <String>[sample.kind.label];
    if (sample.latencyMs != null) parts.add('${sample.latencyMs!.round()} ms');
    if (sample.throughputKbps != null && sample.throughputKbps! > 0) {
      parts.add(throughput(sample.throughputKbps!));
    }
    return parts.join(' · ');
  }

  /// Delegates to [Format.throughput] so the notification and the in-app meter
  /// cannot word the same reading differently. Two implementations had already
  /// drifted at and above 10 Mbps ("48 Mbps" in-app vs "48.0 Mbps" in the
  /// notification); PRODUCT_SPEC puts the wording in exactly one place.
  static String throughput(double kbps) => Format.throughput(kbps);
}
