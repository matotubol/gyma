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

  testWidgets('logger seeds the previous session and validates weight and reps',
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
    expect(fieldValue(tester, weightField), '60');
    expect(fieldValue(tester, repsField), '8');
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
    await tester.tap(find.byKey(const ValueKey('logged-set-1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(weightField), '100');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(entry.sets.last.kg, 65);
    expect(fieldValue(tester, weightField), '70');
    await tester.tap(find.byKey(const ValueKey('logged-set-1')));
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
