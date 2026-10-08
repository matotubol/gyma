import 'package:flutter/material.dart';

import '../format.dart';
import '../models.dart';
import '../progression.dart';
import '../recovery.dart';
import '../store.dart';
import '../widgets.dart';
import 'active_workout_screen.dart';

class WorkoutDetailScreen extends StatelessWidget {
  const WorkoutDetailScreen({super.key, required this.workout});

  final Workout workout;

  ProgressionSuggestion _suggestion(WorkoutExercise entry) {
    final previous = store
        .historyFor(entry.exerciseId)
        .where((record) => record.$1.start.isBefore(workout.start))
        .lastOrNull;
    return nextSessionSuggestion(entry,
        energy: workout.energy,
        hasPain: (workout.checkIn?.painNote.trim().isNotEmpty ?? false) ||
            (store.recoveryDays[dayKey(workout.start)]?.painAreas.isNotEmpty ??
                false),
        daysSincePrevious: previous == null
            ? null
            : workout.start.difference(previous.$1.start).inDays);
  }

  Widget _review(BuildContext context) {
    final theme = Theme.of(context);
    final startOfDay =
        DateTime(workout.start.year, workout.start.month, workout.start.day);
    final weekStart = startOfDay.subtract(const Duration(days: 6));
    final sessions = store.finishedWorkouts
        .where((session) =>
            !session.start.isBefore(weekStart) &&
            !session.start.isAfter(workout.start) &&
            session.totalSets > 0)
        .length;
    final workingSets = workout.exercises
        .expand((entry) => entry.sets)
        .where((set) => set.isWarmup == false)
        .length;
    return Card(
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Session review', style: theme.textTheme.titleLarge),
            if (workout.planTitle?.isNotEmpty ?? false) ...[
              const SizedBox(height: 4),
              Text(workout.planTitle!, style: theme.textTheme.titleSmall),
            ],
            const SizedBox(height: 10),
            Text(
                '$sessions logged ${sessions == 1 ? 'session' : 'sessions'} in the seven days through this session.'),
            const SizedBox(height: 6),
            Text('$workingSets sets marked as working sets in this session. '
                'Use the suggestions below at your next check-in, when you know how recovered you feel.'),
            const SizedBox(height: 8),
            Text(
                'Suggestions use your logged targets and effort. They are not automatically applied.',
                style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete workout?'),
        content: const Text(
            'You can restore it later from Your data → Deleted workouts.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    store.deleteWorkout(workout);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Text(fmtDate(workout.start)),
          actions: [
            IconButton(
              tooltip: 'Edit',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                      builder: (_) => ActiveWorkoutScreen(workout: workout))),
            ),
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _delete(context),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _review(context),
            const SizedBox(height: 12),
            WorkoutSummaryCard(workout: workout),
            const SizedBox(height: 12),
            for (final entry in workout.exercises)
              if (entry.sets.isNotEmpty || entry.target != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              ExerciseAvatar(store.exercise(entry.exerciseId)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(store.exercise(entry.exerciseId).name,
                                        style: theme.textTheme.titleMedium),
                                    Text(
                                      'Top ${fmtKg(entry.topKg)} kg · ${fmtKg(entry.volume)} kg total',
                                      style: muted,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          if (entry.target case final target?)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Text(
                                  'Planned: ${target.sets} working sets · ${target.repsMin}–${target.repsMax} reps'
                                  '${target.loadKg == null ? '' : ' · ${fmtKg(target.loadKg!)} kg suggested'}',
                                  style: muted),
                            ),
                          if (entry.sets.isEmpty)
                            const Text(
                                'No sets logged. Revisit this exercise at your next check-in.'),
                          for (var i = 0; i < entry.sets.length; i++)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 56,
                                    child: Text('Set ${i + 1}', style: muted),
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${fmtKg(entry.sets[i].kg)} kg  ×  ${entry.sets[i].reps}',
                                          style: theme.textTheme.titleSmall,
                                        ),
                                        Text(
                                            [
                                              if (entry.sets[i].isWarmup ==
                                                  true)
                                                'Warm-up'
                                              else if (entry.sets[i].isWarmup ==
                                                  false)
                                                'Working set'
                                              else
                                                'Set type not recorded',
                                              entry.sets[i].effort?.label ??
                                                  'Effort not recorded',
                                            ].join(' · '),
                                            style: muted),
                                      ],
                                    ),
                                  ),
                                  Text('${fmtKg(entry.sets[i].volume)} kg',
                                      style: muted),
                                ],
                              ),
                            ),
                          if (entry.sets.isNotEmpty) ...[
                            const Divider(height: 28),
                            Text('Next time · ${_suggestion(entry).title}',
                                style: theme.textTheme.titleSmall),
                            const SizedBox(height: 6),
                            Text(_suggestion(entry).reason,
                                style: theme.textTheme.bodyMedium),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
