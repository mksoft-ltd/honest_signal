import 'package:flutter/foundation.dart';

import 'data_budget.dart';
import 'signal_sample.dart';

/// Why the engine is not currently probing, when it isn't.
enum MeasurementPause {
  none,

  /// The user turned off measuring on mobile data.
  cellularOptOut,

  /// Today's probe data budget is spent.
  budgetExhausted,

  /// The app is backgrounded. On Android the foreground service keeps going; on
  /// iOS nothing runs, which the UI says out loud.
  appBackgrounded,
}

@immutable
class MeasurementState {
  const MeasurementState({
    required this.sample,
    required this.budget,
    this.measuring = false,
    this.pause = MeasurementPause.none,
  });

  final SignalSample sample;
  final DataBudget budget;
  final bool measuring;
  final MeasurementPause pause;

  bool get hasReading => !sample.isPlaceholder;

  MeasurementState copyWith({
    SignalSample? sample,
    DataBudget? budget,
    bool? measuring,
    MeasurementPause? pause,
  }) =>
      MeasurementState(
        sample: sample ?? this.sample,
        budget: budget ?? this.budget,
        measuring: measuring ?? this.measuring,
        pause: pause ?? this.pause,
      );
}
