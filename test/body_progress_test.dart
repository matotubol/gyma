import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyma/body_progress.dart';
import 'package:gyma/screens/body_progress_screen.dart';

void main() {
  late Directory directory;
  late BodyProgressStore repository;
  final photo = Uint8List.fromList([137, 80, 78, 71]);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('gyma-progress-test-');
    repository = BodyProgressStore(directory: directory);
    await repository.load();
  });

  tearDown(() async {
    repository.dispose();
    await directory.delete(recursive: true);
  });

  test('check-ins and owned photo bytes persist across restart', () async {
    final entry = await repository.save(
        date: DateTime(2026, 10, 1),
        weightKg: 78.5,
        waistCm: 82,
        notes: 'Feeling stronger',
        newPhotos: {BodyPhotoAngle.front: photo});
    final path = repository.photoFile(entry.photos[BodyPhotoAngle.front])!;
    expect(await path.readAsBytes(), photo);
    final restored = BodyProgressStore(directory: directory);
    await restored.load();
    expect(restored.isReady, isTrue);
    expect(restored.entries.single.toJson(), entry.toJson());
    restored.dispose();
  });

  test('replace and remove photos only after saving the updated entry',
      () async {
    final entry = await repository.save(
        date: DateTime(2026, 10, 1), newPhotos: {BodyPhotoAngle.front: photo});
    final firstFile = repository.photoFile(entry.photos[BodyPhotoAngle.front])!;
    final updated = await repository
        .save(id: entry.id, date: entry.date, notes: 'Updated', newPhotos: {
      BodyPhotoAngle.front: Uint8List.fromList([1, 2])
    });
    expect(await firstFile.exists(), isFalse);
    final secondFile =
        repository.photoFile(updated.photos[BodyPhotoAngle.front])!;
    expect(await secondFile.exists(), isTrue);
    await repository.save(
        id: entry.id,
        date: entry.date,
        notes: 'No photo this week',
        removedPhotos: {BodyPhotoAngle.front});
    expect(await secondFile.exists(), isFalse);
    expect(repository.entries.single.photos, isEmpty);
    await repository.delete(entry.id);
    final restored = BodyProgressStore(directory: directory);
    await restored.load();
    expect(restored.entries, isEmpty);
    restored.dispose();
  });

  test('invalid data preserves the original index and blocks overwriting',
      () async {
    final file = File('${directory.path}/entries.json');
    const broken = '{unreadable';
    await file.writeAsString(broken);
    await repository.load();
    expect(repository.isReady, isFalse);
    expect(repository.storageError, isNotNull);
    await expectLater(
        repository.save(date: DateTime(2026), notes: 'new'), throwsStateError);
    expect(await file.readAsString(), broken);
  });

  test('external photo paths are rejected without accessing external files',
      () async {
    expect(repository.photoFile('../../private.png'), isNull);
    final data = {
      'id': 'test',
      'date': '2026-10-01',
      'notes': '',
      'photos': {'front': '../../private.png'},
    };
    expect(() => BodyProgressEntry.fromJson(data), throwsFormatException);
    expect(
        () => BodyProgressEntry.fromJson({
              ...data,
              'photos': {'front': r'C:\Users\other\photo.png'}
            }),
        throwsFormatException);
  });

  test('failed index save leaves saved entry unchanged and removes new photo',
      () async {
    final original =
        await repository.save(date: DateTime(2026, 10, 1), notes: 'Keep me');
    await Directory('${directory.path}/entries.json.tmp').create();
    await expectLater(
        repository.save(
            id: original.id,
            date: original.date,
            notes: 'Unsaved',
            newPhotos: {BodyPhotoAngle.side: photo}),
        throwsA(isA<FileSystemException>()));
    expect(repository.entries.single.notes, 'Keep me');
    expect(
        await directory.list().where((f) => f.path.endsWith('.png')).length, 0);
    final restored = BodyProgressStore(directory: directory);
    await restored.load();
    expect(restored.entries.single.notes, 'Keep me');
    restored.dispose();
  });

  test('simultaneous saves do not lose either check-in', () async {
    await Future.wait([
      repository.save(date: DateTime(2026, 10, 1), notes: 'First'),
      repository.save(date: DateTime(2026, 10, 8), notes: 'Second'),
    ]);
    final restored = BodyProgressStore(directory: directory);
    await restored.load();
    expect(restored.entries.map((e) => e.notes), ['Second', 'First']);
    restored.dispose();
  });

  test('interrupted index replacement recovers previous saved records',
      () async {
    await repository.save(
        date: DateTime(2026, 10, 1), notes: 'Saved before crash');
    await File('${directory.path}/entries.json')
        .rename('${directory.path}/entries.json.previous');
    final restored = BodyProgressStore(directory: directory);
    await restored.load();
    expect(restored.entries.single.notes, 'Saved before crash');
    expect(restored.isReady, isTrue);
    restored.dispose();
  });

  test('empty entries and nonfinite measurements cannot be stored', () async {
    await expectLater(
        repository.save(date: DateTime(2026)), throwsFormatException);
    await expectLater(
        repository.save(date: DateTime(2026), weightKg: double.nan),
        throwsFormatException);
    expect(repository.entries, isEmpty);
    final index = File('${directory.path}/entries.json');
    expect(await index.exists(), isFalse);
  });

  testWidgets(
      'small screen check-in rejects empty saves and warns before discard',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
        MaterialApp(home: BodyProgressScreen(repository: repository)));
    await tester.tap(find.text('Add weekly check-in'));
    await tester.pumpAndSettle();
    final save = find.text('Save check-in');
    await tester.scrollUntilVisible(save, 250,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('Add a photo, measurement or note to save this check-in.'),
        findsOneWidget);
    final notes =
        find.widgetWithText(TextFormField, 'How are you feeling? (optional)');
    await tester.ensureVisible(notes);
    await tester.enterText(notes, 'An encouraging week');
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('comparison supports measurement-only weeks and changes view',
      (tester) async {
    await tester.runAsync(() async {
      await repository.save(
          date: DateTime(2026, 9, 1), weightKg: 80, notes: 'Start');
      await repository.save(
          date: DateTime(2026, 9, 29), weightKg: 81, notes: 'Later');
    });
    await tester.pumpWidget(
        MaterialApp(home: BodyProgressScreen(repository: repository)));
    await tester.tap(find.text('Compare check-ins'));
    await tester.pumpAndSettle();
    expect(find.text('28 days apart'), findsOneWidget);
    expect(find.text('No photo'), findsNWidgets(2));
    await tester.tap(find.text('Side'));
    await tester.pumpAndSettle();
    expect(find.text('80 kg'), findsOneWidget);
    expect(find.text('81 kg'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test(
      'photo payload stays outside the index, missing image does not lose entry',
      () async {
    final entry = await repository.save(
        date: DateTime(2026, 10, 1), newPhotos: {BodyPhotoAngle.front: photo});
    await repository.photoFile(entry.photos[BodyPhotoAngle.front])!.delete();
    final index =
        jsonDecode(await File('${directory.path}/entries.json').readAsString());
    expect(index['entries'][0]['photos']['front'],
        isNot(contains(directory.path)));
    final restored = BodyProgressStore(directory: directory);
    await restored.load();
    expect(restored.entries.single.id, entry.id);
    expect(restored.isReady, isTrue);
    restored.dispose();
  });
}
