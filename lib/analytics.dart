import 'models.dart';
import 'recovery.dart';
import 'store.dart';

/// Deterministic metrics shared by the dashboard and AI context.
/// Compare identical exercise IDs and rep counts; never rank unrelated volume.
class ExerciseTrend {
  ExerciseTrend(this.exerciseId, this.reps, this.previousKg, this.currentKg,
      this.previousWorkoutId, this.currentWorkoutId);
  final String exerciseId;
  final int reps;
  final double previousKg;
  final double currentKg;
  final String previousWorkoutId;
  final String currentWorkoutId;
  double get delta => currentKg - previousKg;
  double get percent => previousKg == 0 ? 0 : delta / previousKg * 100;
  Map<String, dynamic> toJson() => {
        'exerciseId': exerciseId,
        'metric': 'load_at_same_reps',
        'reps': reps,
        'previousKg': previousKg,
        'currentKg': currentKg,
        'deltaKg': delta,
        'percent': percent,
        'evidenceWorkoutIds': [previousWorkoutId, currentWorkoutId],
        'confidence': 'limited',
        'limitations':
            'Two sessions; effort, technique and equipment may differ. Not proof of adaptation.',
      };
}

List<ExerciseTrend> exerciseTrends(GymaStore data, DateTime now, int days) {
  final start = DateTime(now.year, now.month, now.day - days + 1);
  final ids = {
    for (final w in data.finishedWorkouts)
      if (!w.start.isAfter(now) && !w.start.isBefore(start))
        for (final e in w.exercises) e.exerciseId
  };
  final result = <ExerciseTrend>[];
  for (final id in ids) {
    final history = data
        .historyFor(id)
        .where((h) => !h.$1.start.isAfter(now) && !h.$1.start.isBefore(start))
        .toList();
    if (history.length < 2) continue;
    final current = history.last;
    final previous = history[history.length - 2];
    Map<int, double> loads(WorkoutExercise e) {
      final map = <int, double>{};
      for (final s in e.sets) {
        if (s.kg <= 0 || s.reps <= 0) continue;
        if (s.kg > (map[s.reps] ?? 0)) map[s.reps] = s.kg;
      }
      return map;
    }

    final before = loads(previous.$2);
    final after = loads(current.$2);
    // Choose the most recent set's comparable rep count deterministically.
    final shared = current.$2.sets.reversed
        .map((s) => s.reps)
        .where((r) => before.containsKey(r) && after.containsKey(r));
    if (shared.isEmpty) continue;
    final reps = shared.first;
    result.add(ExerciseTrend(
        id, reps, before[reps]!, after[reps]!, previous.$1.id, current.$1.id));
  }
  result.sort((a, b) => b.percent.compareTo(a.percent));
  return result;
}

Map<String, dynamic> trainingContext(GymaStore data, DateTime now,
    {int days = 28}) {
  final from = DateTime(now.year, now.month, now.day - days + 1);
  final workouts = data.finishedWorkouts
      .where((w) => !w.start.isBefore(from) && !w.start.isAfter(now))
      .toList();
  final recovery = data.recoveryDays.values
      .where((r) =>
          r.day.compareTo(dayKey(from)) >= 0 &&
          r.day.compareTo(dayKey(now)) <= 0)
      .toList()
    ..sort((a, b) => a.day.compareTo(b.day));
  return {
    'schemaVersion': 1,
    'dataRevision': data.revision,
    'generatedAt': now.toUtc().toIso8601String(),
    'localToday': dayKey(now),
    'utcOffsetMinutes': now.timeZoneOffset.inMinutes,
    'window': {
      'fromDay': dayKey(from),
      'throughDay': dayKey(now),
      'days': days
    },
    'units': {'load': 'kg', 'volume': 'kg_repetitions'},
    'profile': data.trainingProfile,
    'exerciseCatalog': [for (final e in data.exercises) e.toJson()],
    'workouts': [
      for (final w in workouts) {...w.toJson(), 'localDay': dayKey(w.start)}
    ],
    'dailyRecovery': [for (final r in recovery) r.toJson()],
    'todayRecovery': data.recoveryDays[dayKey(now)]?.toJson(),
    'trends': [for (final t in exerciseTrends(data, now, days)) t.toJson()],
    'dataQuality': {
      'finishedSessions': workouts.length,
      'recoveryDaysLogged': recovery.length,
      'missingSorenessMeans': 'unknown; never assume none or carry forward',
      'sorenessScale': {'none': 0, 'mild': 1, 'moderate': 2, 'severe': 3},
      'painAreasMeaning':
          'User flagged pain different from ordinary muscle soreness',
      'limitations': [
        'Soreness is self-reported and is not a growth or readiness score.',
        'No causal inference about optimal routine from these observations.',
        'Historical daily check-ins may have been entered after a workout.',
        'Effort, warm-up status, sleep and equipment variations are not recorded.'
      ],
    },
  };
}
