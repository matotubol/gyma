import 'package:flutter/material.dart';

import '../format.dart';
import '../models.dart';
import '../store.dart';
import '../widgets.dart';

/// A compact summary. Logging happens on the exercise's own screen.
class ExerciseCard extends StatelessWidget {
  const ExerciseCard({super.key, required this.entry, required this.onTap});

  final WorkoutExercise entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final def = store.exercise(entry.exerciseId);
    final last = entry.sets.lastOrNull;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            ExerciseAvatar(def, size: 48),
            const SizedBox(width: 14),
            Expanded(
                child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(def.name,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(
                  last == null
                      ? '${def.muscle.label} · Log your first set'
                      : '${entry.sets.length} ${entry.sets.length == 1 ? 'set' : 'sets'} · Last: ${fmtKg(last.kg)} kg × ${last.reps}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                if (entry.target case final target?) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Plan: ${target.sets} × ${target.repsMin}–${target.repsMax} reps'
                    ' · ${entry.sets.where((set) => set.isWarmup == false).length} working sets logged',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.primary),
                  ),
                ],
              ],
            )),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded,
                color: theme.colorScheme.onSurfaceVariant),
          ]),
        ),
      ),
    );
  }
}
