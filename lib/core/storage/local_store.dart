import 'dart:typed_data';

import 'package:hive_flutter/hive_flutter.dart';

/// Opens and holds the app's Hive boxes.
///
/// Two boxes only: `settings` for everything small and singular, `history` for
/// the rolling sample log keyed by timestamp. No adapters or codegen — values
/// are plain JSON maps, which keeps the schema readable and migration-free.
class LocalStore {
  LocalStore._(this.settings, this.history);

  static const String settingsBoxName = 'settings';
  static const String historyBoxName = 'history';

  final Box<dynamic> settings;
  final Box<dynamic> history;

  static Future<LocalStore> open() async {
    await Hive.initFlutter();
    final settings = await Hive.openBox<dynamic>(settingsBoxName);
    final history = await Hive.openBox<dynamic>(historyBoxName);
    return LocalStore._(settings, history);
  }

  /// In-memory boxes for tests and for the screenshot harness, so neither
  /// touches the real on-device data. Passing a `bytes` buffer is Hive's way of
  /// saying "this box never hits disk".
  static Future<LocalStore> openInMemory() async {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final settings = await Hive.openBox<dynamic>(
      '${settingsBoxName}_mem_$stamp',
      bytes: Uint8List(0),
    );
    final history = await Hive.openBox<dynamic>(
      '${historyBoxName}_mem_$stamp',
      bytes: Uint8List(0),
    );
    return LocalStore._(settings, history);
  }

  Future<void> close() async {
    await settings.close();
    await history.close();
  }
}
