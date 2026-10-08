import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gyma/analytics.dart';
import 'package:gyma/models.dart';
import 'package:gyma/store.dart';

Workout finished(String id, DateTime when, List<WorkSet> sets) => Workout(
    id: id,
    start: when,
    end: when.add(const Duration(minutes: 40)),
    shift: Shift.off,
    energy: Energy.good,
    exercises: [WorkoutExercise('bench_press', sets)]);

void main() {
  test('late coaching replies after restore cannot poison workout loading', () {
    final data = GymaStore()
      ..workouts.add(finished('before', DateTime(2026), [WorkSet(50, 8)]));
    final beforeRevision = data.revision;
    final reply = <String, dynamic>{
      'answer': 'Old reply',
      'rationale': <String>[],
      'limitations': <String>[],
      'evidenceWorkoutIds': ['before'],
      'plan': <dynamic>[]
    };
    data.restoreBackup({
      'version': 3,
      'workouts': [
        finished('restored', DateTime(2026), [WorkSet(40, 8)]).toJson()
      ]
    });
    expect(
        data.saveCoachExchange('Old question', reply,
            sourceRevision: beforeRevision, sourceDay: '2026-10-09'),
        isFalse);
    expect(data.coachDraft, isNull);
    final corruptedCache = data.toJson()..['coachDraft'] = reply;
    final copy = GymaStore.fromJson(corruptedCache);
    expect(copy.workouts.single.id, 'restored');
    expect(copy.coachDraft, isNull);
    expect(data.restoreGeneration, 1);
  });

  test('future-ending workouts are excluded consistently', () {
    final data = GymaStore();
    final now = DateTime(2026, 10, 9, 12);
    data.workouts.add(finished(
        'later', now.subtract(const Duration(minutes: 10)), [WorkSet(50, 8)]));
    expect(
        trainingContext(data, now)['historySummary']['totalFinishedWorkouts'],
        0);
    expect(weeklyReview(data, now)['sessions'], 0);
    expect(repTrends(data, now, 28), isEmpty);
  });

  test(
      'active plan revisions retain actual sets and remove only unstarted exercises',
      () {
    final data = GymaStore();
    final w = data.startWorkout(Shift.off, Energy.good);
    final logged = WorkoutExercise('bench_press',
        [WorkSet(50, 8, effort: SetEffort.challenging, isWarmup: false)]);
    w.exercises.addAll([logged, WorkoutExercise('squat')]);
    final newExerciseId = data.exercises
        .firstWhere((e) => !['bench_press', 'squat'].contains(e.id))
        .id;
    final day = DateTime.now();
    final sourceDay =
        '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    final revision = data.revision;
    data.applyPlanToActiveWorkout(
        w,
        [
          WorkoutExercise('bench_press')
            ..target =
                ExerciseTarget(sets: 2, repsMin: 8, repsMax: 10, loadKg: 50),
          WorkoutExercise(newExerciseId)
            ..target = ExerciseTarget(sets: 1, repsMin: 8, repsMax: 12),
        ],
        sourceRevision: revision,
        sourceDay: sourceDay,
        planTitle: 'Shorter session');
    expect(w.totalSets, 1);
    expect(identical(w.exercises.first, logged), isTrue);
    expect(logged.sets.single.kg, 50);
    expect(logged.target!.sets, 2);
    expect(w.exercises.any((e) => e.exerciseId == 'squat'), isFalse);
    expect(
        () => data.applyPlanToActiveWorkout(w, [],
            sourceRevision: revision, sourceDay: sourceDay),
        throwsStateError);
    data.applyPlanToActiveWorkout(
        w,
        [
          WorkoutExercise(newExerciseId)
            ..target = ExerciseTarget(sets: 1, repsMin: 8, repsMax: 12)
        ],
        sourceRevision: data.revision,
        sourceDay: sourceDay);
    expect(w.totalSets, 1);
    expect(logged.target, isNull);
    expect(w.exercises, contains(logged));
  });

  test(
      'long breaks preserve last session and exercise baselines outside recent window',
      () {
    final data = GymaStore();
    final now = DateTime(2026, 10, 9);
    data.workouts.addAll([
      finished('future', DateTime(2027), [WorkSet(100, 8)]),
      finished('older', DateTime(2026, 8, 1), [WorkSet(60, 8)]),
    ]);
    data.deletedWorkouts
        .add(finished('trash', DateTime(2026, 10, 8), [WorkSet(70, 8)]));
    final context = trainingContext(data, now);
    expect(context['workouts'], isEmpty);
    final history = context['historySummary'] as Map;
    expect(history['totalFinishedWorkouts'], 1);
    expect(history['daysSinceLastWorkout'], 69);
    expect(history['lastExerciseSessions'].single['workoutId'], 'older');
    expect(jsonEncode(context), isNot(contains('trash')));
    expect(jsonEncode(context), isNot(contains('future')));
  });

  test('coach sees current energy and preparation before anything is completed',
      () {
    final data = GymaStore();
    data.startWorkout(Shift.night, Energy.poor);
    final context = trainingContext(data, DateTime.now());
    expect(context['workouts'], isEmpty);
    expect(context['currentCheckIn']['energy'], 'poor');
    expect(context['activeWorkout']['shift'], 'night');
    final preparation = SessionCheckIn(
        shift: Shift.off,
        energy: Energy.medium,
        timeMinutes: 25,
        sleepHours: 5,
        painNote: 'Shoulder discomfort',
        recentTrainingNote: 'Trained elsewhere on Monday');
    final prepared =
        trainingContext(data, DateTime.now(), checkIn: preparation);
    expect(prepared['currentCheckIn']['timeMinutes'], 25);
    expect(prepared['currentCheckIn']['painNote'], 'Shoulder discomfort');
    expect(
        prepared['currentCheckIn']['recentTrainingNote'], contains('Monday'));
  });

  test('legacy backups preserve unknown effort and set type', () {
    final raw = finished('legacy', DateTime(2026), [WorkSet(50, 8)]).toJson();
    (raw['exercises'][0]['sets'][0] as Map).remove('effort');
    (raw['exercises'][0]['sets'][0] as Map).remove('isWarmup');
    final data = GymaStore.fromJson({
      'version': 1,
      'workouts': [raw]
    });
    final set = data.workouts.single.exercises.single.sets.single;
    expect(set.effort, isNull);
    expect(set.isWarmup, isNull);
    expect(data.toJson()['version'], 3);
  });

  test('accepting a plan preserves targets and never invents completed sets',
      () {
    final data = GymaStore();
    final exercise = WorkoutExercise('bench_press')
      ..target = ExerciseTarget(
          sets: 2,
          repsMin: 8,
          repsMax: 12,
          loadKg: 50,
          restSeconds: 90,
          reason: 'Start here');
    final w = data.startWorkout(Shift.off, Energy.good,
        exercises: [exercise],
        planTitle: 'Back to training',
        checkIn: SessionCheckIn(
            shift: Shift.off,
            energy: Energy.good,
            timeMinutes: 30,
            notes: 'Keep it short'));
    expect(w.totalSets, 0);
    expect(w.exercises.single.target!.repsMax, 12);
    expect(() => data.startWorkout(Shift.off, Energy.good), throwsStateError);
    data.addSet(w.exercises.single,
        WorkSet(50, 10, effort: SetEffort.challenging, isWarmup: false));
    expect(exercise.sets, isEmpty);
    final copy = GymaStore.fromJson(
        jsonDecode(jsonEncode(data.toJson())) as Map<String, dynamic>);
    expect(copy.workouts.single.checkIn!.notes, 'Keep it short');
    expect(copy.workouts.single.planTitle, 'Back to training');
    expect(copy.workouts.single.exercises.single.sets.single.effort,
        SetEffort.challenging);
    data.updateCheckIn(w, Shift.night, Energy.poor);
    expect(w.checkIn!.energy, Energy.poor);
    expect(w.checkIn!.timeMinutes, 30);
  });

  test('plans containing completed sets are rejected before starting', () {
    final data = GymaStore();
    expect(
        () => data.startWorkout(Shift.off, Energy.good, exercises: [
              WorkoutExercise('bench_press', [WorkSet(50, 8)])
            ]),
        throwsFormatException);
    expect(data.workouts, isEmpty);
  });

  test('saved coach memory persists without making fresh advice stale', () {
    final data = GymaStore();
    final reply = <String, dynamic>{
      'answer': 'How do you feel?',
      'rationale': <String>[],
      'evidenceWorkoutIds': <String>[],
      'limitations': <String>[],
      'plan': <dynamic>[]
    };
    final revision = data.revision;
    data.saveCoachExchange('Back after a break', reply,
        sourceRevision: revision, sourceDay: '2026-10-09');
    expect(data.revision, revision);
    final copy = GymaStore.fromJson(
        jsonDecode(jsonEncode(data.toJson())) as Map<String, dynamic>);
    expect(copy.coachConversation.first['content'], 'Back after a break');
    expect(copy.coachDraftRevision, copy.revision);
    copy.saveProfile({'goal': 'Build muscle'});
    expect(copy.coachDraftRevision, isNot(copy.revision));
    copy.restoreBackup(data.toJson());
    expect(copy.coachDraftRevision, isNull);
    copy.clearCoachConversation();
    expect(copy.coachConversation, isEmpty);
    expect(copy.coachDraft, isNull);
  });

  test('rep gains are recognized and marked warmups do not create load records',
      () {
    final data = GymaStore();
    final now = DateTime(2026, 10, 9);
    data.workouts.addAll([
      finished('new', DateTime(2026, 10, 8),
          [WorkSet(60, 10, isWarmup: false), WorkSet(100, 8, isWarmup: true)]),
      finished('old', DateTime(2026, 10, 6), [WorkSet(60, 8, isWarmup: false)]),
    ]);
    expect(exerciseTrends(data, now, 7), isEmpty);
    expect(repTrends(data, now, 7).single.delta, 2);
    final week = weeklyReview(data, now);
    expect(week['workingSets'], 2);
    expect(week['warmupSets'], 1);
  });

  test('invalid targets and effort fail import without replacing existing data',
      () {
    final data = GymaStore()
      ..workouts.add(finished('keep', DateTime(2026), [WorkSet(50, 8)]));
    final broken =
        jsonDecode(jsonEncode(data.toJson())) as Map<String, dynamic>;
    broken['workouts'][0]['exercises'][0]['sets'][0]['effort'] = 'invented';
    expect(() => data.restoreBackup(broken), throwsA(anything));
    expect(data.workouts.single.id, 'keep');
    expect(() => ExerciseTarget(sets: 2, repsMin: 12, repsMax: 8),
        throwsFormatException);
  });
}
