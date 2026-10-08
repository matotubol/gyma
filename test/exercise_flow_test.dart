import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyma/main.dart';
import 'package:gyma/models.dart';
import 'package:gyma/screens/active_workout_screen.dart';
import 'package:gyma/screens/exercise_log_screen.dart';
import 'package:gyma/screens/exercise_picker_screen.dart';
import 'package:gyma/screens/workout_detail_screen.dart';
import 'package:gyma/store.dart';

const weightField = ValueKey('set-weight');
const repsField = ValueKey('set-reps');
const saveSet = ValueKey('save-set');

Workout session({bool finished = false, List<WorkoutExercise>? exercises}) {
  final start = DateTime.now().subtract(const Duration(hours: 1));
  return Workout(
    id: 'session',
    start: start,
    end: finished ? DateTime.now() : null,
    shift: Shift.off,
    energy: Energy.good,
    exercises: exercises,
  );
}

void smallPhone(WidgetTester tester, {double scale = 1.3}) {
  tester.view.physicalSize = const Size(320, 740);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

String fieldValue(WidgetTester tester, Key key) =>
    tester.widget<TextField>(find.byKey(key)).controller!.text;

void main() {
  setUp(() {
    store.workouts.clear();
    store.customExercises.clear();
    store.editHistory.clear();
  });
  tearDown(() {
    store.workouts.clear();
    store.customExercises.clear();
    store.editHistory.clear();
  });

  testWidgets(
      'selecting an exercise opens its own logger and keeps workout compact',
      (tester) async {
    smallPhone(tester);
    final workout = session();
    store.workouts.add(workout);
    await tester.pumpWidget(const GymaApp());
    await tester.tap(find.text('Resume workout'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add exercise'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pick-bench_press')));
    await tester.pumpAndSettle();
    expect(find.byType(ExerciseLogScreen), findsOneWidget);
    expect(find.byType(ExercisePickerScreen), findsNothing);
    expect(find.byKey(weightField).hitTestable(), findsOneWidget);
    await tester.enterText(find.byKey(weightField), '62,5');
    await tester.enterText(find.byKey(repsField), '8');
    await tester.tap(find.byKey(saveSet));
    await tester.pumpAndSettle();
    expect(workout.exercises.single.sets.single.kg, 62.5);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(ActiveWorkoutScreen), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('1 set · Last: 62.5 kg × 8'), findsOneWidget);
    await tester.tap(find.text('Bench press'));
    await tester.pumpAndSettle();
    expect(fieldValue(tester, weightField), '62.5');
    expect(find.text('62.5 kg × 8 reps'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'legacy loads remain reference only and inputs validate weight and reps',
      (tester) async {
    final previous = session(finished: true, exercises: [
      WorkoutExercise('bench_press', [WorkSet(60, 8)])
    ]);
    previous.start = previous.start.subtract(const Duration(days: 1));
    previous.end = previous.end!.subtract(const Duration(days: 1));
    final workout = session(exercises: [WorkoutExercise('bench_press')]);
    store.workouts.addAll([workout, previous]);
    await tester.pumpWidget(MaterialApp(
        home: ExerciseLogScreen(
            workout: workout, entry: workout.exercises.single)));
    expect(fieldValue(tester, weightField), isEmpty);
    expect(fieldValue(tester, repsField), isEmpty);
    await tester.enterText(find.byKey(weightField), '');
    await tester.enterText(find.byKey(repsField), '0');
    await tester.tap(find.byKey(saveSet));
    await tester.pumpAndSettle();
    expect(workout.totalSets, 0);
    expect(find.text('Enter a valid weight'), findsOneWidget);
    expect(find.text('Enter at least 1 rep'), findsOneWidget);
    await tester.enterText(find.byKey(weightField), '0');
    await tester.enterText(find.byKey(repsField), '12');
    await tester.tap(find.byKey(saveSet));
    await tester.pumpAndSettle();
    expect(workout.exercises.single.sets.single.kg, 0);
    expect(workout.exercises.single.sets.single.reps, 12);
    expect(tester.takeException(), isNull);
  });

  testWidgets('returning after a break keeps old loads as reference only',
      (tester) async {
    final previous = session(finished: true, exercises: [
      WorkoutExercise('bench_press', [WorkSet(80, 8)])
    ]);
    previous.start = previous.start.subtract(const Duration(days: 28));
    previous.end = previous.end!.subtract(const Duration(days: 28));
    final entry = WorkoutExercise('bench_press')
      ..target = ExerciseTarget(sets: 2, repsMin: 8, repsMax: 12);
    final workout = session(exercises: [entry]);
    store.workouts.addAll([workout, previous]);
    await tester.pumpWidget(
        MaterialApp(home: ExerciseLogScreen(workout: workout, entry: entry)));
    expect(fieldValue(tester, weightField), isEmpty);
    expect(fieldValue(tester, repsField), '8');
    expect(find.textContaining('Last time ('), findsOneWidget);
    expect(entry.sets, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'today’s 50 kg target wins over an older 80 kg load after a break',
      (tester) async {
    final previous = session(finished: true, exercises: [
      WorkoutExercise('bench_press', [WorkSet(80, 12)])
    ]);
    previous.start = previous.start.subtract(const Duration(days: 28));
    previous.end = previous.end!.subtract(const Duration(days: 28));
    final entry = WorkoutExercise('bench_press')
      ..target = ExerciseTarget(sets: 2, repsMin: 8, repsMax: 10, loadKg: 50);
    final workout = session(exercises: [entry])..energy = Energy.poor;
    store.workouts.addAll([workout, previous]);
    await tester.pumpWidget(
        MaterialApp(home: ExerciseLogScreen(workout: workout, entry: entry)));
    expect(fieldValue(tester, weightField), '50');
    expect(fieldValue(tester, repsField), '8');
    expect(entry.sets, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'recent load reuse requires a known working set with non-limit effort',
      (tester) async {
    for (final effort in [SetEffort.challenging, SetEffort.limit, null]) {
      final previous = session(finished: true, exercises: [
        WorkoutExercise('bench_press', [
          WorkSet(20, 12, isWarmup: true, effort: SetEffort.easy),
          WorkSet(60, 8, isWarmup: false, effort: effort),
        ])
      ]);
      previous.start = previous.start.subtract(const Duration(days: 1));
      previous.end = previous.end!.subtract(const Duration(days: 1));
      final entry = WorkoutExercise('bench_press');
      final workout = session(exercises: [entry]);
      store.workouts
        ..clear()
        ..addAll([workout, previous]);
      await tester.pumpWidget(
          MaterialApp(home: ExerciseLogScreen(workout: workout, entry: entry)));
      expect(fieldValue(tester, weightField),
          effort == SetEffort.challenging ? '60' : isEmpty);
      expect(entry.sets, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('target load stays blank when coach leaves load to the user',
      (tester) async {
    final previous = session(finished: true, exercises: [
      WorkoutExercise('bench_press',
          [WorkSet(80, 8, isWarmup: false, effort: SetEffort.easy)])
    ]);
    previous.start = previous.start.subtract(const Duration(days: 1));
    previous.end = previous.end!.subtract(const Duration(days: 1));
    final entry = WorkoutExercise('bench_press')
      ..target = ExerciseTarget(sets: 2, repsMin: 8, repsMax: 12);
    final workout = session(exercises: [entry]);
    store.workouts.addAll([workout, previous]);
    await tester.pumpWidget(
        MaterialApp(home: ExerciseLogScreen(workout: workout, entry: entry)));
    expect(fieldValue(tester, weightField), isEmpty);
    expect(fieldValue(tester, repsField), '8');
    expect(tester.takeException(), isNull);
  });

  testWidgets('current working sets precede targets while warm-ups do not',
      (tester) async {
    for (final hasWorkingSet in [false, true]) {
      final entry = WorkoutExercise('bench_press', [
        if (hasWorkingSet) WorkSet(55, 10, isWarmup: false),
        WorkSet(20, 12, isWarmup: true),
      ])
        ..target = ExerciseTarget(sets: 2, repsMin: 8, repsMax: 12, loadKg: 50);
      final workout = session(exercises: [entry]);
      await tester.pumpWidget(
          MaterialApp(home: ExerciseLogScreen(workout: workout, entry: entry)));
      expect(fieldValue(tester, weightField), hasWorkingSet ? '55' : '50');
      expect(fieldValue(tester, repsField), hasWorkingSet ? '10' : '8');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('effort and warm-up are saved only for the rated set',
      (tester) async {
    smallPhone(tester);
    final entry = WorkoutExercise('bench_press');
    final workout = session(exercises: [entry]);
    store.workouts.add(workout);
    await tester.pumpWidget(
        MaterialApp(home: ExerciseLogScreen(workout: workout, entry: entry)));
    await tester.enterText(find.byKey(weightField), '40');
    await tester.enterText(find.byKey(repsField), '8');
    await tester.tap(find.byKey(const ValueKey('set-context')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(SetEffort.easy.label));
    await tester.ensureVisible(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile));
    await tester.ensureVisible(find.text('Use for this set'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use for this set'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(saveSet));
    await tester.pumpAndSettle();
    expect(entry.sets.single.effort, SetEffort.easy);
    expect(entry.sets.single.isWarmup, isTrue);
    await tester.tap(find.byKey(saveSet));
    await tester.pumpAndSettle();
    expect(entry.sets.last.effort, isNull);
    expect(entry.sets.last.isWarmup, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('logging a warm-up returns the next working set to its target',
      (tester) async {
    final entry = WorkoutExercise('bench_press')
      ..target = ExerciseTarget(sets: 2, repsMin: 8, repsMax: 12, loadKg: 50);
    final workout = session(exercises: [entry]);
    await tester.pumpWidget(
        MaterialApp(home: ExerciseLogScreen(workout: workout, entry: entry)));
    await tester.enterText(find.byKey(weightField), '20');
    await tester.enterText(find.byKey(repsField), '12');
    await tester.tap(find.byKey(const ValueKey('set-context')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile));
    await tester.tap(find.text('Use for this set'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(saveSet));
    await tester.pumpAndSettle();
    expect(entry.sets.single.kg, 20);
    expect(entry.sets.single.isWarmup, isTrue);
    expect(fieldValue(tester, weightField), '50');
    expect(fieldValue(tester, repsField), '8');
    expect(tester.takeException(), isNull);
  });

  testWidgets('adjusting a target does not create or change logged sets',
      (tester) async {
    final entry = WorkoutExercise('bench_press')
      ..target = ExerciseTarget(sets: 2, repsMin: 8, repsMax: 12);
    final workout = session(exercises: [entry]);
    store.workouts.add(workout);
    await tester.pumpWidget(
        MaterialApp(home: ExerciseLogScreen(workout: workout, entry: entry)));
    await tester.ensureVisible(find.byKey(const ValueKey('edit-target')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('edit-target')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('target-sets')), '3');
    await tester.tap(find.text('Save target'));
    await tester.pumpAndSettle();
    expect(entry.target!.sets, 3);
    expect(entry.sets, isEmpty);
    expect(workout.totalSets, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'editing a legacy set does not silently assign effort or set type',
      (tester) async {
    final entry = WorkoutExercise('bench_press', [WorkSet(40, 8)]);
    final workout = session(finished: true, exercises: [entry]);
    await tester.pumpWidget(
        MaterialApp(home: ExerciseLogScreen(workout: workout, entry: entry)));
    await tester.ensureVisible(find.byKey(const ValueKey('logged-set-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('logged-set-0')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(repsField), '9');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(entry.sets.single.reps, 9);
    expect(entry.sets.single.effort, isNull);
    expect(entry.sets.single.isWarmup, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'editing a completed workout supports cancel, save and deleting a preceding set',
      (tester) async {
    final entry =
        WorkoutExercise('bench_press', [WorkSet(60, 8), WorkSet(65, 6)]);
    final workout = session(finished: true, exercises: [entry]);
    store.workouts.add(workout);
    await tester.pumpWidget(
        MaterialApp(home: ExerciseLogScreen(workout: workout, entry: entry)));
    await tester.enterText(find.byKey(weightField), '70');
    await tester.ensureVisible(find.byKey(const ValueKey('logged-set-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('logged-set-1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(weightField), '100');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(entry.sets.last.kg, 65);
    expect(fieldValue(tester, weightField), '70');
    await tester.ensureVisible(find.byKey(const ValueKey('logged-set-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('logged-set-1')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Delete set 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete set 1'));
    await tester.pumpAndSettle();
    expect(find.text('Edit set 1'), findsOneWidget);
    await tester.enterText(find.byKey(weightField), '67.5');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(entry.sets.single.kg, 67.5);
    expect(entry.sets.single.reps, 6);
    expect(workout.isActive, isFalse);
    await tester.tap(find.byKey(const ValueKey('logged-set-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete set 1'));
    await tester.pumpAndSettle();
    expect(entry.sets, isEmpty);
    expect(find.text('Log set'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'long set history never pushes inputs down and keyboard leaves Log set visible',
      (tester) async {
    smallPhone(tester);
    final entry = WorkoutExercise(
        'bench_press', List.generate(20, (_) => WorkSet(60, 8)));
    final workout = session(exercises: [entry]);
    store.workouts.add(workout);
    await tester.pumpWidget(const GymaApp());
    await tester.tap(find.text('Resume workout'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bench press'));
    await tester.pumpAndSettle();
    final position = tester.getTopLeft(find.byKey(weightField));
    await tester.drag(
        find.byKey(const PageStorageKey('logged-sets')), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(weightField)), position);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.tap(find.byKey(weightField));
    await tester.pumpAndSettle();
    expect(find.byKey(saveSet).hitTestable(), findsOneWidget);
    expect(
        tester.getBottomRight(find.byKey(saveSet)).dy, lessThanOrEqualTo(440));
    await tester.tap(find.byKey(saveSet));
    await tester.pumpAndSettle();
    expect(entry.sets, hasLength(21));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('picker searches, filters and prevents duplicate additions',
      (tester) async {
    smallPhone(tester);
    await tester.pumpWidget(const MaterialApp(
        home: ExercisePickerScreen(alreadyAdded: {'bench_press'})));
    expect(
        tester
            .widget<ListTile>(find.byKey(const ValueKey('pick-bench_press')))
            .enabled,
        isFalse);
    await tester.enterText(find.byType(TextField), 'incline');
    await tester.pumpAndSettle();
    expect(find.text('Incline bench press'), findsOneWidget);
    expect(find.text('Bench press'), findsNothing);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Back'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Back'));
    await tester.pumpAndSettle();
    expect(find.text('Deadlift'), findsOneWidget);
    expect(find.text('Bench press'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('finished sessions remain editable through the focused flow',
      (tester) async {
    smallPhone(tester);
    final entry = WorkoutExercise('bench_press', [WorkSet(60, 8)]);
    final workout = session(exercises: [entry])..shift = Shift.afternoon;
    store.workouts.add(workout);
    await tester.pumpWidget(const GymaApp());
    await tester.tap(find.text('Resume workout'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finish'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Finish'));
    await tester.pumpAndSettle();
    expect(workout.isActive, isFalse);
    expect(find.byType(WorkoutDetailScreen), findsOneWidget);
    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bench press'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('logged-set-0')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(weightField), '65');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(workout.volume, 520);
    expect(workout.isActive, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('landscape and large text keep saved sets accessible',
      (tester) async {
    smallPhone(tester, scale: 2);
    tester.view.physicalSize = const Size(740, 320);
    final entry = WorkoutExercise('bench_press', [WorkSet(60, 8)]);
    final workout = session(exercises: [entry]);
    await tester.pumpWidget(
        MaterialApp(home: ExerciseLogScreen(workout: workout, entry: entry)));
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('logged-set-0')), 150,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('logged-set-0')).hitTestable(),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('logged-set-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(weightField).hitTestable(), findsOneWidget);
    expect(fieldValue(tester, weightField), '60');
    expect(tester.takeException(), isNull);
  });

  testWidgets('removing an exercise confirms and returns to the workout',
      (tester) async {
    final entry = WorkoutExercise('bench_press', [WorkSet(60, 8)]);
    final workout = session(exercises: [entry]);
    store.workouts.add(workout);
    await tester.pumpWidget(const GymaApp());
    await tester.tap(find.text('Resume workout'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bench press'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Exercise options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove exercise'));
    await tester.pumpAndSettle();
    expect(workout.exercises, hasLength(1));
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(workout.exercises, isEmpty);
    expect(find.byType(ActiveWorkoutScreen), findsOneWidget);
    expect(find.byType(ExerciseLogScreen), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
