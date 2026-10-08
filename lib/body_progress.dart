import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

enum BodyPhotoAngle {
  front('Front'),
  side('Side'),
  back('Back');

  const BodyPhotoAngle(this.label);
  final String label;
}

class BodyProgressEntry {
  BodyProgressEntry({
    required this.id,
    required this.date,
    this.weightKg,
    this.waistCm,
    this.notes = '',
    Map<BodyPhotoAngle, String> photos = const {},
  }) : photos = Map.unmodifiable(photos);

  final String id;
  final DateTime date;
  final double? weightKg;
  final double? waistCm;
  final String notes;

  /// App-owned filenames only. Gallery paths are never persisted.
  final Map<BodyPhotoAngle, String> photos;

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'weightKg': weightKg,
        'waistCm': waistCm,
        'notes': notes,
        'photos': {for (final p in photos.entries) p.key.name: p.value},
      };

  factory BodyProgressEntry.fromJson(Map<String, dynamic> json) {
    final entry = BodyProgressEntry(
      id: json['id'] as String,
      date: DateTime.parse(json['date'] as String),
      weightKg: (json['weightKg'] as num?)?.toDouble(),
      waistCm: (json['waistCm'] as num?)?.toDouble(),
      notes: json['notes'] as String? ?? '',
      photos: {
        for (final p in (json['photos'] as Map).entries)
          BodyPhotoAngle.values.byName(p.key as String): p.value as String,
      },
    );
    entry.validate();
    return entry;
  }

  void validate() {
    if (id.isEmpty || notes.length > 2000) {
      throw const FormatException('Invalid progress entry');
    }
    for (final value in [weightKg, waistCm]) {
      if (value != null && (!value.isFinite || value <= 0 || value > 1000)) {
        throw const FormatException('Measurements must be between 0 and 1000');
      }
    }
    if (photos.values.any((name) => !_photoName.hasMatch(name))) {
      throw const FormatException('Invalid progress photo filename');
    }
    if (photos.isEmpty &&
        weightKg == null &&
        waistCm == null &&
        notes.trim().isEmpty) {
      throw const FormatException('Add a photo, measurement or note');
    }
  }
}

final _photoName = RegExp(r'^photo-[a-f0-9]{32}\.png$');
final bodyProgressStore = BodyProgressStore();

/// A separate local store: photos never enter workout backups or AI context.
/// Mutations publish only after their index and new photos have been saved.
class BodyProgressStore extends ChangeNotifier {
  BodyProgressStore({Directory? directory}) : _directory = directory;

  Directory? _directory;
  List<BodyProgressEntry> _entries = [];
  Future<void> _pending = Future.value();
  bool _ready = false;
  String? storageError;

  List<BodyProgressEntry> get entries => List.unmodifiable(_entries);
  bool get isReady => _ready;

  Future<void> load() async {
    try {
      _directory ??= Directory(
          '${(await getApplicationDocumentsDirectory()).path}/gyma_progress');
      await _directory!.create(recursive: true);
      final file = _index;
      final previous = File('${file.path}.previous');
      // Recover an interruption between renaming the previous and new index.
      if (!await file.exists() && await previous.exists()) {
        await previous.rename(file.path);
      }
      final parsed = <BodyProgressEntry>[];
      if (await file.exists()) {
        final data =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        if (data['version'] != 1) {
          throw const FormatException('Unsupported progress data version');
        }
        parsed.addAll((data['entries'] as List)
            .map((e) => BodyProgressEntry.fromJson(e as Map<String, dynamic>)));
        if (parsed.map((e) => e.id).toSet().length != parsed.length) {
          throw const FormatException('Duplicate progress entry');
        }
      }
      parsed.sort((a, b) => b.date.compareTo(a.date));
      _entries = parsed;
      _ready = true;
      storageError = null;
    } catch (_) {
      _ready = false;
      storageError =
          'Progress could not be opened. Your saved files are preserved. '
          'Try opening this screen again.';
    }
    notifyListeners();
  }

  File get _index => File('${_directory!.path}/entries.json');

  /// Returns null for unknown or unsafe filenames; missing files render gently.
  File? photoFile(String? name) =>
      name != null && _photoName.hasMatch(name) && _directory != null
          ? File('${_directory!.path}/$name')
          : null;

  Future<T> _serialize<T>(Future<T> Function() action) {
    final future = _pending.then((_) => action());
    _pending = future.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return future;
  }

  Future<BodyProgressEntry> save({
    String? id,
    required DateTime date,
    double? weightKg,
    double? waistCm,
    String notes = '',
    Map<BodyPhotoAngle, Uint8List> newPhotos = const {},
    Set<BodyPhotoAngle> removedPhotos = const {},
  }) =>
      _serialize(() async {
        _requireReady();
        final matches = _entries.where((e) => e.id == id);
        if (id != null && matches.isEmpty) {
          throw StateError('This progress entry no longer exists.');
        }
        final old = matches.isEmpty ? null : matches.first;
        final photos = Map<BodyPhotoAngle, String>.of(old?.photos ?? {});
        for (final angle in removedPhotos) {
          photos.remove(angle);
        }
        final created = <String>[];
        try {
          for (final p in newPhotos.entries) {
            if (p.value.isEmpty || p.value.length > 30 * 1024 * 1024) {
              throw const FormatException('Photo is empty or too large');
            }
            final name = 'photo-${_newId()}.png';
            created.add(name);
            await photoFile(name)!.writeAsBytes(p.value, flush: true);
            photos[p.key] = name;
          }
          final entry = BodyProgressEntry(
            id: id ?? _newId(),
            date: DateTime(date.year, date.month, date.day),
            weightKg: weightKg,
            waistCm: waistCm,
            notes: notes.trim(),
            photos: photos,
          )..validate();
          final next = [..._entries.where((e) => e.id != id), entry]
            ..sort((a, b) => b.date.compareTo(a.date));
          await _commit(next);
          _entries = next;
          storageError = null;
          notifyListeners();
          await _removeUnreferenced(old?.photos.values ?? []);
          return entry;
        } catch (_) {
          await _removeUnreferenced(created);
          rethrow;
        }
      });

  Future<void> delete(String id) => _serialize(() async {
        _requireReady();
        final matches = _entries.where((e) => e.id == id);
        if (matches.isEmpty) return;
        final old = matches.first;
        final next = _entries.where((e) => e.id != id).toList();
        await _commit(next);
        _entries = next;
        storageError = null;
        notifyListeners();
        await _removeUnreferenced(old.photos.values);
      });

  void _requireReady() {
    if (!_ready) throw StateError('Progress storage is unavailable.');
  }

  Future<void> _commit(List<BodyProgressEntry> next) async {
    final file = _index;
    final temp = File('${file.path}.tmp');
    final previous = File('${file.path}.previous');
    var movedPrevious = false;
    try {
      await temp.writeAsString(
          jsonEncode({
            'version': 1,
            'entries': next.map((e) => e.toJson()).toList(),
          }),
          flush: true);
      if (await file.exists()) {
        if (await previous.exists()) await previous.delete();
        await file.rename(previous.path);
        movedPrevious = true;
      }
      await temp.rename(file.path);
    } catch (_) {
      if (movedPrevious && !await file.exists() && await previous.exists()) {
        await previous.rename(file.path);
      }
      storageError =
          'Your changes could not be saved. Keep this screen open and try again.';
      notifyListeners();
      rethrow;
    }
    // A failed cleanup must not turn a successful save into a failed save.
    try {
      if (await previous.exists()) await previous.delete();
    } catch (_) {}
  }

  Future<void> _removeUnreferenced(Iterable<String> names) async {
    final referenced = _entries.expand((e) => e.photos.values).toSet();
    for (final name in names) {
      if (referenced.contains(name)) continue;
      final file = photoFile(name);
      if (file == null) continue;
      try {
        if (await FileSystemEntity.type(file.path, followLinks: false) ==
            FileSystemEntityType.file) {
          await file.delete();
        }
      } catch (_) {
        // An orphaned private file is safer than losing the saved entry.
      }
    }
  }

  String _newId() {
    final random = Random.secure();
    return List.generate(
            16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
