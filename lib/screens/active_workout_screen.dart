import 'dart:async';

import 'package:flutter/material.dart';

import '../format.dart';
import '../models.dart';
import '../store.dart';
import '../widgets.dart';
import 'check_in_sheet.dart';
import 'exercise_card.dart';
import 'exercise_log_screen.dart';
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
    if (id == null || !mounted) return;
    store.addExercise(_w, id);
    await _openExercise(_w.exercises.last);
  }

  Future<void> _openExercise(WorkoutExercise entry) =>
      Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => ExerciseLogScreen(workout: _w, entry: entry),
      ));

  Future<void> _workoutAction(String action) async {
    switch (action) {
      case 'check-in':
        await _editCheckIn();
      case 'recovery':
        if (!mounted) return;
        await Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => RecoveryScreen(date: _w.start),
            ));
      case 'date':
        final date = await showDatePicker(
          context: context,
          initialDate: _w.start,
          firstDate: DateTime(2000),
          lastDate: DateTime.now(),
        );
        if (date != null) store.updateWorkoutDate(_w, date);
      case 'discard':
        await _discard();
    }
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
          title: Text(editing ? 'Edit workout' : 'Workout'),
          actions: [
            TextButton(
              onPressed: editing ? () => Navigator.pop(context) : _finish,
              child: Text(editing ? 'Done' : 'Finish'),
            ),
            PopupMenuButton<String>(
              tooltip: 'Workout options',
              onSelected: _workoutAction,
              itemBuilder: (_) => [
                const PopupMenuItem(
                    value: 'check-in', child: Text('Edit shift & energy')),
                const PopupMenuItem(
                    value: 'recovery', child: Text('Daily soreness')),
                if (editing)
                  const PopupMenuItem(
                      value: 'date', child: Text('Correct workout date')),
                if (!editing)
                  const PopupMenuItem(
                      value: 'discard', child: Text('Discard workout')),
              ],
            ),
          ],
        ),
        body: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Card(
                child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(editing ? fmtDate(_w.start) : 'IN PROGRESS',
                        style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            letterSpacing: 1.2)),
                    const SizedBox(height: 16),
                    Row(children: [
                      Expanded(
                          child: StatTile(fmtClock(_w.duration), 'Duration')),
                      Expanded(
                          child:
                              StatTile('${_w.exercises.length}', 'Exercises')),
                      Expanded(
                          child: StatTile('${_w.totalSets}', 'Sets logged')),
                    ]),
                    const SizedBox(height: 20),
                    InkWell(
                      onTap: _editCheckIn,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(children: [
                          Expanded(
                              child: Wrap(spacing: 8, runSpacing: 8, children: [
                            ShiftPill(_w.shift),
                            EnergyPill(_w.energy)
                          ])),
                          const SizedBox(width: 8),
                          Icon(Icons.edit_outlined,
                              size: 18,
                              color: theme.colorScheme.onSurfaceVariant),
                        ]),
                      ),
                    ),
                  ]),
            )),
            const SizedBox(height: 28),
            Text('Your exercises',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Open an exercise to log or edit its sets.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 16),
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
                    key: ObjectKey(entry),
                    entry: entry,
                    onTap: () => _openExercise(entry)),
              ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: FilledButton.icon(
            onPressed: _addExercise,
            icon: const Icon(Icons.add),
            label: const Text('Add exercise'),
          ),
        ),
      ),
    );
  }
}
