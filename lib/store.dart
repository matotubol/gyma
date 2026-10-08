import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'catalog.dart';
import 'coach_client.dart';
import 'models.dart';
import 'recovery.dart';

/// The single app-wide store. Everything lives in one JSON file on the device.
final store = GymaStore();

class GymaStore extends ChangeNotifier {
  GymaStore();

  factory GymaStore.fromJson(Map<String, dynamic> data) =>
      GymaStore().._readJson(data);

  final List<ExerciseDef> customExercises = [];
  final Map<String, RecoveryDay> recoveryDays = {};
  final List<Workout> deletedWorkouts = [];
  final List<Map<String, dynamic>> editHistory = [];
  Map<String, String> trainingProfile = {};
  final List<Map<String, String>> coachConversation = [];
  Map<String, dynamic>? coachDraft;
  int? coachDraftRevision;
  String? coachDraftDay;
  int revision = 0;
  // In-memory generation lets open editors react to an explicit restore.
  int restoreGeneration = 0;
  String? storageError;

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
          final parsed = GymaStore.fromJson(
              jsonDecode(await file.readAsString()) as Map<String, dynamic>);
          _readJson(parsed.toJson());
        } catch (e) {
          // Keep the unreadable file instead of overwriting it on next save.
          debugPrint('Could not read data, backing it up: $e');
          await file.rename(
              '${dir.path}/gyma_data.broken-${DateTime.now().millisecondsSinceEpoch}.json');
          customExercises.clear();
          workouts.clear();
          recoveryDays.clear();
          deletedWorkouts.clear();
          editHistory.clear();
          trainingProfile.clear();
          coachConversation.clear();
          coachDraft = null;
          coachDraftRevision = null;
          coachDraftDay = null;
          storageError =
              'Saved data could not be read. The original file has been preserved on this device.';
        }
      }
    } catch (e) {
      _file = null;
      storageError =
          'Device storage is unavailable. Export a backup before closing the app.';
      debugPrint('Storage unavailable: $e');
    }
    notifyListeners();
  }

  void _readJson(Map<String, dynamic> data) {
    final version = data['version'] as int? ?? 1;
    if (version < 1 || version > 3) {
      throw const FormatException('Unsupported backup version');
    }
    revision = data['revision'] as int? ?? 0;
    recoveryDays
      ..clear()
      ..addEntries([
        for (final r in data['recoveryDays'] as List? ?? [])
          MapEntry(r['day'] as String,
              RecoveryDay.fromJson(r as Map<String, dynamic>))
      ]);
    deletedWorkouts
      ..clear()
      ..addAll([
        for (final w in data['deletedWorkouts'] as List? ?? [])
          Workout.fromJson(w as Map<String, dynamic>)
      ]);
    editHistory
      ..clear()
      ..addAll([
        for (final e in data['editHistory'] as List? ?? [])
          Map<String, dynamic>.from(e as Map)
      ]);
    trainingProfile =
        Map<String, String>.from(data['trainingProfile'] as Map? ?? {});
    coachConversation.clear();
    try {
      final messages = [
        for (final m in data['coachConversation'] as List? ?? [])
          Map<String, String>.from(m as Map)
      ];
      if (messages.length <= 40 &&
          messages.every((m) =>
              ['user', 'assistant'].contains(m['role']) &&
              m['content'] != null &&
              m['content']!.length <= 100000)) {
        coachConversation.addAll(messages);
      }
    } catch (_) {
      // An unusable advisory cache must never prevent workout recovery.
    }
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
    final ids = <String>{};
    for (final w in [...workouts, ...deletedWorkouts]) {
      if (!ids.add(w.id) || (w.end?.isBefore(w.start) ?? false)) {
        throw const FormatException('Invalid workout identity or duration');
      }
      for (final e in w.exercises) {
        for (final s in e.sets) {
          if (!s.kg.isFinite || s.kg < 0 || s.reps <= 0) {
            throw const FormatException('Invalid set');
          }
        }
      }
    }
    if (workouts.where((w) => w.isActive).length > 1) {
      throw const FormatException('Multiple active workouts');
    }
    for (final r in recoveryDays.values) {
      final parsed = DateTime.tryParse(r.day);
      if (parsed == null || dayKey(parsed) != r.day) {
        throw const FormatException('Invalid recovery day');
      }
    }
    for (final entry in editHistory) {
      if (entry['action'] is! String ||
          entry['at'] is! String ||
          entry['before'] is! Map) {
        throw const FormatException('Invalid edit history');
      }
    }
    coachDraft = null;
    coachDraftRevision = null;
    coachDraftDay = null;
    try {
      final draft = data['coachDraft'] == null
          ? null
          : Map<String, dynamic>.from(data['coachDraft'] as Map);
      if (draft != null) {
        CoachClient.validateReply(draft, {
          'workouts': [
            for (final w in [...workouts, ...deletedWorkouts]) {'id': w.id}
          ],
          'exerciseCatalog': [
            for (final e in exercises) {'id': e.id}
          ]
        });
        coachDraft = draft;
        coachDraftRevision = data['coachDraftRevision'] as int?;
        coachDraftDay = data['coachDraftDay'] as String?;
      }
    } catch (_) {
      coachDraft = null;
      coachDraftRevision = null;
      coachDraftDay = null;
    }
  }

  Map<String, dynamic> toJson() => {
        'version': 3,
        'revision': revision,
        'recoveryDays': [for (final r in recoveryDays.values) r.toJson()],
        'deletedWorkouts': [for (final w in deletedWorkouts) w.toJson()],
        'editHistory': editHistory,
        'trainingProfile': trainingProfile,
        'coachConversation': coachConversation,
        'coachDraft': coachDraft,
        'coachDraftRevision': coachDraftRevision,
        'coachDraftDay': coachDraftDay,
        'customExercises': [for (final e in customExercises) e.toJson()],
        'workouts': [for (final w in workouts) w.toJson()],
      };

  void _changed({bool trainingChanged = true}) {
    if (trainingChanged) revision++;
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
      if (storageError != null) {
        storageError = null;
        notifyListeners();
      }
    } catch (e) {
      storageError =
          'Changes could not be saved. Keep the app open and export a backup.';
      notifyListeners();
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
    final def =
        ExerciseDef(_newId('custom'), name, muscle, iconKey, custom: true);
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

  List<Workout> get finishedWorkouts => [
        for (final w in workouts)
          if (!w.isActive) w
      ];

  Workout startWorkout(Shift shift, Energy energy,
      {SessionCheckIn? checkIn,
      List<WorkoutExercise>? exercises,
      String? planTitle}) {
    if (activeWorkout != null) {
      throw StateError('Resume or finish your current workout first.');
    }
    final entries = [
      for (final e in exercises ?? <WorkoutExercise>[])
        WorkoutExercise.fromJson(e.toJson())
    ];
    if (entries.any((e) => e.sets.isNotEmpty) ||
        entries.map((e) => e.exerciseId).toSet().length != entries.length ||
        entries
            .any((e) => !this.exercises.any((def) => def.id == e.exerciseId))) {
      throw const FormatException(
          'A new session needs valid exercises with no completed sets.');
    }
    final w = Workout(
        id: _newId('w'),
        start: DateTime.now(),
        shift: shift,
        energy: energy,
        checkIn: checkIn,
        exercises: entries,
        planTitle: planTitle);
    workouts.insert(0, w);
    _changed();
    return w;
  }

  void updateCheckIn(Workout w, Shift shift, Energy energy) {
    _audit('Edit workout check-in',
        {'id': w.id, 'shift': w.shift.name, 'energy': w.energy.name});
    w
      ..shift = shift
      ..energy = energy;
    final previous = w.checkIn;
    if (previous != null) {
      w.checkIn = SessionCheckIn(
          shift: shift,
          energy: energy,
          timeMinutes: previous.timeMinutes,
          sleepHours: previous.sleepHours,
          notes: previous.notes,
          recentTrainingNote: previous.recentTrainingNote,
          painNote: previous.painNote);
    }
    _changed();
  }

  void finishWorkout(Workout w) {
    w.end = DateTime.now();
    _changed();
  }

  void deleteWorkout(Workout w) {
    if (!workouts.remove(w)) return;
    deletedWorkouts.insert(0, w);
    _audit('Delete workout', w.toJson());
    _changed();
  }

  void restoreWorkout(Workout w) {
    if (w.isActive && activeWorkout != null) {
      throw StateError('Finish the active workout before restoring this one.');
    }
    if (!deletedWorkouts.remove(w)) return;
    workouts.add(w);
    workouts.sort((a, b) => b.start.compareTo(a.start));
    _audit('Restore workout', {'id': w.id});
    _changed();
  }

  void updateWorkoutDate(Workout w, DateTime date) {
    _audit(
        'Edit workout date', {'id': w.id, 'before': w.start.toIso8601String()});
    final duration = w.duration;
    w.start =
        DateTime(date.year, date.month, date.day, w.start.hour, w.start.minute);
    if (w.end != null) w.end = w.start.add(duration);
    workouts.sort((a, b) => b.start.compareTo(a.start));
    _changed();
  }

  void saveRecovery(RecoveryDay day) {
    _audit('Edit soreness ${day.day}', recoveryDays[day.day]?.toJson() ?? {});
    recoveryDays[day.day] = day;
    _changed();
  }

  void saveProfile(Map<String, String> profile) {
    if (mapEquals(trainingProfile, profile)) return;
    trainingProfile = Map.of(profile);
    _changed();
  }

  /// Conversation writes do not make their own training evidence stale.
  bool saveCoachExchange(String question, Map<String, dynamic> reply,
      {required int sourceRevision, required String sourceDay}) {
    if (sourceRevision != revision) return false;
    coachConversation.addAll([
      {'role': 'user', 'content': question},
      {'role': 'assistant', 'content': jsonEncode(reply)}
    ]);
    while (coachConversation.length > 40) {
      coachConversation.removeRange(0, 2);
    }
    coachDraft = jsonDecode(jsonEncode(reply)) as Map<String, dynamic>;
    coachDraftRevision = sourceRevision;
    coachDraftDay = sourceDay;
    _changed(trainingChanged: false);
    return true;
  }

  void clearCoachConversation() {
    coachConversation.clear();
    coachDraft = null;
    coachDraftRevision = null;
    coachDraftDay = null;
    _changed(trainingChanged: false);
  }

  void updateTarget(WorkoutExercise exercise, ExerciseTarget? target) {
    _audit('Edit session target', {
      'exerciseId': exercise.exerciseId,
      'target': exercise.target?.toJson()
    });
    exercise.target = target;
    _changed();
  }

  /// Replace remaining intentions while retaining every completed set.
  /// Targets describe totals for this session, never additional sets.
  void applyPlanToActiveWorkout(Workout workout, List<WorkoutExercise> plan,
      {String? planTitle,
      required int sourceRevision,
      required String sourceDay}) {
    if (!identical(workout, activeWorkout) ||
        sourceRevision != revision ||
        sourceDay != dayKey(DateTime.now())) {
      throw StateError(
          'Your session has changed. Ask your coach to refresh the plan.');
    }
    final desired = [
      for (final e in plan) WorkoutExercise.fromJson(e.toJson())
    ];
    if (desired.isEmpty ||
        desired.length > 12 ||
        desired.any((e) =>
            e.sets.isNotEmpty ||
            e.target == null ||
            !exercises.any((def) => def.id == e.exerciseId)) ||
        desired.map((e) => e.exerciseId).toSet().length != desired.length) {
      throw const FormatException('Invalid remaining-session plan');
    }
    final existing = {for (final e in workout.exercises) e.exerciseId: e};
    _audit('Adjust remaining session', workout.toJson());
    final next = <WorkoutExercise>[];
    for (final planned in desired) {
      final entry = existing.remove(planned.exerciseId) ??
          WorkoutExercise(planned.exerciseId);
      entry.target = planned.target;
      next.add(entry);
    }
    for (final entry in existing.values) {
      if (entry.sets.isNotEmpty) {
        entry.target = null;
        next.add(entry);
      }
    }
    workout.exercises
      ..clear()
      ..addAll(next);
    workout.planTitle = planTitle;
    _changed();
  }

  void restoreBackup(Map<String, dynamic> data) {
    // Parse everything in isolation before replacing any current records.
    final parsed = GymaStore.fromJson(data);
    final nextRevision = revision + 1;
    _readJson(parsed.toJson());
    revision = nextRevision;
    coachDraftRevision = null;
    restoreGeneration++;
    _changed();
  }

  void _audit(String action, Map<String, dynamic> before) {
    editHistory.insert(0, {
      'action': action,
      'at': DateTime.now().toUtc().toIso8601String(),
      'before': jsonDecode(jsonEncode(before))
    });
    if (editHistory.length > 100) editHistory.removeLast();
  }

  void addExercise(Workout w, String exerciseId) {
    w.exercises.add(WorkoutExercise(exerciseId));
    _changed();
  }

  void removeExercise(Workout w, WorkoutExercise e) {
    _audit('Remove exercise', {'workoutId': w.id, ...e.toJson()});
    w.exercises.remove(e);
    _changed();
  }

  void addSet(WorkoutExercise e, WorkSet set) {
    e.sets.add(set);
    _changed();
  }

  void updateSet(WorkoutExercise e, int index, WorkSet set) {
    _audit('Edit set', {
      'exerciseId': e.exerciseId,
      'index': index,
      ...e.sets[index].toJson()
    });
    e.sets[index] = set;
    _changed();
  }

  void removeSet(WorkoutExercise e, int index) {
    _audit('Remove set', {
      'exerciseId': e.exerciseId,
      'index': index,
      ...e.sets[index].toJson()
    });
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
