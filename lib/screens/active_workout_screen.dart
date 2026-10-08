import 'dart:async';

import 'package:flutter/material.dart';

import '../format.dart';
import '../models.dart';
import '../store.dart';
import '../widgets.dart';
import 'check_in_sheet.dart';
import 'exercise_card.dart';
import 'exercise_picker_screen.dart';
import 'workout_detail_screen.dart';
import 'recovery_screen.dart';

/// Logs a running workout. Also used to edit a finished one.
class ActiveWorkoutScreen extends StatefulWidget {
  const ActiveWorkoutScreen({super.key, required this.workout});

  final Workout workout;

  @override
  State<ActiveWorkoutScreen> createState() => _ActiveWorkoutScreenState();
}

class _ActiveWorkoutScreenState extends State<ActiveWorkoutScreen> {
  Timer? _ticker;

  Workout get _w => widget.workout;

  @override
  void initState() {
    super.initState();
    if (_w.isActive) {
      _ticker =
          Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _addExercise() async {
    final id = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => ExercisePickerScreen(
          alreadyAdded: {for (final e in _w.exercises) e.exerciseId},
        ),
      ),
    );
    if (id != null) store.addExercise(_w, id);
  }

  Future<void> _editCheckIn() async {
    final result = await showModalBottomSheet<(Shift, Energy)>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => CheckInSheet(shift: _w.shift, energy: _w.energy),
    );
    if (result != null) store.updateCheckIn(_w, result.$1, result.$2);
  }

  Future<void> _finish() async {
    if (_w.totalSets == 0) {
      await _discard();
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Finish workout?'),
        content: Text(
            '${fmtClock(_w.duration)}  ·  ${_w.totalSets} sets  ·  ${fmtKg(_w.volume)} kg lifted'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep going'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Finish'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    store.finishWorkout(_w);
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => WorkoutDetailScreen(workout: _w)),
    );
  }

  Future<void> _discard() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard workout?'),
        content: const Text(
            'This moves the workout to Deleted workouts, where it can be restored.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    store.deleteWorkout(_w);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final editing = !_w.isActive;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: editing
              ? const Text('Edit workout')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Workout'),
                    Text(
                      fmtClock(_w.duration),
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
          actions: [
            if (!editing)
              IconButton(
                tooltip: 'Discard workout',
                onPressed: _discard,
                icon: const Icon(Icons.delete_outline),
              ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton(
                onPressed: editing ? () => Navigator.pop(context) : _finish,
                child: Text(editing ? 'Done' : 'Finish'),
              ),
            ),
          ],
        ),
        body: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          children: [
            WorkoutSummaryCard(workout: _w, onEditCheckIn: _editCheckIn),
            TextButton.icon(
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                        builder: (_) => RecoveryScreen(date: _w.start))),
                icon: const Icon(Icons.accessibility_new),
                label: const Text('Daily soreness (optional)')),
            if (editing)
              TextButton.icon(
                  onPressed: () async {
                    final date = await showDatePicker(
                        context: context,
                        initialDate: _w.start,
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now());
                    if (date != null) store.updateWorkoutDate(_w, date);
                  },
                  icon: const Icon(Icons.calendar_today),
                  label: const Text('Correct workout date')),
            const SizedBox(height: 12),
            if (_w.exercises.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 32),
                child: EmptyState(
                  icon: Icons.fitness_center,
                  title: 'No exercises yet',
                  message: 'Tap "Add exercise" to pick your first one.',
                ),
              ),
            for (final entry in _w.exercises)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ExerciseCard(
                    key: ObjectKey(entry), workout: _w, entry: entry),
              ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _addExercise,
          icon: const Icon(Icons.add),
          label: const Text('Add exercise'),
        ),
      ),
    );
  }
}
