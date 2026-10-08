import 'dart:convert';
import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:gyma/format.dart';
import 'package:gyma/main.dart';
import 'package:gyma/models.dart';
import 'package:gyma/store.dart';

void main() {
  testWidgets('populated dashboard fits a small phone with large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final now = DateTime.now();
    for (var i = 0; i < 2; i++) {
      final date = now.subtract(Duration(days: i + 1));
      store.workouts.add(Workout(
          id: 'preview-$i',
          start: date,
          end: date.add(const Duration(hours: 1)),
          shift: Shift.off,
          energy: Energy.good,
          exercises: [
            WorkoutExercise('bench_press', [WorkSet(i == 0 ? 65 : 60, 8)]),
            WorkoutExercise('squat', [WorkSet(i == 0 ? 70 : 80, 8)])
          ]));
    }
    addTearDown(store.workouts.clear);
    await tester.pumpWidget(const GymaApp());
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Lower loads'), 200,
        scrollable: find
            .descendant(
                of: find.byType(ListView).first,
                matching: find.byType(Scrollable))
            .first);
    await tester.pumpAndSettle();
    expect(find.text('Lower loads'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home screen shows empty state', (tester) async {
    await tester.pumpWidget(const GymaApp());
    expect(find.text('Your training'), findsOneWidget);
    expect(find.text('Start workout'), findsOneWidget);
  });

  testWidgets('start workout asks for shift and energy', (tester) async {
    await tester.pumpWidget(const GymaApp());
    await tester.tap(find.text('Start workout'));
    await tester.pumpAndSettle();
    expect(find.text('Did you work today?'), findsOneWidget);
    expect(find.text('How is your energy?'), findsOneWidget);
  });

  test('workout totals and JSON round trip', () {
    final w = Workout(
      id: '1',
      start: DateTime(2026, 10, 8, 18),
      end: DateTime(2026, 10, 8, 19),
      shift: Shift.night,
      energy: Energy.good,
      exercises: [
        WorkoutExercise('bench_press', [WorkSet(60, 10), WorkSet(62.5, 8)]),
      ],
    );
    expect(w.totalSets, 2);
    expect(w.totalReps, 18);
    expect(w.volume, 1100);

    final copy = Workout.fromJson(
        jsonDecode(jsonEncode(w.toJson())) as Map<String, dynamic>);
    expect(copy.volume, 1100);
    expect(copy.shift, Shift.night);
    expect(copy.energy, Energy.good);
    expect(copy.duration, const Duration(hours: 1));
  });

  test('formatting', () {
    expect(fmtKg(60), '60');
    expect(fmtKg(62.5), '62.5');
    expect(fmtKg(31.25), '31.25');
    expect(fmtKg(1100), '1,100');
    expect(parseKg('62,5'), 62.5);
    expect(fmtDuration(const Duration(minutes: 65)), '1h 05m');
    expect(fmtClock(const Duration(seconds: 309)), '05:09');
  });
}
