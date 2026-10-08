import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../format.dart';
import '../models.dart';
import '../store.dart';
import '../widgets.dart';

/// Keeps the current set visible while the exercise's history scrolls below it.
class ExerciseLogScreen extends StatefulWidget {
  const ExerciseLogScreen(
      {super.key, required this.workout, required this.entry});

  final Workout workout;
  final WorkoutExercise entry;

  @override
  State<ExerciseLogScreen> createState() => _ExerciseLogScreenState();
}

class _ExerciseLogScreenState extends State<ExerciseLogScreen> {
  final _kg = TextEditingController();
  final _reps = TextEditingController();
  final _repsFocus = FocusNode();
  final _pageScroll = ScrollController();
  int? _editing;
  String? _kgError;
  String? _repsError;
  String? _announcement;
  late final WorkoutExercise? _previous;
  (String, String)? _draft;

  @override
  void initState() {
    super.initState();
    _previous = store.previousFor(widget.entry.exerciseId, widget.workout);
    _fill(widget.entry.sets.lastOrNull ?? _previous?.sets.firstOrNull);
  }

  void _fill(WorkSet? set) {
    _kg.text = set == null ? '' : fmtKg(set.kg).replaceAll(',', '');
    _reps.text = set == null ? '' : '${set.reps}';
    _kgError = null;
    _repsError = null;
  }

  @override
  void dispose() {
    _kg.dispose();
    _reps.dispose();
    _repsFocus.dispose();
    _pageScroll.dispose();
    super.dispose();
  }

  void _saveSet() {
    final kg = parseKg(_kg.text);
    final reps = int.tryParse(_reps.text.trim());
    setState(() {
      _kgError =
          kg == null || !kg.isFinite || kg < 0 ? 'Enter a valid weight' : null;
      _repsError = reps == null || reps <= 0 ? 'Enter at least 1 rep' : null;
    });
    if (_kgError != null || _repsError != null) return;
    FocusScope.of(context).unfocus();
    final index = _editing;
    final set = WorkSet(kg!, reps!);
    if (index == null) {
      store.addSet(widget.entry, set);
      setState(() {
        _announcement = 'Set ${widget.entry.sets.length} logged';
        _fill(set);
      });
    } else {
      store.updateSet(widget.entry, index, set);
      _cancelEdit();
      setState(() => _announcement = 'Set ${index + 1} updated');
    }
    HapticFeedback.lightImpact();
  }

  void _editSet(int index) {
    FocusScope.of(context).unfocus();
    setState(() {
      if (_editing == null) _draft = (_kg.text, _reps.text);
      _editing = index;
      _announcement = null;
      _fill(widget.entry.sets[index]);
    });
    if (_pageScroll.hasClients) {
      _pageScroll.animateTo(0,
          duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    }
  }

  void _cancelEdit() {
    FocusScope.of(context).unfocus();
    setState(() {
      _editing = null;
      _kg.text = _draft?.$1 ?? '';
      _reps.text = _draft?.$2 ?? '';
      _draft = null;
      _kgError = null;
      _repsError = null;
    });
  }

  void _deleteSet(int index) {
    if (_editing == index) {
      _cancelEdit();
    } else if (_editing != null && _editing! > index) {
      setState(() => _editing = _editing! - 1);
    }
    store.removeSet(widget.entry, index);
    setState(() => _announcement = 'Set removed');
  }

  Future<void> _removeExercise() async {
    final count = widget.entry.sets.length;
    if (count > 0) {
      final remove = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Remove exercise?'),
          content: Text(
              'This removes the exercise and its $count logged ${count == 1 ? 'set' : 'sets'} from this workout.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Remove')),
          ],
        ),
      );
      if (remove != true || !mounted) return;
    }
    store.removeExercise(widget.workout, widget.entry);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final def = store.exercise(widget.entry.exerciseId);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final sets = widget.entry.sets;
        final number = (_editing ?? sets.length) + 1;
        final previousSets = _previous?.sets ?? <WorkSet>[];
        final previous = number <= previousSets.length
            ? previousSets[number - 1]
            : previousSets.lastOrNull;
        return Scaffold(
          appBar: AppBar(
            title: Tooltip(
                message: def.name,
                child: Text(def.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done')),
              PopupMenuButton<String>(
                tooltip: 'Exercise options',
                onSelected: (_) => _removeExercise(),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'remove', child: Text('Remove exercise'))
                ],
              ),
            ],
          ),
          body: SafeArea(
            top: false,
            child: LayoutBuilder(builder: (context, constraints) {
              final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
              final compact = constraints.maxHeight < 500 * textScale;
              final editor = Padding(
                padding: EdgeInsets.fromLTRB(16, compact ? 4 : 16, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!compact) ...[
                      Align(
                          alignment: Alignment.centerLeft,
                          child: Pill(
                            leading: Icon(def.icon),
                            label: def.muscle.label,
                            color: def.muscle.color,
                          )),
                      const SizedBox(height: 12),
                    ],
                    Card(
                      child: Padding(
                        padding: EdgeInsets.all(compact ? 12 : 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(children: [
                              Expanded(
                                  child: Text(
                                _editing == null
                                    ? 'Set $number'
                                    : 'Edit set $number',
                                style: theme.textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              )),
                              if (_editing != null)
                                TextButton(
                                    onPressed: _cancelEdit,
                                    child: const Text('Cancel'))
                              else
                                Icon(Icons.fitness_center,
                                    size: 20, color: scheme.primary),
                            ]),
                            if (previous != null && !compact) ...[
                              const SizedBox(height: 4),
                              Text(
                                  'Last time: ${fmtKg(previous.kg)} kg × ${previous.reps} reps',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant)),
                            ],
                            SizedBox(height: compact ? 12 : 20),
                            Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                      child: _SetInput(
                                    fieldKey: const ValueKey('set-weight'),
                                    controller: _kg,
                                    label: 'Weight (kg)',
                                    decimal: true,
                                    error: _kgError,
                                    onSubmitted: (_) =>
                                        _repsFocus.requestFocus(),
                                  )),
                                  const SizedBox(width: 12),
                                  Expanded(
                                      child: _SetInput(
                                    fieldKey: const ValueKey('set-reps'),
                                    controller: _reps,
                                    focusNode: _repsFocus,
                                    label: 'Reps',
                                    error: _repsError,
                                    onSubmitted: (_) => _saveSet(),
                                  )),
                                ]),
                            const SizedBox(height: 14),
                            FilledButton.icon(
                              key: const ValueKey('save-set'),
                              onPressed: _saveSet,
                              icon: const Icon(Icons.check_rounded),
                              label: Text(_editing == null
                                  ? 'Log set'
                                  : 'Save changes'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                            _announcement ?? 'Sets are saved as you log them.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant)),
                      ),
                    ),
                  ],
                ),
              );
              final history = <Widget>[
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(children: [
                    Expanded(
                        child: Text('Logged sets',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700))),
                    Text('${sets.length}',
                        style: theme.textTheme.labelLarge
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                  ]),
                ),
                if (sets.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text('Tap a set to edit it.',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                  ),
                if (sets.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 24, horizontal: 16),
                    child: Text(
                        'Your first set starts above.\nUse 0 kg for an unweighted set.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                  )
                else
                  Card(
                      clipBehavior: Clip.antiAlias,
                      child: Column(children: [
                        for (var i = 0; i < sets.length; i++) ...[
                          if (i > 0) const Divider(indent: 16, endIndent: 16),
                          ListTile(
                            key: ValueKey('logged-set-$i'),
                            selected: _editing == i,
                            selectedTileColor:
                                scheme.primary.withValues(alpha: 0.08),
                            leading: CircleAvatar(
                              radius: 16,
                              backgroundColor:
                                  scheme.primary.withValues(alpha: 0.1),
                              child: Text('${i + 1}',
                                  style: theme.textTheme.labelMedium
                                      ?.copyWith(color: scheme.primary)),
                            ),
                            title: Text(
                                '${fmtKg(sets[i].kg)} kg × ${sets[i].reps} reps'),
                            onTap: () => _editSet(i),
                            trailing: IconButton(
                              tooltip: 'Delete set ${i + 1}',
                              onPressed: () => _deleteSet(i),
                              icon: const Icon(Icons.remove_circle_outline,
                                  size: 21),
                            ),
                          ),
                        ],
                      ])),
              ];
              // Very short screens scroll the whole page so both the editor
              // and saved sets remain accessible in landscape or large text.
              if (constraints.maxHeight < 340 * textScale) {
                return SingleChildScrollView(
                  controller: _pageScroll,
                  child: Column(children: [
                    editor,
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: history),
                    ),
                  ]),
                );
              }
              return Column(children: [
                editor,
                Expanded(
                    child: ListView(
                  key: const PageStorageKey('logged-sets'),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  children: history,
                )),
              ]);
            }),
          ),
        );
      },
    );
  }
}

class _SetInput extends StatelessWidget {
  const _SetInput(
      {required this.fieldKey,
      required this.controller,
      required this.label,
      required this.onSubmitted,
      this.decimal = false,
      this.error,
      this.focusNode});

  final Key fieldKey;
  final TextEditingController controller;
  final String label;
  final bool decimal;
  final String? error;
  final FocusNode? focusNode;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) => TextField(
        key: fieldKey,
        controller: controller,
        focusNode: focusNode,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        textInputAction: decimal ? TextInputAction.next : TextInputAction.done,
        inputFormatters: [
          FilteringTextInputFormatter.allow(
              RegExp(decimal ? r'[0-9.,]' : r'[0-9]'))
        ],
        style: Theme.of(context)
            .textTheme
            .headlineSmall
            ?.copyWith(fontWeight: FontWeight.w600),
        onSubmitted: onSubmitted,
        onTapOutside: (_) => FocusScope.of(context).unfocus(),
        decoration: InputDecoration(
            labelText: label,
            floatingLabelBehavior: FloatingLabelBehavior.always,
            hintText: '0',
            errorText: error,
            errorMaxLines: 2),
      );
}
