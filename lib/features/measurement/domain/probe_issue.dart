import 'dart:async';

/// What went wrong with a probe, as far as the device can tell. Feeds the
/// plain-English diagnosis only; scoring never reads it.
enum ProbeIssue {
  /// Answered, but not with the endpoint's empty 204: a Wi-Fi sign-in page or
  /// a filtering proxy replied in its place.
  intercepted,

  /// The host name would not resolve.
  dns,

  /// Nothing came back before the deadline.
  timeout,

  /// Refused, reset, TLS failure or a 5xx — the path exists but did not work.
  unreachable;

  static ProbeIssue? fromStorage(Object? value) =>
      ProbeIssue.values.where((i) => i.name == value).firstOrNull;

  /// `package:http` wraps socket errors in a `ClientException` whose message
  /// carries the platform's wording, so the classification is by text. The
  /// phrases cover Android/Linux ("Failed host lookup", "No address
  /// associated with hostname") and iOS ("nodename nor servname").
  static ProbeIssue classify(Object error) {
    if (error is TimeoutException) return ProbeIssue.timeout;
    final text = error.toString().toLowerCase();
    if (text.contains('host lookup') ||
        text.contains('no address associated') ||
        text.contains('nodename nor servname') ||
        text.contains('name or service not known')) {
      return ProbeIssue.dns;
    }
    if (text.contains('timed out') || text.contains('timeout')) {
      return ProbeIssue.timeout;
    }
    return ProbeIssue.unreachable;
  }
}
