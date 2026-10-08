import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyma/api_key_store.dart';
import 'package:gyma/coach_client.dart';
import 'package:gyma/screens/api_key_screen.dart';
import 'package:gyma/store.dart';

void main() {
  final context = <String, dynamic>{'workouts': [{'id': 'w1'}], 'exerciseCatalog': [{'id': 'bench_press'}]};
  Map<String, dynamic> reply() => {'answer': 'Here is a draft.', 'rationale': ['Limited history'],
    'evidenceWorkoutIds': ['w1'], 'limitations': ['Soreness unknown'], 'plan': [{'title': 'Session',
      'exercises': [{'exerciseId': 'bench_press', 'sets': 2, 'reps': 8, 'loadKg': null, 'reason': 'Comfortable load'}]}]};

  test('direct coach uses requested model, strict output and no stored response', () async {
    final client = CoachClient(transport: (body, key) async {
      expect(key, 'test-only');
      expect(body['model'], 'gpt-6-luna');
      expect(body['store'], false);
      expect(body['text']['format']['strict'], true);
      expect(jsonEncode(body), isNot(contains('test-only')));
      return {'status': 'completed', 'output': [{'type': 'message', 'content': [{'type': 'output_text', 'text': jsonEncode(reply())}]}]};
    });
    final result = await client.ask(apiKey: 'test-only', question: 'Help', context: context);
    expect(result['answer'], 'Here is a draft.');
  });

  test('rejects invented evidence and unsafe numeric prescriptions', () {
    expect(() => CoachClient.validateReply({...reply(), 'evidenceWorkoutIds': ['invented']}, context), throwsFormatException);
    for (final change in [{'exerciseId': 'invented'}, {'sets': -2}, {'reps': 0}, {'loadKg': '60'}, {'loadKg': double.nan}]) {
      final invalid = reply();
      final exercise = invalid['plan'][0]['exercises'][0] as Map<String, dynamic>;
      exercise.addAll(change);
      expect(() => CoachClient.validateReply(invalid, context), throwsFormatException);
    }
  });

  test('incomplete responses and refusals do not become plans', () async {
    for (final data in [{'status': 'incomplete', 'output': []},
      {'status': 'completed', 'output': [{'type': 'message', 'content': [{'type': 'refusal', 'refusal': 'No'}]}]}]) {
      final client = CoachClient(transport: (body, key) async => data);
      await expectLater(client.ask(apiKey: 'test-only', question: 'Help', context: context), throwsA(anything));
    }
  });

  testWidgets('settings saves, replaces and removes key independently of backups', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: ApiKeyScreen()));
    await tester.pumpAndSettle();
    expect(find.text('No API key saved yet.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'sk-test-only-not-a-real-key');
    await tester.tap(find.text('Save API key'));
    await tester.pumpAndSettle();
    expect(await ApiKeyStore().read(), 'sk-test-only-not-a-real-key');
    expect(jsonEncode(store.toJson()), isNot(contains('sk-test')));
    expect(find.text('An API key is saved on this device.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'sk-replacement-not-a-real-key');
    await tester.tap(find.text('Save API key'));
    await tester.pumpAndSettle();
    expect(await ApiKeyStore().read(), 'sk-replacement-not-a-real-key');
    await tester.tap(find.text('Remove saved key'));
    await tester.pumpAndSettle();
    expect(await ApiKeyStore().read(), isNull);
  });
}
