import 'models.dart';
import 'recovery.dart';
import 'store.dart';

bool isFinishedAt(Workout workout, DateTime now) =>
    workout.end != null &&
    !workout.start.isAfter(now) &&
    !workout.end!.isAfter(now);

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
      if (isFinishedAt(w, now) && !w.start.isBefore(start))
        for (final e in w.exercises) e.exerciseId
  };
  final result = <ExerciseTrend>[];
  for (final id in ids) {
    final history = data
        .historyFor(id)
        .where((h) => isFinishedAt(h.$1, now) && !h.$1.start.isBefore(start))
        .toList();
    if (history.length < 2) continue;
    final current = history.last;
    final previous = history[history.length - 2];
    Map<int, double> loads(WorkoutExercise e) {
      final map = <int, double>{};
      for (final s in e.sets) {
        if (s.isWarmup == true || s.kg <= 0 || s.reps <= 0) continue;
        if (s.kg > (map[s.reps] ?? 0)) map[s.reps] = s.kg;
      }
      return map;
    }

    final before = loads(previous.$2);
    final after = loads(current.$2);
    // Choose the most recent set's comparable rep count deterministically.
    final shared = current.$2.sets.reversed
        .where((s) => s.isWarmup != true)
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
    {int days = 28, SessionCheckIn? checkIn}) {
  final from = DateTime(now.year, now.month, now.day - days + 1);
  final allHistory = data.finishedWorkouts
      .where((w) => isFinishedAt(w, now))
      .toList()
    ..sort((a, b) => b.start.compareTo(a.start));
  final workouts = allHistory
      .where((w) => !w.start.isBefore(from) && !w.start.isAfter(now))
      .toList();
  final latestByExercise = <String, Map<String, dynamic>>{};
  for (final w in allHistory) {
    for (final e in w.exercises) {
      if (e.sets.isEmpty || latestByExercise.containsKey(e.exerciseId)) {
        continue;
      }
      latestByExercise[e.exerciseId] = {
        'workoutId': w.id,
        'exerciseId': e.exerciseId,
        'recordedAt': w.start.toIso8601String(),
        'daysSince': calendarDaysBetween(w.start, now),
        'sets': [for (final s in e.sets) s.toJson()],
        'target': e.target?.toJson()
      };
    }
  }
  final active = data.activeWorkout;
  final recovery = data.recoveryDays.values
      .where((r) =>
          r.day.compareTo(dayKey(from)) >= 0 &&
          r.day.compareTo(dayKey(now)) <= 0)
      .toList()
    ..sort((a, b) => a.day.compareTo(b.day));
  return {
    'schemaVersion': 2,
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
    'historySummary': {
      'totalFinishedWorkouts': allHistory.length,
      'lastWorkoutAt': allHistory.firstOrNull?.start.toIso8601String(),
      'daysSinceLastWorkout': allHistory.isEmpty
          ? null
          : calendarDaysBetween(allHistory.first.start, now),
      'lastExerciseSessions': latestByExercise.values.toList(),
      'meaning':
          'Logged activity only. A gap does not prove inactivity; ask about training elsewhere. Older loads are historical references, not current capacity.'
    },
    'currentCheckIn': checkIn?.toJson() ??
        active?.checkIn?.toJson() ??
        (active == null
            ? null
            : {'shift': active.shift.name, 'energy': active.energy.name}),
    'activeWorkout': active?.toJson(),
    'exerciseCatalog': [for (final e in data.exercises) e.toJson()],
    'workouts': [
      for (final w in workouts) {...w.toJson(), 'localDay': dayKey(w.start)}
    ],
    'dailyRecovery': [for (final r in recovery) r.toJson()],
    'todayRecovery': data.recoveryDays[dayKey(now)]?.toJson(),
    'trends': [for (final t in exerciseTrends(data, now, days)) t.toJson()],
    'repTrends': [for (final t in repTrends(data, now, days)) t.toJson()],
    'weeklyReview': weeklyReview(data, now),
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
        'Effort, warm-up status and sleep are optional; null means unknown. Older sets have no effort or warm-up classification.',
        'Equipment variations and technique are not measured. Photos and body measurements are excluded.'
      ],
    },
  };
}

int calendarDaysBetween(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day)
        .difference(DateTime.utc(from.year, from.month, from.day))
        .inDays;

class RepTrend {
  const RepTrend(this.exerciseId, this.kg, this.previousReps, this.currentReps,
      this.previousWorkoutId, this.currentWorkoutId);
  final String exerciseId;
  final double kg;
  final int previousReps;
  final int currentReps;
  final String previousWorkoutId;
  final String currentWorkoutId;
  int get delta => currentReps - previousReps;
  Map<String, dynamic> toJson() => {
        'exerciseId': exerciseId,
        'loadKg': kg,
        'previousReps': previousReps,
        'currentReps': currentReps,
        'evidenceWorkoutIds': [previousWorkoutId, currentWorkoutId],
        'limitations':
            'Two sessions at matching load. Effort, technique and equipment may differ.'
      };
}

List<RepTrend> repTrends(GymaStore data, DateTime now, int days) {
  final from = DateTime(now.year, now.month, now.day - days + 1);
  final result = <RepTrend>[];
  for (final def in data.exercises) {
    final history = data
        .historyFor(def.id)
        .where((h) => isFinishedAt(h.$1, now) && !h.$1.start.isBefore(from))
        .toList();
    if (history.length < 2) continue;
    final previous = history[history.length - 2];
    final current = history.last;
    Map<double, int> repsAtLoad(WorkoutExercise e) {
      final reps = <double, int>{};
      for (final s in e.sets.where((s) => s.isWarmup != true)) {
        if (s.kg <= 0) continue;
        if (s.reps > (reps[s.kg] ?? 0)) reps[s.kg] = s.reps;
      }
      return reps;
    }

    final before = repsAtLoad(previous.$2);
    final after = repsAtLoad(current.$2);
    final shared = current.$2.sets.reversed
        .where((s) => s.isWarmup != true)
        .map((s) => s.kg)
        .where((kg) => before.containsKey(kg) && after.containsKey(kg));
    if (shared.isEmpty) continue;
    final kg = shared.first;
    if (after[kg] == before[kg]) continue;
    result.add(RepTrend(
        def.id, kg, before[kg]!, after[kg]!, previous.$1.id, current.$1.id));
  }
  return result..sort((a, b) => b.delta.compareTo(a.delta));
}

Map<String, dynamic> weeklyReview(GymaStore data, DateTime now) {
  final from = DateTime(now.year, now.month, now.day - 6);
  final workouts = data.finishedWorkouts
      .where((w) => !w.start.isBefore(from) && isFinishedAt(w, now));
  final sets =
      workouts.expand((w) => w.exercises).expand((e) => e.sets).toList();
  return {
    'fromDay': dayKey(from),
    'throughDay': dayKey(now),
    'sessions': workouts.length,
    'trainingDays': workouts.map((w) => dayKey(w.start)).toSet().length,
    'workingSets': sets.where((s) => s.isWarmup == false).length,
    'warmupSets': sets.where((s) => s.isWarmup == true).length,
    'unclassifiedSets': sets.where((s) => s.isWarmup == null).length,
    'setsWithEffort':
        sets.where((s) => s.isWarmup == false && s.effort != null).length,
    'interpretation':
        'Activity observations, not a muscle-growth or readiness score.'
  };
}
