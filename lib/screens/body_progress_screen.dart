import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../body_progress.dart';
import '../format.dart';

class BodyProgressScreen extends StatefulWidget {
  const BodyProgressScreen({super.key, this.repository, this.embedded = false});
  final BodyProgressStore? repository;
  final bool embedded;

  @override
  State<BodyProgressScreen> createState() => _BodyProgressScreenState();
}

class _BodyProgressScreenState extends State<BodyProgressScreen> {
  BodyProgressStore get _store => widget.repository ?? bodyProgressStore;

  @override
  void initState() {
    super.initState();
    if (!_store.isReady) _store.load();
  }

  void _edit([BodyProgressEntry? entry]) => Navigator.push<void>(
      context,
      MaterialPageRoute(
          builder: (_) => _ProgressEditor(repository: _store, entry: entry)));

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _store,
        builder: (context, _) {
          final entries = _store.entries;
          final theme = Theme.of(context);
          final content = ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              Text('See the bigger picture',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              const Text('An optional weekly check-in for photos, measurements '
                  'and how you feel. Look for changes over several weeks.'),
              const SizedBox(height: 16),
              const _PrivacyNote(),
              if (_store.storageError != null) ...[
                const SizedBox(height: 12),
                Card(
                    child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_store.storageError!),
                            if (!_store.isReady)
                              TextButton(
                                  onPressed: _store.load,
                                  child: const Text('Try again')),
                          ],
                        ))),
              ],
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _store.isReady ? () => _edit() : null,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('Add weekly check-in'),
              ),
              if (entries.length > 1) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                          builder: (_) => _ProgressComparison(
                              repository: _store, entries: entries))),
                  icon: const Icon(Icons.compare_outlined),
                  label: const Text('Compare check-ins'),
                ),
              ],
              const SizedBox(height: 24),
              if (entries.isEmpty)
                Card(
                    child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.photo_library_outlined,
                            size: 32, color: theme.colorScheme.primary),
                        const SizedBox(height: 12),
                        Text('Your starting point',
                            style: theme.textTheme.titleMedium),
                        const SizedBox(height: 6),
                        const Text(
                            'Choose front, side or back photos, or simply add a '
                            'measurement or note. Every part is optional.'),
                      ]),
                )),
              for (final entry in entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Card(
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => _edit(entry),
                        child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Expanded(
                                      child: Text(fmtDate(entry.date),
                                          style: theme.textTheme.titleMedium)),
                                  const Icon(Icons.chevron_right),
                                ]),
                                if (entry.weightKg != null ||
                                    entry.waistCm != null) ...[
                                  const SizedBox(height: 6),
                                  Text(_measurements(entry)),
                                ],
                                if (entry.photos.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        for (final angle
                                            in BodyPhotoAngle.values)
                                          Expanded(
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 3),
                                              child: Column(children: [
                                                _Photo(
                                                    repository: _store,
                                                    name: entry.photos[angle],
                                                    label:
                                                        '${angle.label} photo',
                                                    aspectRatio: 0.8),
                                                const SizedBox(height: 4),
                                                Text(angle.label,
                                                    style: theme
                                                        .textTheme.labelSmall),
                                              ]),
                                            ),
                                          ),
                                      ]),
                                ],
                                if (entry.notes.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  Text(entry.notes,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis),
                                ],
                              ],
                            )),
                      )),
                ),
            ],
          );
          return widget.embedded
              ? content
              : Scaffold(
                  appBar: AppBar(title: const Text('Shape & progress')),
                  body: content);
        },
      );
}

String _measurements(BodyProgressEntry entry) => [
      if (entry.weightKg != null) '${fmtKg(entry.weightKg!)} kg',
      if (entry.waistCm != null) '${fmtKg(entry.waistCm!)} cm waist',
    ].join(' · ');

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline,
              size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
              child: Text(
                  'Saved on this device. Photos and measurements are '
                  'never sent to the AI coach and are not included in workout JSON backups. '
                  'Keep your original photos before reinstalling.',
                  style: Theme.of(context).textTheme.bodySmall)),
        ],
      );
}

class _Photo extends StatelessWidget {
  const _Photo(
      {required this.repository,
      required this.name,
      required this.label,
      this.bytes,
      this.aspectRatio = 0.72});
  final BodyProgressStore repository;
  final String? name;
  final String label;
  final Uint8List? bytes;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    final file = repository.photoFile(name);
    Widget placeholder(String text) => Center(
            child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.image_outlined),
            const SizedBox(height: 4),
            Text(text,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall),
          ]),
        ));
    return Semantics(
        label: label,
        image: true,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: aspectRatio,
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: bytes != null
                  ? Image.memory(bytes!,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) =>
                          placeholder('Cannot open photo'))
                  : file != null
                      ? Image.file(file,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) =>
                              placeholder('Photo unavailable'))
                      : placeholder('No photo'),
            ),
          ),
        ));
  }
}

class _ProgressEditor extends StatefulWidget {
  const _ProgressEditor({required this.repository, this.entry});
  final BodyProgressStore repository;
  final BodyProgressEntry? entry;

  @override
  State<_ProgressEditor> createState() => _ProgressEditorState();
}

class _ProgressEditorState extends State<_ProgressEditor> {
  final _form = GlobalKey<FormState>();
  late DateTime _date;
  late TextEditingController _weight;
  late TextEditingController _waist;
  late TextEditingController _notes;
  final _newPhotos = <BodyPhotoAngle, Uint8List>{};
  final _removedPhotos = <BodyPhotoAngle>{};
  bool _busy = false;
  bool _dirty = false;
  bool _canLeave = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    _date = entry?.date ?? DateTime.now();
    _weight = TextEditingController(text: entry?.weightKg?.toString() ?? '');
    _waist = TextEditingController(text: entry?.waistCm?.toString() ?? '');
    _notes = TextEditingController(text: entry?.notes ?? '');
  }

  @override
  void dispose() {
    _weight.dispose();
    _waist.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _leave() async {
    if (_busy) return;
    final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Discard changes?'),
              content: const Text(
                  'This check-in has changes that have not been saved.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Keep editing')),
                TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Discard')),
              ],
            ));
    if (discard == true && mounted) {
      setState(() => _canLeave = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    }
  }

  Future<void> _pick(BodyPhotoAngle angle) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final file = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          maxWidth: 1600,
          maxHeight: 2000,
          imageQuality: 85,
          requestFullMetadata: false);
      if (file == null) return;
      // Decode pixels and re-encode: no gallery paths, EXIF or location metadata.
      final codec = await ui.instantiateImageCodec(await file.readAsBytes(),
          targetWidth: 1400, allowUpscaling: false);
      Uint8List bytes;
      try {
        final frame = await codec.getNextFrame();
        try {
          final data =
              await frame.image.toByteData(format: ui.ImageByteFormat.png);
          if (data == null) throw StateError('Could not process photo');
          bytes =
              data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
      if (mounted) {
        setState(() {
          _newPhotos[angle] = bytes;
          _removedPhotos.remove(angle);
          _dirty = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'This photo could not be opened. '
            'Try selecting a different photo from your library.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final hasPhotos = _newPhotos.isNotEmpty ||
        (widget.entry?.photos.keys
                .any((angle) => !_removedPhotos.contains(angle)) ??
            false);
    if (!hasPhotos &&
        _weight.text.trim().isEmpty &&
        _waist.text.trim().isEmpty &&
        _notes.text.trim().isEmpty) {
      setState(() =>
          _error = 'Add a photo, measurement or note to save this check-in.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.save(
          id: widget.entry?.id,
          date: _date,
          weightKg: parseKg(_weight.text),
          waistCm: parseKg(_waist.text),
          notes: _notes.text,
          newPhotos: _newPhotos,
          removedPhotos: _removedPhotos);
      if (mounted) {
        setState(() {
          _busy = false;
          _canLeave = true;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.pop(context);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error =
              'Could not save your check-in. Your changes are still here; try again.';
        });
      }
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Delete this check-in?'),
              content: const Text(
                  'Its saved photos, measurements and notes will be '
                  'removed from Gyma. Your original library photos are unaffected.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel')),
                TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Delete')),
              ],
            ));
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.delete(widget.entry!.id);
      if (mounted) {
        setState(() {
          _busy = false;
          _canLeave = true;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.pop(context);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Could not delete this check-in. Try again.';
        });
      }
    }
  }

  String? _validateMeasurement(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    final value = parseKg(text);
    return value == null || !value.isFinite || value <= 0 || value > 1000
        ? 'Enter a value greater than 0, up to 1000'
        : null;
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_busy && (!_dirty || _canLeave),
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _leave();
        },
        child: Scaffold(
          appBar: AppBar(
              title: Text(
                  widget.entry == null ? 'Weekly check-in' : 'Edit check-in')),
          body: AbsorbPointer(
              absorbing: _busy,
              child: Form(
                key: _form,
                onChanged: () {
                  if (!_dirty) setState(() => _dirty = true);
                },
                child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                    children: [
                      OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await showDatePicker(
                                context: context,
                                initialDate: _date,
                                firstDate: DateTime(2000),
                                lastDate: DateTime.now());
                            if (picked != null && mounted) {
                              setState(() {
                                _date = picked;
                                _dirty = true;
                              });
                            }
                          },
                          icon: const Icon(Icons.calendar_today_outlined),
                          label: Text(fmtDate(_date))),
                      const SizedBox(height: 16),
                      Text('A consistent view',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 6),
                      const Text(
                          'Use similar lighting, distance, clothing and a relaxed pose. '
                          'Keep the same side each week. Small day-to-day changes are normal.'),
                      const SizedBox(height: 16),
                      Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final angle in BodyPhotoAngle.values)
                              Expanded(
                                  child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 3),
                                child: Column(children: [
                                  _Photo(
                                      repository: widget.repository,
                                      name: _removedPhotos.contains(angle)
                                          ? null
                                          : widget.entry?.photos[angle],
                                      bytes: _newPhotos[angle],
                                      label: '${angle.label} photo'),
                                  TextButton(
                                      onPressed: () => _pick(angle),
                                      child: Text(angle.label)),
                                  if (_newPhotos.containsKey(angle) ||
                                      (!_removedPhotos.contains(angle) &&
                                          (widget.entry?.photos
                                                  .containsKey(angle) ??
                                              false)))
                                    IconButton(
                                        tooltip:
                                            'Remove ${angle.label.toLowerCase()} photo',
                                        onPressed: () => setState(() {
                                              _newPhotos.remove(angle);
                                              _removedPhotos.add(angle);
                                              _dirty = true;
                                            }),
                                        icon:
                                            const Icon(Icons.close, size: 18)),
                                ]),
                              )),
                          ]),
                      const SizedBox(height: 16),
                      TextFormField(
                          controller: _weight,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: const InputDecoration(
                              labelText: 'Body weight (optional)',
                              suffixText: 'kg'),
                          validator: _validateMeasurement),
                      const SizedBox(height: 16),
                      TextFormField(
                          controller: _waist,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: const InputDecoration(
                              labelText: 'Waist (optional)',
                              suffixText: 'cm',
                              helperText:
                                  'Measure at the same spot each time.'),
                          validator: _validateMeasurement),
                      const SizedBox(height: 16),
                      TextFormField(
                          controller: _notes,
                          minLines: 3,
                          maxLines: 6,
                          maxLength: 2000,
                          decoration: const InputDecoration(
                              labelText: 'How are you feeling? (optional)',
                              hintText:
                                  'Energy, confidence, clothing fit, or a small win…')),
                      const SizedBox(height: 16),
                      const _PrivacyNote(),
                      if (_error != null)
                        Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Text(_error!,
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.error))),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                          onPressed: _busy ? null : _save,
                          icon: _busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.check),
                          label:
                              Text(_busy ? 'Please wait…' : 'Save check-in')),
                      if (widget.entry != null)
                        TextButton(
                            onPressed: _busy ? null : _delete,
                            child: const Text('Delete check-in')),
                    ]),
              )),
        ),
      );
}

class _ProgressComparison extends StatefulWidget {
  const _ProgressComparison({required this.repository, required this.entries});
  final BodyProgressStore repository;
  final List<BodyProgressEntry> entries;

  @override
  State<_ProgressComparison> createState() => _ProgressComparisonState();
}

class _ProgressComparisonState extends State<_ProgressComparison> {
  late String _first = widget.entries.last.id;
  late String _second = widget.entries.first.id;
  BodyPhotoAngle _angle = BodyPhotoAngle.front;

  @override
  Widget build(BuildContext context) {
    final first = widget.entries.firstWhere((e) => e.id == _first);
    final second = widget.entries.firstWhere((e) => e.id == _second);
    final days =
        DateTime.utc(second.date.year, second.date.month, second.date.day)
            .difference(
                DateTime.utc(first.date.year, first.date.month, first.date.day))
            .inDays
            .abs();
    return Scaffold(
      appBar: AppBar(title: const Text('Compare check-ins')),
      body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Text('$days days apart',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text(
                'Compare the same view. Lighting, posture and clothing can '
                'change how a photo looks; photos do not measure body fat or muscle.'),
            const SizedBox(height: 20),
            SegmentedButton<BodyPhotoAngle>(
                showSelectedIcon: false,
                segments: [
                  for (final angle in BodyPhotoAngle.values)
                    ButtonSegment(value: angle, label: Text(angle.label))
                ],
                selected: {_angle},
                onSelectionChanged: (value) =>
                    setState(() => _angle = value.first)),
            const SizedBox(height: 20),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                  child: _column(first, _first, _second,
                      (id) => setState(() => _first = id))),
              const SizedBox(width: 12),
              Expanded(
                  child: _column(second, _second, _first,
                      (id) => setState(() => _second = id))),
            ]),
            const SizedBox(height: 20),
            const _PrivacyNote(),
          ]),
    );
  }

  Widget _column(BodyProgressEntry entry, String selected, String other,
          ValueChanged<String> changed) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButton<String>(
              value: selected,
              isExpanded: true,
              items: [
                for (final e in widget.entries.where((e) => e.id != other))
                  DropdownMenuItem(
                      value: e.id,
                      child: Text(fmtDate(e.date),
                          overflow: TextOverflow.ellipsis))
              ],
              onChanged: (value) {
                if (value != null) changed(value);
              }),
          const SizedBox(height: 8),
          _Photo(
              repository: widget.repository,
              name: entry.photos[_angle],
              label: '${_angle.label} photo from ${fmtDate(entry.date)}'),
          if (_measurements(entry).isNotEmpty)
            Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_measurements(entry))),
          if (entry.notes.isNotEmpty)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(entry.notes)),
        ],
      );
}
