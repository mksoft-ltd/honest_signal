/// Endpoints the measurement engine probes.
///
/// All are long-standing captive-portal / connectivity-check endpoints operated
/// by major providers, chosen because they are anycast (so they measure the
/// nearest edge rather than a transatlantic hop), return an empty or near-empty
/// body, and are explicitly intended to be polled by devices.
///
/// Probing rotates across the list so no single provider sees a steady stream
/// from one device, and so one provider having a bad day cannot make a healthy
/// connection look broken.
class ProbeTargets {
  const ProbeTargets._();

  /// Empty-body 204 endpoints. Response body is zero bytes by design.
  static final List<Uri> latency = List.unmodifiable([
    Uri.parse('https://www.gstatic.com/generate_204'),
    Uri.parse('https://cp.cloudflare.com/generate_204'),
    Uri.parse('https://connectivitycheck.gstatic.com/generate_204'),
  ]);

  /// Cloudflare's public speed-test origin, which serves exactly the number of
  /// bytes asked for. Sizing the sample lets the engine hold a hard data
  /// budget instead of guessing.
  static Uri transfer(int bytes) =>
      Uri.parse('https://speed.cloudflare.com/__down?bytes=$bytes');

  /// Rotates the latency list so consecutive cycles start at different hosts.
  static List<Uri> latencyRotation(int cycle, int count) {
    final out = <Uri>[];
    for (var i = 0; i < count; i++) {
      out.add(latency[(cycle + i) % latency.length]);
    }
    return out;
  }
}
