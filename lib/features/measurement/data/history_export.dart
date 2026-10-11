import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../../core/utils/formatters.dart';
import '../domain/history_insights.dart';
import '../domain/history_stats.dart';
import '../domain/signal_sample.dart';

/// Turns stored history into files the user can send to their provider.
///
/// Nothing leaves the device unless the user picks a destination in the
/// system share sheet: the files are written to the app's temporary directory
/// and handed over, and the app itself sends nothing anywhere. The report
/// carries no device, account or location identifiers.
class HistoryExport {
  const HistoryExport._();

  static const String _csvHeader =
      'timestamp_utc,local_time,network,bars,composite,latency_ms,'
      'jitter_ms,throughput_kbps,loss_percent,issue';

  /// One row per stored reading, oldest first. Plain RFC 4180 CSV with an
  /// ISO 8601 UTC timestamp so a spreadsheet or a provider's tooling can read
  /// it without guessing the time zone.
  static String csv(List<SignalSample> samples) {
    final ordered = [...samples]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final out = StringBuffer()..writeln(_csvHeader);
    String n(double? v, [int digits = 0]) =>
        v == null ? '' : v.toStringAsFixed(digits);
    for (final s in ordered) {
      out.writeln(
        [
          s.timestamp.toUtc().toIso8601String(),
          _localStamp(s.timestamp),
          s.kind.label,
          s.bars,
          s.composite.toStringAsFixed(3),
          n(s.latencyMs),
          n(s.jitterMs),
          n(s.throughputKbps),
          (s.lossRatio * 100).toStringAsFixed(0),
          s.issue?.name ?? '',
        ].join(','),
      );
    }
    return out.toString();
  }

  /// A one-to-two page evidence report: what was measured, how often it went
  /// wrong and exactly when.
  static Future<Uint8List> pdfReport({
    required List<SignalSample> samples,
    required Duration window,
    required DateTime now,
    required Duration maxHold,
  }) async {
    final stats = HistoryStats.from(samples, end: now, maxHold: maxHold);
    final drops = HistoryInsights.dropouts(samples, end: now, maxHold: maxHold);
    final networks = HistoryInsights.byNetwork(
      samples,
      end: now,
      maxHold: maxHold,
    );
    final start = now.subtract(window);
    final doc = pw.Document(
      title: 'Connection report',
      author: 'Honest Signal',
      creator: 'Honest Signal',
    );

    pw.Widget heading(String text) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 18, bottom: 6),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
      ),
    );

    pw.Widget row(String label, String value) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        children: [
          pw.Expanded(child: pw.Text(label)),
          pw.Text(value, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        footer: (context) => pw.Text(
          'Measured on this phone by Honest Signal, which times real requests '
          'to public Google and Cloudflare connectivity-check endpoints and '
          'real download samples, and scores the result from 0 to 5 bars. '
          'Page ${context.pageNumber} of ${context.pagesCount}.',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
        build: (context) => [
          pw.Text(
            'Connection report',
            style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            '${_localStamp(start)} to ${_localStamp(now)} '
            '(local time, UTC${_utcOffset(now)})',
          ),
          heading('Summary'),
          row('Readings stored', '${samples.length}'),
          row('Drop-outs (0-1 bars)', '${drops.length}'),
          row(
            'Time at 0-1 bars',
            samples.isEmpty ? '-' : _pdf(Format.percent(stats.badFraction)),
          ),
          row(
            'Time at 4-5 bars',
            samples.isEmpty ? '-' : _pdf(Format.percent(stats.goodFraction)),
          ),
          row(
            'Longest drop-out',
            drops.isEmpty
                ? '-'
                : _duration(
                    drops
                        .map((d) => d.duration)
                        .reduce((a, b) => a > b ? a : b),
                  ),
          ),
          row('Median latency', _pdf(Format.latency(stats.medianLatency))),
          row('Best speed seen', _pdf(Format.throughput(stats.bestThroughput))),
          heading('Score over time'),
          pw.SizedBox(
            height: 110,
            child: pw.CustomPaint(
              size: const PdfPoint(523, 110),
              painter: (canvas, size) =>
                  _paintChart(canvas, size, samples, start, now, maxHold),
            ),
          ),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                _localStamp(start),
                style: const pw.TextStyle(fontSize: 8),
              ),
              pw.Text(_localStamp(now), style: const pw.TextStyle(fontSize: 8)),
            ],
          ),
          if (networks.isNotEmpty) ...[
            heading('By network'),
            pw.TableHelper.fromTextArray(
              headers: [
                'Network',
                'Time measured',
                'Average',
                'At 0-1 bars',
                'Median latency',
                'Drop-outs',
              ],
              data: [
                for (final n in networks)
                  [
                    n.kind.label,
                    _duration(n.measured),
                    '${n.averageBars.toStringAsFixed(1)} / 5',
                    _pdf(Format.percent(n.poorFraction)),
                    _pdf(Format.latency(n.medianLatency)),
                    '${n.dropouts}',
                  ],
              ],
              cellStyle: const pw.TextStyle(fontSize: 9),
              headerStyle: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
          heading('Every drop-out'),
          if (drops.isEmpty)
            pw.Text('None in this period.')
          else
            pw.TableHelper.fromTextArray(
              headers: ['Started', 'Ended', 'Lasted', 'Network', 'Lowest'],
              data: [
                for (final d in drops.reversed)
                  [
                    _localStamp(d.start),
                    d.ongoing ? 'ongoing' : _localStamp(d.end),
                    _duration(d.duration),
                    d.kind.label,
                    '${d.worstBars} / 5',
                  ],
              ],
              cellStyle: const pw.TextStyle(fontSize: 9),
              headerStyle: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          pw.SizedBox(height: 12),
          pw.Text(
            'A drop-out is a continuous period scored 0 or 1 bars. Readings are '
            'taken while the app is open and, on Android with the status-bar '
            'indicator on, in the background. Periods with no fresh reading '
            'are left blank rather than guessed. Readings older than 25 hours '
            'are kept as the worst reading in each 5 minutes.',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ],
      ),
    );
    return doc.save();
  }

  static void _paintChart(
    PdfGraphics canvas,
    PdfPoint size,
    List<SignalSample> samples,
    DateTime start,
    DateTime end,
    Duration maxHold,
  ) {
    final span = end.difference(start).inMilliseconds;
    if (span <= 0) return;
    canvas
      ..setStrokeColor(PdfColors.grey300)
      ..setLineWidth(0.5);
    for (var level = 0; level <= 5; level++) {
      final y = level / 5 * size.y;
      canvas
        ..moveTo(0, y)
        ..lineTo(size.x, y)
        ..strokePath();
    }
    double x(DateTime t) =>
        (t.difference(start).inMilliseconds / span).clamp(0.0, 1.0) * size.x;
    for (final interval in HistoryInterval.fromSamples(
      samples,
      end: end,
      maxHold: maxHold,
    )) {
      final bars = interval.sample.bars;
      final left = x(interval.start);
      final width = (x(interval.end) - left).clamp(0.5, size.x);
      final height = bars == 0 ? 2.0 : bars / 5 * size.y;
      canvas
        ..setFillColor(_colour(bars))
        ..drawRect(left, 0, width, height)
        ..fillPath();
    }
  }

  static PdfColor _colour(int bars) => switch (bars) {
    0 || 1 => PdfColors.red600,
    2 => PdfColors.orange600,
    3 => PdfColors.amber600,
    _ => PdfColors.green600,
  };

  /// Writes [bytes] to a temporary file and opens the system share sheet.
  static Future<void> share({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    required String subject,
  }) async {
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: mimeType)],
        subject: subject,
      ),
    );
  }

  static String fileStamp(DateTime t) =>
      '${t.year}-${_two(t.month)}-${_two(t.day)}';

  static String _localStamp(DateTime t) =>
      '${t.year}-${_two(t.month)}-${_two(t.day)} '
      '${_two(t.hour)}:${_two(t.minute)}';

  static String _utcOffset(DateTime t) {
    final offset = t.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final minutes = offset.inMinutes.abs();
    return '$sign${_two(minutes ~/ 60)}:${_two(minutes % 60)}';
  }

  static String _duration(Duration d) {
    if (d.inMinutes < 1) return '${d.inSeconds} s';
    if (d.inHours < 1) return '${d.inMinutes} min';
    if (d.inDays < 1) return '${d.inHours} h ${_two(d.inMinutes % 60)} min';
    return '${d.inDays} d ${d.inHours % 24} h';
  }

  /// The built-in PDF fonts are Latin-1 only; `Format` uses an em dash for
  /// "no value", which would otherwise silently vanish from the report.
  static String _pdf(String text) =>
      text.replaceAll('—', '-').replaceAll('–', '-');

  static String _two(int v) => v.toString().padLeft(2, '0');
}
