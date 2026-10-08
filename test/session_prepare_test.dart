import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyma/coach_client.dart';
import 'package:gyma/models.dart';
import 'package:gyma/recovery.dart';
import 'package:gyma/screens/coach_tab.dart';
import 'package:gyma/screens/session_prepare_screen.dart';
import 'package:gyma/store.dart';

Map<String, dynamic> response({int sets = 3}) => {
      'status': 'completed',
      'output': [
        {
          'type': 'message',
          'content': [
            {
              'type': 'output_text',
              'text': jsonEncode({
                'answer':
                    'Let’s keep this manageable. Start with a comfortable effort.',
                'rationale': ['Fits your available time'],
                'limitations': ['Technique is not observed'],
                'evidenceWorkoutIds': <String>[],
                'plan': [
                  {
                    'title': 'A steady return',
                    'exercises': [
                      {
                        'exerciseId': 'bench_press',
                        'sets': sets,
                        'repsMin': 8,
                        'repsMax': 10,
                        'restSeconds': 120,
                        'loadKg': 40,
                        'reason': 'A familiar movement'
                      },
                    ]
                  }
                ],
              })
            }
          ]
        }
      ],
    };

Future<void> reveal(WidgetTester tester, Finder finder) async {
  final list = tester.widget<ListView>(find.byType(ListView).first);
  list.controller!.jumpTo(0);
  await tester.pump();
  await tester.scrollUntilVisible(finder, 180,
      scrollable: find.byType(Scrollable).first, maxScrolls: 40);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, String label) async {
  await reveal(tester, find.text(label));
  await tester.tap(find.text(label));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> checkIn(WidgetTester tester) async {
  await tap(tester, '🙂 Good');
  await tap(tester, 'Day off');
}

Future<void> open(WidgetTester tester,
    {CoachClient? client, ValueChanged<Workout?>? onResult}) async {
  await tester.pumpWidget(MaterialApp(
      home: Builder(
          builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async {
                      final workout = await Navigator.push<Workout>(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  SessionPrepareScreen(client: client)));
                      onResult?.call(workout);
                    },
                    child: const Text('Open preparation')),
              ))));
  await tester.tap(find.text('Open preparation'));
  await tester.pumpAndSettle();
}

Future<void> send(WidgetTester tester,
    {bool update = false, bool settle = true}) async {
  await tap(tester, update ? 'Update with my coach' : 'Plan with my coach');
  expect(find.text('Send training context?'), findsOneWidget);
  await tester.tap(find.text('Send'));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

void main() {
  setUp(() {
    store.restoreBackup({'version': 3, 'workouts': [], 'customExercises': []});
    FlutterSecureStorage.setMockInitialValues(
        {'gyma.openai.api_key': 'test-only'});
  });

  testWidgets('manual start requires an explicit check-in and works without AI',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Workout? started;
    await open(tester, onResult: (value) => started = value);
    await tap(tester, 'Start a workout myself');
    expect(store.activeWorkout, isNull);
    expect(find.text('Choose how you feel today.'), findsOneWidget);
    await checkIn(tester);
    await tap(tester, '20 min');
    await tap(tester, 'Start a workout myself');
    expect(started, same(store.activeWorkout));
    expect(started!.checkIn!.timeMinutes, 20);
    expect(started!.energy, Energy.good);
    expect(started!.shift, Shift.off);
    expect(started!.exercises, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'conversation revises stale check-in and starts targets without logged sets',
      (tester) async {
    var calls = 0;
    final sent = <Map<String, dynamic>>[];
    final client = CoachClient(transport: (body, _) async {
      sent.add(jsonDecode(body['input'] as String) as Map<String, dynamic>);
      return response(sets: ++calls == 1 ? 3 : 2);
    });
    Workout? started;
    await open(tester, client: client, onResult: (value) => started = value);
    await checkIn(tester);
    await tap(tester, 'Plan with my coach');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    await send(tester);
    expect(sent.single['trainingContext']['currentCheckIn']['energy'], 'good');
    expect(store.coachConversation.length, 2);
    await tap(tester, '20 min');
    await reveal(tester, find.text('Start this session'));
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Start this session'))
            .onPressed,
        isNull);
    final followup =
        find.widgetWithText(TextFormField, 'Talk it through with your coach');
    await reveal(tester, followup);
    await tester.enterText(
        followup, 'I only have 20 minutes; please reduce the sets.');
    await send(tester, update: true);
    expect(sent.last['conversation'], hasLength(2));
    expect(sent.last['trainingContext']['currentCheckIn']['timeMinutes'], 20);
    await tap(tester, 'Start this session');
    expect(started!.exercises.single.target!.sets, 2);
    expect(started!.exercises.single.target!.repsMin, 8);
    expect(started!.exercises.single.target!.repsMax, 10);
    expect(started!.exercises.single.target!.restSeconds, 120);
    expect(started!.totalSets, 0);
    expect(store.coachConversation, hasLength(4));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'late replies cannot start or save after preparation is dismissed',
      (tester) async {
    final pending = Completer<Map<String, dynamic>>();
    await open(tester,
        client: CoachClient(transport: (_, __) => pending.future));
    await checkIn(tester);
    await send(tester, settle: false);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    pending.complete(response());
    await tester.pumpAndSettle();
    expect(store.activeWorkout, isNull);
    expect(store.coachConversation, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('changed training data makes an in-flight reply stale',
      (tester) async {
    final pending = Completer<Map<String, dynamic>>();
    await open(tester,
        client: CoachClient(transport: (_, __) => pending.future));
    await checkIn(tester);
    await send(tester, settle: false);
    store.saveProfile({'goal': 'Build muscle'});
    pending.complete(response());
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Start this session'));
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Start this session'))
            .onPressed,
        isNull);
    expect(store.activeWorkout, isNull);
  });

  testWidgets('restoring a backup replaces stale coach preference controllers',
      (tester) async {
    store.saveProfile({'goal': 'Old goal'});
    await tester
        .pumpWidget(const MaterialApp(home: Scaffold(body: CoachTab())));
    await tester.tap(find.text('Your goals & preferences'));
    await tester.pumpAndSettle();
    final goal =
        find.widgetWithText(TextField, 'What does better shape mean to you?');
    await tester.enterText(goal, 'Unsaved old goal');
    store.restoreBackup({
      'version': 3,
      'workouts': [],
      'customExercises': [],
      'trainingProfile': {'goal': 'Restored goal', 'schedule': 'Twice weekly'}
    });
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(goal).controller!.text, 'Restored goal');
    await tap(tester, 'Save preferences');
    expect(store.trainingProfile['goal'], 'Restored goal');
    expect(store.trainingProfile['schedule'], 'Twice weekly');
    expect(tester.takeException(), isNull);
  });

  testWidgets('an active workout can only be resumed from preparation',
      (tester) async {
    final active = store.startWorkout(Shift.off, Energy.good);
    Workout? resumed;
    await open(tester, onResult: (value) => resumed = value);
    await reveal(tester, find.text('Start a workout myself'));
    expect(
        tester
            .widget<TextButton>(
                find.widgetWithText(TextButton, 'Start a workout myself'))
            .onPressed,
        isNull);
    await tap(tester, 'Resume workout');
    expect(resumed, same(active));
    expect(store.workouts, hasLength(1));
  });

  testWidgets('active coaching changes are reviewed and preserve logged sets',
      (tester) async {
    final active = store.startWorkout(Shift.off, Energy.good);
    store.addExercise(active, 'bench_press');
    final bench = active.exercises.single;
    store.addSet(bench, WorkSet(40, 8, isWarmup: false));
    store.addSet(bench, WorkSet(20, 8, isWarmup: true));
    store.addSet(bench, WorkSet(30, 8));
    store.updateTarget(bench, ExerciseTarget(sets: 3, repsMin: 8, repsMax: 10));
    store.addExercise(active, 'lat_pulldown');
    final draft = jsonDecode(
            response(sets: 2)['output'][0]['content'][0]['text'] as String)
        as Map<String, dynamic>;
    store.saveCoachExchange('Make the remaining session shorter.', draft,
        sourceRevision: store.revision, sourceDay: dayKey(DateTime.now()));
    await tester
        .pumpWidget(const MaterialApp(home: Scaffold(body: CoachTab())));
    await tap(tester, 'Review workout changes');
    expect(
        find.text(
            'Bench press: 1 working set logged → 2 total target\n1 unlabelled set; confirm its type before counting it.'),
        findsOneWidget);
    expect(find.text('Lat pulldown: remove this unstarted exercise.'),
        findsOneWidget);
    await tester.tap(find.text('Keep current plan'));
    await tester.pumpAndSettle();
    expect(bench.target!.sets, 3);
    expect(active.exercises, hasLength(2));
    await tap(tester, 'Review workout changes');
    await tester.tap(find.text('Apply to this workout'));
    await tester.pumpAndSettle();
    expect(active.exercises.single, same(bench));
    expect(bench.target!.sets, 2);
    expect(bench.sets.first.kg, 40);
    expect(bench.sets.first.reps, 8);
    expect(active.totalSets, 3);
    expect(store.workouts, hasLength(1));
    expect(tester.takeException(), isNull);
  });
}
