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

class WorkSet {
  WorkSet(this.kg, this.reps);

  double kg;
  int reps;

  double get volume => kg * reps;

  /// Epley estimate of the one-rep max.
  double get oneRepMax => reps <= 1 ? kg : kg * (1 + reps / 30);

  Map<String, dynamic> toJson() => {'kg': kg, 'reps': reps};

  factory WorkSet.fromJson(Map<String, dynamic> j) =>
      WorkSet((j['kg'] as num).toDouble(), (j['reps'] as num).toInt());
}

class WorkoutExercise {
  WorkoutExercise(this.exerciseId, [List<WorkSet>? sets]) : sets = sets ?? [];

  final String exerciseId;
  final List<WorkSet> sets;

  int get reps => sets.fold<int>(0, (a, s) => a + s.reps);
  double get volume => sets.fold<double>(0, (a, s) => a + s.volume);
  double get topKg => sets.isEmpty ? 0 : sets.map((s) => s.kg).reduce(max);
  double get best1rm =>
      sets.isEmpty ? 0 : sets.map((s) => s.oneRepMax).reduce(max);

  Map<String, dynamic> toJson() => {
        'exercise': exerciseId,
        'sets': [for (final s in sets) s.toJson()],
      };

  factory WorkoutExercise.fromJson(Map<String, dynamic> j) => WorkoutExercise(
        j['exercise'] as String,
        [
          for (final s in j['sets'] as List)
            WorkSet.fromJson(s as Map<String, dynamic>)
        ],
      );
}

class Workout {
  Workout({
    required this.id,
    required this.start,
    this.end,
    required this.shift,
    required this.energy,
    List<WorkoutExercise>? exercises,
  }) : exercises = exercises ?? [];

  final String id;
  DateTime start;
  DateTime? end;
  Shift shift;
  Energy energy;
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
        'exercises': [for (final e in exercises) e.toJson()],
      };

  factory Workout.fromJson(Map<String, dynamic> j) => Workout(
        id: j['id'] as String,
        start: DateTime.parse(j['start'] as String),
        end: j['end'] == null ? null : DateTime.parse(j['end'] as String),
        shift: Shift.values.byName(j['shift'] as String),
        energy: Energy.values.byName(j['energy'] as String),
        exercises: [
          for (final e in j['exercises'] as List)
            WorkoutExercise.fromJson(e as Map<String, dynamic>)
        ],
      );
}
