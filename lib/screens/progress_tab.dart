import 'package:flutter/material.dart';

import '../format.dart';
import '../models.dart';
import '../store.dart';
import '../widgets.dart';
import 'exercise_progress_screen.dart';

class ProgressTab extends StatelessWidget {
  const ProgressTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final workouts = store.finishedWorkouts;
        if (workouts.isEmpty) {
          return const EmptyState(
            icon: Icons.insights,
            title: 'No progress yet',
            message: 'Finish a workout and your progress shows up here.',
          );
        }

        double avgVolume(Iterable<Workout> ws) => ws.isEmpty
            ? 0
            : ws.fold<double>(0, (a, w) => a + w.volume) / ws.length;

        final exerciseIds = <String>{
          for (final w in workouts)
            for (final e in w.exercises)
              if (e.sets.isNotEmpty) e.exerciseId
        };

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _BarsCard(
              title: 'Energy vs. performance',
              rows: [
                for (final e in Energy.values)
                  _Bar(
                    leading: Text(e.emoji),
                    label: e.label,
                    color: e.color,
                    workouts: [for (final w in workouts) if (w.energy == e) w],
                    avg: avgVolume([for (final w in workouts) if (w.energy == e) w]),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _BarsCard(
              title: 'Shift vs. performance',
              rows: [
                for (final s in Shift.values)
                  _Bar(
                    leading: Icon(s.icon, size: 18),
                    label: s.short,
                    color: Theme.of(context).colorScheme.primary,
                    workouts: [for (final w in workouts) if (w.shift == s) w],
                    avg: avgVolume([for (final w in workouts) if (w.shift == s) w]),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text('Exercises',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            for (final id in exerciseIds) _ExerciseRow(id),
          ],
        );
      },
    );
  }
}

class _Bar {
  const _Bar({
    required this.leading,
    required this.label,
    required this.color,
    required this.workouts,
    required this.avg,
  });

  final Widget leading;
  final String label;
  final Color color;
  final List<Workout> workouts;
  final double avg;
}

/// Average kg lifted per workout, split by a check-in answer.
class _BarsCard extends StatelessWidget {
  const _BarsCard({required this.title, required this.rows});

  final String title;
  final List<_Bar> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final top = rows.fold<double>(0, (a, r) => r.avg > a ? r.avg : a);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            Text('Average kg lifted per workout',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    SizedBox(
                      width: 100,
                      child: Row(
                        children: [
                          IconTheme(
                            data: IconThemeData(color: r.color),
                            child: r.leading,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(r.label,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelLarge),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Container(
                        height: 10,
                        alignment: Alignment.centerLeft,
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: FractionallySizedBox(
                          widthFactor: top == 0 ? 0 : r.avg / top,
                          child: Container(
                            decoration: BoxDecoration(
                              color: r.color,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 92,
                      child: Text(
                        r.workouts.isEmpty
                            ? '–'
                            : '${fmtKg(r.avg)} kg (${r.workouts.length}×)',
                        textAlign: TextAlign.end,
                        style: theme.textTheme.labelMedium,
                      ),
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

class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow(this.exerciseId);

  final String exerciseId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final def = store.exercise(exerciseId);
    final history = store.historyFor(exerciseId);
    final best = history.fold<double>(
        0, (a, h) => h.$2.topKg > a ? h.$2.topKg : a);
    final delta = history.length < 2
        ? null
        : history.last.$2.topKg - history[history.length - 2].$2.topKg;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: ExerciseAvatar(def),
        title: Text(def.name),
        subtitle: Text(
            'Best ${fmtKg(best)} kg · ${history.length} session${history.length == 1 ? '' : 's'}'),
        trailing: delta == null
            ? const Icon(Icons.chevron_right)
            : _Trend(delta, style: theme.textTheme.labelLarge),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => ExerciseProgressScreen(exerciseId: exerciseId))),
      ),
    );
  }
}

class _Trend extends StatelessWidget {
  const _Trend(this.delta, {this.style});

  final double delta;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final up = delta > 0;
    final color = delta == 0
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : (up ? const Color(0xFF2E7D32) : const Color(0xFFE53935));
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          delta == 0
              ? Icons.trending_flat
              : (up ? Icons.trending_up : Icons.trending_down),
          color: color,
          size: 20,
        ),
        const SizedBox(width: 4),
        Text('${up ? '+' : ''}${fmtKg(delta)} kg',
            style: style?.copyWith(color: color)),
      ],
    );
  }
}
