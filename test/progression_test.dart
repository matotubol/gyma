import 'package:flutter_test/flutter_test.dart';
import 'package:gyma/models.dart';
import 'package:gyma/progression.dart';

WorkoutExercise planned(List<WorkSet> sets, {double? loadKg = 40}) =>
    WorkoutExercise('bench_press', sets)
      ..target =
          ExerciseTarget(sets: 2, repsMin: 8, repsMax: 12, loadKg: loadKg);

WorkSet working(int reps,
        {double kg = 40, SetEffort? effort = SetEffort.easy}) =>
    WorkSet(kg, reps, effort: effort, isWarmup: false);

void main() {
  test('only easy, complete working sets at the top justify a load suggestion',
      () {
    final exercise = planned([
      WorkSet(10, 6, isWarmup: true),
      working(12),
      working(12),
    ]);
    final before = exercise.toJson();
    final suggestion = nextSessionSuggestion(exercise, energy: Energy.good);
    expect(suggestion.action, ProgressionAction.considerLoad);
    expect(suggestion.title, contains('smallest available'));
    expect(exercise.toJson(), before,
        reason: 'Advice must not change records or targets');
  });

  test('easy sets within the range suggest reps before load', () {
    expect(
        nextSessionSuggestion(planned([working(8), working(10)]),
                energy: Energy.good)
            .action,
        ProgressionAction.addReps);
  });

  test('missing sets, low reps, or difficult sets do not suggest more load',
      () {
    for (final sets in [
      [working(12)],
      [working(12), working(7)],
      [working(12), working(12, effort: SetEffort.challenging)],
      [working(12), working(12, effort: SetEffort.limit)],
    ]) {
      expect(nextSessionSuggestion(planned(sets), energy: Energy.good).action,
          ProgressionAction.hold);
    }
  });

  test('pain, low energy and a long gap override easy high-rep sets', () {
    final exercise = planned([working(12), working(12)]);
    expect(
        nextSessionSuggestion(exercise, energy: Energy.good, hasPain: true)
            .action,
        ProgressionAction.recover);
    expect(nextSessionSuggestion(exercise, energy: Energy.poor).action,
        ProgressionAction.recover);
    expect(
        nextSessionSuggestion(exercise,
                energy: Energy.good, daysSincePrevious: 14)
            .action,
        ProgressionAction.recover);
    expect(
        nextSessionSuggestion(exercise,
                energy: Energy.good, daysSincePrevious: 13)
            .action,
        ProgressionAction.considerLoad);
  });

  test(
      'unknown effort and unknown historical set type remain insufficient context',
      () {
    final legacy = WorkSet.fromJson({'kg': 40, 'reps': 12});
    expect(legacy.isWarmup, isNull);
    expect(legacy.effort, isNull);
    for (final sets in [
      [legacy, working(12)],
      [working(12), working(12, effort: null)],
      [WorkSet(40, 12, effort: SetEffort.easy), working(12)],
      [WorkSet(10, 6, isWarmup: true)],
      <WorkSet>[],
    ]) {
      expect(nextSessionSuggestion(planned(sets), energy: Energy.good).action,
          ProgressionAction.observe);
    }
    expect(legacy.isWarmup, isNull,
        reason: 'Advice must preserve unknown historical labels');
  });

  test('warm-up sets cannot satisfy a working-set target', () {
    final exercise = planned([
      WorkSet(40, 12, effort: SetEffort.easy, isWarmup: true),
      working(12),
    ]);
    expect(nextSessionSuggestion(exercise, energy: Energy.good).action,
        ProgressionAction.hold);
  });

  test('varying or lower loads do not justify increasing the planned load', () {
    for (final sets in [
      [working(12, kg: 20), working(12, kg: 20)],
      [working(12, kg: 40), working(12, kg: 50)],
    ]) {
      expect(nextSessionSuggestion(planned(sets), energy: Energy.good).action,
          ProgressionAction.hold);
    }
  });

  test('without a target, sets are a baseline rather than a load prescription',
      () {
    final exercise = WorkoutExercise('bench_press', [working(12), working(12)]);
    expect(nextSessionSuggestion(exercise, energy: Energy.good).action,
        ProgressionAction.observe);
  });
}
