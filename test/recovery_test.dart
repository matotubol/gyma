import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyma/analytics.dart';
import 'package:gyma/models.dart';
import 'package:gyma/recovery.dart';
import 'package:gyma/screens/recovery_screen.dart';
import 'package:gyma/store.dart';

Workout workout(String id, DateTime date, double kg, {int reps = 8}) => Workout(
  id: id, start: date, end: date.add(const Duration(hours: 1)),
  shift: Shift.off, energy: Energy.good,
  exercises: [WorkoutExercise('bench_press', [WorkSet(kg, reps)])]);

void main() {
  test('legacy data migrates without inventing soreness', () {
    final old = {'version': 1, 'customExercises': [], 'workouts': [workout('w1', DateTime(2026, 10, 7), 60).toJson()]};
    final data = GymaStore.fromJson(old);
    expect(data.workouts.single.id, 'w1');
    expect(data.recoveryDays, isEmpty);
    expect(data.toJson()['version'], 3);
  });

  test('daily soreness preserves unknown vs none, pain and edits across restart', () {
    final data = GymaStore();
    data.saveRecovery(RecoveryDay(day: '2026-10-08', muscles: {
      BodyArea.quads: Soreness.severe, BodyArea.chest: Soreness.none}, painAreas: {BodyArea.shoulders}));
    data.saveRecovery(RecoveryDay(day: '2026-10-08', muscles: {
      BodyArea.quads: Soreness.mild, BodyArea.chest: Soreness.none}, painAreas: {BodyArea.shoulders}));
    final copy = GymaStore.fromJson(jsonDecode(jsonEncode(data.toJson())) as Map<String, dynamic>);
    expect(copy.recoveryDays.length, 1);
    final day = copy.recoveryDays['2026-10-08']!;
    expect(day.muscles[BodyArea.chest], Soreness.none);
    expect(day.muscles[BodyArea.quads], Soreness.mild);
    expect(day.muscles[BodyArea.biceps], isNull);
    expect(day.painAreas, contains(BodyArea.shoulders));
    expect(copy.editHistory.first['before']['muscles']['quads'], 'severe');
    expect(copy.workouts, isEmpty);
  });

  test('correcting a set recalculates trends; changed reps are not a decline', () {
    final data = GymaStore();
    final now = DateTime(2026, 10, 8, 20);
    final recent = workout('new', DateTime(2026, 10, 8), 800);
    data.workouts.addAll([recent, workout('old', DateTime(2026, 10, 6), 60)]);
    expect(exerciseTrends(data, now, 7).single.delta, 740);
    data.updateSet(recent.exercises.single, 0, WorkSet(65, 8));
    expect(exerciseTrends(data, now, 7).single.delta, 5);
    data.updateSet(recent.exercises.single, 0, WorkSet(50, 12));
    expect(exerciseTrends(data, now, 7), isEmpty);
  });

  test('context excludes trash, future data and stale daily recovery', () {
    final data = GymaStore();
    final removed = workout('trash', DateTime(2026, 10, 7), 60);
    data.workouts.addAll([workout('future', DateTime(2026, 10, 10), 70), removed]);
    data.deleteWorkout(removed);
    data.saveRecovery(RecoveryDay(day: '2026-10-07', muscles: {BodyArea.quads: Soreness.severe}));
    final context = trainingContext(data, DateTime(2026, 10, 8, 20));
    expect(context['workouts'], isEmpty);
    expect(context['todayRecovery'], isNull);
    expect(context['dailyRecovery'], hasLength(1));
    expect(context.containsKey('editHistory'), isFalse);
    final copy = GymaStore.fromJson(data.toJson());
    copy.restoreWorkout(copy.deletedWorkouts.single);
    expect(copy.finishedWorkouts.map((w) => w.id), contains('trash'));
  });

  test('invalid backup leaves current data untouched', () {
    final data = GymaStore()..workouts.add(workout('keep', DateTime(2026), 60));
    expect(() => data.restoreBackup({'version': 2, 'workouts': [{'invalid': true}]}), throwsA(anything));
    expect(data.workouts.single.id, 'keep');
  });

  testWidgets('soreness is optional and can be cleared without recording zero', (tester) async {
    store.recoveryDays.clear();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: RecoveryScreen()));
    await tester.tap(find.text('Mild').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(store.recoveryDays[dayKey(DateTime.now())]!.muscles[BodyArea.chest], Soreness.mild);
    await tester.tap(find.text('Mild').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(store.recoveryDays[dayKey(DateTime.now())]!.muscles[BodyArea.chest], isNull);
    expect(tester.takeException(), isNull);
    store.recoveryDays.clear();
  });
}
