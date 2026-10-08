import 'dart:math';

import 'package:flutter/material.dart';

/// What the day looked like before the workout.
enum Shift {
  morning('Morning', 'Morning shift', Icons.wb_twilight),
  afternoon('Afternoon', 'Afternoon shift', Icons.wb_sunny_outlined),
  night('Night', 'Night shift', Icons.nightlight_outlined),
  off('Off', 'Day off', Icons.beach_access_outlined);

  const Shift(this.short, this.label, this.icon);
  final String short;
  final String label;
  final IconData icon;
}

/// How the user felt right before the workout.
enum Energy {
  great('Great', '🔥', Color(0xFF2E7D32)),
  good('Good', '🙂', Color(0xFF7CB342)),
  medium('Medium', '😐', Color(0xFFF9A825)),
  poor('Poor', '😴', Color(0xFFE53935));

  const Energy(this.label, this.emoji, this.color);
  final String label;
  final String emoji;
  final Color color;
}

enum Muscle {
  chest('Chest', Color(0xFFE53935)),
  back('Back', Color(0xFF1E88E5)),
  legs('Legs', Color(0xFF43A047)),
  shoulders('Shoulders', Color(0xFFFB8C00)),
  arms('Arms', Color(0xFF8E24AA)),
  core('Core', Color(0xFF00ACC1));

  const Muscle(this.label, this.color);
  final String label;
  final Color color;
}

/// Icons an exercise can use. Stored by key so release builds can tree-shake
/// the icon font (non-constant IconData breaks that).
const Map<String, IconData> exerciseIcons = {
  'barbell': Icons.fitness_center,
  'legs': Icons.airline_seat_legroom_extra,
  'gymnastics': Icons.sports_gymnastics,
  'body': Icons.accessibility_new,
  'arm': Icons.sports_mma,
  'core': Icons.self_improvement,
  'row': Icons.rowing,
  'walk': Icons.directions_walk,
  'stairs': Icons.stairs,
  'run': Icons.directions_run,
  'bike': Icons.directions_bike,
  'bolt': Icons.bolt,
};

class ExerciseDef {
  const ExerciseDef(this.id, this.name, this.muscle, this.iconKey,
      {this.custom = false});

  final String id;
  final String name;
  final Muscle muscle;
  final String iconKey;
  final bool custom;

  IconData get icon => exerciseIcons[iconKey] ?? Icons.fitness_center;

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'muscle': muscle.name, 'icon': iconKey};

  factory ExerciseDef.fromJson(Map<String, dynamic> j) => ExerciseDef(
        j['id'] as String,
        j['name'] as String,
        Muscle.values.byName(j['muscle'] as String),
        j['icon'] as String,
        custom: true,
      );
}

enum SetEffort {
  easy('Several more reps'),
  challenging('1–2 more reps'),
  limit('At my limit');

  const SetEffort(this.label);
  final String label;
}

/// A prescription is a target, never a completed set.
class ExerciseTarget {
  ExerciseTarget(
      {required this.sets,
      required this.repsMin,
      required this.repsMax,
      this.loadKg,
      this.restSeconds = 90,
      this.reason = ''}) {
    if (sets < 1 ||
        sets > 10 ||
        repsMin < 1 ||
        repsMax < repsMin ||
        repsMax > 50 ||
        restSeconds < 15 ||
        restSeconds > 600 ||
        (loadKg != null &&
            (!loadKg!.isFinite || loadKg! < 0 || loadKg! > 1000))) {
      throw const FormatException('Invalid exercise target');
    }
  }
  final int sets;
  final int repsMin;
  final int repsMax;
  final double? loadKg;
  final int restSeconds;
  final String reason;

  Map<String, dynamic> toJson() => {
        'sets': sets,
        'repsMin': repsMin,
        'repsMax': repsMax,
        'loadKg': loadKg,
        'restSeconds': restSeconds,
        'reason': reason
      };
  factory ExerciseTarget.fromJson(Map<String, dynamic> j) => ExerciseTarget(
      sets: j['sets'] as int,
      repsMin: (j['repsMin'] ?? j['reps']) as int,
      repsMax: (j['repsMax'] ?? j['reps']) as int,
      loadKg: (j['loadKg'] as num?)?.toDouble(),
      restSeconds: j['restSeconds'] as int? ?? 90,
      reason: j['reason'] as String? ?? '');
}

class SessionCheckIn {
  SessionCheckIn(
      {required this.shift,
      required this.energy,
      this.timeMinutes = 45,
      this.sleepHours,
      this.notes = '',
      this.recentTrainingNote = '',
      this.painNote = ''}) {
    if (timeMinutes < 10 ||
        timeMinutes > 180 ||
        (sleepHours != null &&
            (!sleepHours!.isFinite || sleepHours! < 0 || sleepHours! > 24)) ||
        [notes, recentTrainingNote, painNote].any((s) => s.length > 2000)) {
      throw const FormatException('Invalid session check-in');
    }
  }
  final Shift shift;
  final Energy energy;
  final int timeMinutes;
  final double? sleepHours;
  final String notes;
  final String recentTrainingNote;
  final String painNote;

  Map<String, dynamic> toJson() => {
        'shift': shift.name,
        'energy': energy.name,
        'timeMinutes': timeMinutes,
        'sleepHours': sleepHours,
        'notes': notes,
        'recentTrainingNote': recentTrainingNote,
        'painNote': painNote
      };
  factory SessionCheckIn.fromJson(Map<String, dynamic> j) => SessionCheckIn(
      shift: Shift.values.byName(j['shift'] as String),
      energy: Energy.values.byName(j['energy'] as String),
      timeMinutes: j['timeMinutes'] as int? ?? 45,
      sleepHours: (j['sleepHours'] as num?)?.toDouble(),
      notes: j['notes'] as String? ?? '',
      recentTrainingNote: j['recentTrainingNote'] as String? ?? '',
      painNote: j['painNote'] as String? ?? '');
}

class WorkSet {
  WorkSet(this.kg, this.reps, {this.effort, this.isWarmup});

  double kg;
  int reps;
  SetEffort? effort;
  // Null preserves the unknown classification of older sets.
  bool? isWarmup;

  double get volume => kg * reps;

  /// Epley estimate of the one-rep max.
  double get oneRepMax => reps <= 1 ? kg : kg * (1 + reps / 30);

  Map<String, dynamic> toJson() =>
      {'kg': kg, 'reps': reps, 'effort': effort?.name, 'isWarmup': isWarmup};

  factory WorkSet.fromJson(Map<String, dynamic> j) =>
      WorkSet((j['kg'] as num).toDouble(), j['reps'] as int,
          effort: j['effort'] == null
              ? null
              : SetEffort.values.byName(j['effort'] as String),
          isWarmup: j['isWarmup'] as bool?);
}

class WorkoutExercise {
  WorkoutExercise(this.exerciseId, [List<WorkSet>? sets]) : sets = sets ?? [];

  final String exerciseId;
  final List<WorkSet> sets;
  ExerciseTarget? target;

  int get reps => sets.fold<int>(0, (a, s) => a + s.reps);
  double get volume => sets.fold<double>(0, (a, s) => a + s.volume);
  double get topKg => sets.isEmpty ? 0 : sets.map((s) => s.kg).reduce(max);
  double get best1rm =>
      sets.isEmpty ? 0 : sets.map((s) => s.oneRepMax).reduce(max);

  Map<String, dynamic> toJson() => {
        'exercise': exerciseId,
        'sets': [for (final s in sets) s.toJson()],
        'target': target?.toJson(),
      };

  factory WorkoutExercise.fromJson(Map<String, dynamic> j) => WorkoutExercise(
        j['exercise'] as String,
        [
          for (final s in j['sets'] as List)
            WorkSet.fromJson(s as Map<String, dynamic>)
        ],
      )..target = j['target'] == null
          ? null
          : ExerciseTarget.fromJson(j['target'] as Map<String, dynamic>);
}

class Workout {
  Workout({
    required this.id,
    required this.start,
    this.end,
    required this.shift,
    required this.energy,
    this.checkIn,
    this.planTitle,
    List<WorkoutExercise>? exercises,
  }) : exercises = exercises ?? [];

  final String id;
  DateTime start;
  DateTime? end;
  Shift shift;
  Energy energy;
  SessionCheckIn? checkIn;
  String? planTitle;
  final List<WorkoutExercise> exercises;

  bool get isActive => end == null;
  Duration get duration => (end ?? DateTime.now()).difference(start);
  int get totalSets => exercises.fold<int>(0, (a, e) => a + e.sets.length);
  int get totalReps => exercises.fold<int>(0, (a, e) => a + e.reps);
  double get volume => exercises.fold<double>(0, (a, e) => a + e.volume);

  Map<String, dynamic> toJson() => {
        'id': id,
        'start': start.toIso8601String(),
        'end': end?.toIso8601String(),
        'shift': shift.name,
        'energy': energy.name,
        'checkIn': checkIn?.toJson(),
        'planTitle': planTitle,
        'exercises': [for (final e in exercises) e.toJson()],
      };

  factory Workout.fromJson(Map<String, dynamic> j) => Workout(
        id: j['id'] as String,
        start: DateTime.parse(j['start'] as String),
        end: j['end'] == null ? null : DateTime.parse(j['end'] as String),
        shift: Shift.values.byName(j['shift'] as String),
        energy: Energy.values.byName(j['energy'] as String),
        checkIn: j['checkIn'] == null
            ? null
            : SessionCheckIn.fromJson(j['checkIn'] as Map<String, dynamic>),
        planTitle: j['planTitle'] as String?,
        exercises: [
          for (final e in j['exercises'] as List)
            WorkoutExercise.fromJson(e as Map<String, dynamic>)
        ],
      );
}
