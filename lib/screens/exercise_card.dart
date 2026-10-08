import 'package:flutter/material.dart';

import '../format.dart';
import '../models.dart';
import '../store.dart';
import '../widgets.dart';

String _fmtSet(WorkSet s) => '${fmtKg(s.kg)}×${s.reps}';

/// One exercise inside a workout: its sets plus a kg × reps row to add more.
class ExerciseCard extends StatefulWidget {
  const ExerciseCard({super.key, required this.workout, required this.entry});

  final Workout workout;
  final WorkoutExercise entry;

  @override
  State<ExerciseCard> createState() => _ExerciseCardState();
}

class _ExerciseCardState extends State<ExerciseCard> {
  final _kg = TextEditingController();
  final _reps = TextEditingController();
  WorkoutExercise? _previous;

  @override
  void initState() {
    super.initState();
    _previous = store.previousFor(widget.entry.exerciseId, widget.workout);
    // Pre-fill with the last set, or what you did first last time.
    final sets = widget.entry.sets;
    final seed = sets.isNotEmpty ? sets.last : _previous?.sets.first;
    if (seed != null) {
      _kg.text = fmtKg(seed.kg).replaceAll(',', '');
      _reps.text = '${seed.reps}';
    }
  }

  @override
  void dispose() {
    _kg.dispose();
    _reps.dispose();
    super.dispose();
  }

  void _addSet() {
    final kg = parseKg(_kg.text);
    final reps = int.tryParse(_reps.text.trim());
    if (kg == null || kg < 0 || reps == null || reps <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter the kg and reps first')));
      return;
    }
    FocusScope.of(context).unfocus();
    store.addSet(widget.entry, WorkSet(kg, reps));
  }

  Future<void> _editSet(int index) async {
    final result = await showDialog<_SetEdit>(
      context: context,
      builder: (_) =>
          _SetEditorDialog(set: widget.entry.sets[index], number: index + 1),
    );
    if (result == null) return;
    final set = result.set;
    if (set == null) {
      store.removeSet(widget.entry, index);
    } else {
      store.updateSet(widget.entry, index, set);
    }
  }

  Future<void> _remove() async {
    if (widget.entry.sets.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Remove exercise?'),
          content: Text('Its ${widget.entry.sets.length} sets will be deleted.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remove'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    store.removeExercise(widget.workout, widget.entry);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final def = store.exercise(widget.entry.exerciseId);
    final entry = widget.entry;
    final previous = _previous;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 4, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                ExerciseAvatar(def),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(def.name, style: theme.textTheme.titleMedium),
                      Text(
                        entry.sets.isEmpty
                            ? def.muscle.label
                            : '${entry.sets.length} sets · ${entry.reps} reps · ${fmtKg(entry.volume)} kg',
                        style: muted,
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (_) => _remove(),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'remove', child: Text('Remove exercise')),
                  ],
                ),
              ],
            ),
            if (previous != null)
              Padding(
                padding: const EdgeInsets.only(top: 8, right: 12),
                child: Text(
                  'Last time: ${previous.sets.map(_fmtSet).join('  ·  ')}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: muted,
                ),
              ),
            const SizedBox(height: 8),
            for (var i = 0; i < entry.sets.length; i++)
              _SetRow(number: i + 1, set: entry.sets[i], onTap: () => _editSet(i)),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Row(
                children: [
                  Expanded(
                    child: NumberField(controller: _kg, label: 'kg', decimal: true),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('×'),
                  ),
                  Expanded(child: NumberField(controller: _reps, label: 'reps')),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Add set',
                    onPressed: _addSet,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SetRow extends StatelessWidget {
  const _SetRow({required this.number, required this.set, required this.onTap});

  final int number;
  final WorkSet set;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 5, 12, 5),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: scheme.primaryContainer, shape: BoxShape.circle),
              child: Text('$number',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: scheme.onPrimaryContainer)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text('${fmtKg(set.kg)} kg  ×  ${set.reps}',
                  style: theme.textTheme.titleSmall),
            ),
            Text('${fmtKg(set.volume)} kg',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

/// Result of the set editor: a new set, or `null` set meaning "delete".
class _SetEdit {
  const _SetEdit(this.set);
  final WorkSet? set;
}

class _SetEditorDialog extends StatefulWidget {
  const _SetEditorDialog({required this.set, required this.number});

  final WorkSet set;
  final int number;

  @override
  State<_SetEditorDialog> createState() => _SetEditorDialogState();
}

class _SetEditorDialogState extends State<_SetEditorDialog> {
  late final _kg =
      TextEditingController(text: fmtKg(widget.set.kg).replaceAll(',', ''));
  late final _reps = TextEditingController(text: '${widget.set.reps}');

  @override
  void dispose() {
    _kg.dispose();
    _reps.dispose();
    super.dispose();
  }

  void _save() {
    final kg = parseKg(_kg.text);
    final reps = int.tryParse(_reps.text.trim());
    if (kg == null || kg < 0 || reps == null || reps <= 0) return;
    Navigator.pop(context, _SetEdit(WorkSet(kg, reps)));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Set ${widget.number}'),
      content: Row(
        children: [
          Expanded(child: NumberField(controller: _kg, label: 'kg', decimal: true)),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text('×'),
          ),
          Expanded(child: NumberField(controller: _reps, label: 'reps')),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, const _SetEdit(null)),
          style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error),
          child: const Text('Delete'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
