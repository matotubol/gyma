import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gyma/format.dart';
import 'package:gyma/main.dart';
import 'package:gyma/models.dart';

void main() {
  testWidgets('home screen shows empty state', (tester) async {
    await tester.pumpWidget(const GymaApp());
    expect(find.text('No workouts yet'), findsOneWidget);
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
