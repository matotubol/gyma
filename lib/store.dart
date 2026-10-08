import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'catalog.dart';
import 'models.dart';

/// The single app-wide store. Everything lives in one JSON file on the device.
final store = GymaStore();

class GymaStore extends ChangeNotifier {
  final List<ExerciseDef> customExercises = [];

  /// Newest first.
  final List<Workout> workouts = [];

  File? _file;
  Future<void> _pendingWrite = Future.value();

  Future<void> load() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/gyma_data.json');
      _file = file;
      if (await file.exists()) {
        try {
          _readJson(jsonDecode(await file.readAsString()) as Map<String, dynamic>);
        } catch (e) {
          // Keep the unreadable file instead of overwriting it on next save.
          debugPrint('Could not read data, backing it up: $e');
          await file.rename(
              '${dir.path}/gyma_data.broken-${DateTime.now().millisecondsSinceEpoch}.json');
          customExercises.clear();
          workouts.clear();
        }
      }
    } catch (e) {
      debugPrint('Storage unavailable: $e');
    }
    notifyListeners();
  }

  void _readJson(Map<String, dynamic> data) {
    customExercises
      ..clear()
      ..addAll([
        for (final e in data['customExercises'] as List? ?? const [])
          ExerciseDef.fromJson(e as Map<String, dynamic>)
      ]);
    workouts
      ..clear()
      ..addAll([
        for (final w in data['workouts'] as List? ?? const [])
          Workout.fromJson(w as Map<String, dynamic>)
      ])
      ..sort((a, b) => b.start.compareTo(a.start));
  }

  Map<String, dynamic> toJson() => {
        'version': 1,
        'customExercises': [for (final e in customExercises) e.toJson()],
        'workouts': [for (final w in workouts) w.toJson()],
      };

  void _changed() {
    notifyListeners();
    final file = _file;
    if (file == null) return;
    final json = jsonEncode(toJson());
    // Chain writes so they never overlap.
    _pendingWrite = _pendingWrite.then((_) => _write(file, json));
  }

  Future<void> _write(File file, String json) async {
    try {
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(json, flush: true);
      await tmp.rename(file.path);
    } catch (e) {
      debugPrint('Save failed: $e');
    }
  }

  // ---- Exercises ----

  List<ExerciseDef> get exercises => [...builtInExercises, ...customExercises];

  ExerciseDef exercise(String id) {
    for (final e in builtInExercises) {
      if (e.id == id) return e;
    }
    for (final e in customExercises) {
      if (e.id == id) return e;
    }
    return ExerciseDef(id, 'Unknown exercise', Muscle.core, 'bolt');
  }

  ExerciseDef addCustomExercise(String name, Muscle muscle, String iconKey) {
    final def = ExerciseDef(_newId('custom'), name, muscle, iconKey, custom: true);
    customExercises.add(def);
    _changed();
    return def;
  }

  // ---- Workouts ----

  Workout? get activeWorkout {
    for (final w in workouts) {
      if (w.isActive) return w;
    }
    return null;
  }

  List<Workout> get finishedWorkouts =>
      [for (final w in workouts) if (!w.isActive) w];

  Workout startWorkout(Shift shift, Energy energy) {
    final w = Workout(
        id: _newId('w'), start: DateTime.now(), shift: shift, energy: energy);
    workouts.insert(0, w);
    _changed();
    return w;
  }

  void updateCheckIn(Workout w, Shift shift, Energy energy) {
    w
      ..shift = shift
      ..energy = energy;
    _changed();
  }

  void finishWorkout(Workout w) {
    w.end = DateTime.now();
    _changed();
  }

  void deleteWorkout(Workout w) {
    workouts.remove(w);
    _changed();
  }

  void addExercise(Workout w, String exerciseId) {
    w.exercises.add(WorkoutExercise(exerciseId));
    _changed();
  }

  void removeExercise(Workout w, WorkoutExercise e) {
    w.exercises.remove(e);
    _changed();
  }

  void addSet(WorkoutExercise e, WorkSet set) {
    e.sets.add(set);
    _changed();
  }

  void updateSet(WorkoutExercise e, int index, WorkSet set) {
    e.sets[index] = set;
    _changed();
  }

  void removeSet(WorkoutExercise e, int index) {
    e.sets.removeAt(index);
    _changed();
  }

  /// The most recent earlier session of [exerciseId], to show "last time".
  WorkoutExercise? previousFor(String exerciseId, Workout current) {
    for (final w in workouts) {
      if (w == current || w.isActive || !w.start.isBefore(current.start)) {
        continue;
      }
      for (final e in w.exercises) {
        if (e.exerciseId == exerciseId && e.sets.isNotEmpty) return e;
      }
    }
    return null;
  }

  /// Every finished session of [exerciseId], oldest first.
  List<(Workout, WorkoutExercise)> historyFor(String exerciseId) {
    final result = <(Workout, WorkoutExercise)>[];
    for (final w in workouts.reversed) {
      if (w.isActive) continue;
      for (final e in w.exercises) {
        if (e.exerciseId == exerciseId && e.sets.isNotEmpty) {
          result.add((w, e));
          break;
        }
      }
    }
    return result;
  }

  String _newId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}';
}
