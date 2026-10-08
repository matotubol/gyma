import 'package:flutter/material.dart';

import '../format.dart';
import '../models.dart';
import '../store.dart';
import '../widgets.dart';
import 'workout_detail_screen.dart';

class HistoryTab extends StatefulWidget {
  const HistoryTab({super.key});

  @override
  State<HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<HistoryTab> {
  Shift? _shift;
  Energy? _energy;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final all = store.finishedWorkouts;
        if (all.isEmpty) {
          return const EmptyState(
            icon: Icons.fitness_center,
            title: 'No workouts yet',
            message: 'Tap "Start workout" to log your first session.',
          );
        }
        final shown = [
          for (final w in all)
            if ((_shift == null || w.shift == _shift) &&
                (_energy == null || w.energy == _energy))
              w
        ];
        return ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            _WeekCard(all),
            FilterBar(
              shift: _shift,
              energy: _energy,
              onShift: (s) => setState(() => _shift = s),
              onEnergy: (e) => setState(() => _energy = e),
            ),
            const SizedBox(height: 10),
            if (shown.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Text('No workouts match these filters.',
                    textAlign: TextAlign.center),
              ),
            for (final w in shown)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: _WorkoutTile(w),
              ),
          ],
        );
      },
    );
  }
}

/// Mon–Sun dots for this week plus weekly totals.
class _WeekCard extends StatelessWidget {
  const _WeekCard(this.workouts);

  final List<Workout> workouts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
    final week = [
      for (final w in workouts)
        if (!w.start.isBefore(monday)) w
    ];
    final trained = {for (final w in week) w.start.weekday};
    final volume = week.fold<double>(0, (a, w) => a + w.volume);
    final time = week.fold(Duration.zero, (a, w) => a + w.duration);

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('This week', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var d = 1; d <= 7; d++)
                  Column(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: trained.contains(d)
                              ? scheme.primary
                              : scheme.surfaceContainerHighest,
                          border: d == now.weekday
                              ? Border.all(color: scheme.primary, width: 2)
                              : null,
                        ),
                        child: trained.contains(d)
                            ? Icon(Icons.check,
                                size: 18, color: scheme.onPrimary)
                            : null,
                      ),
                      const SizedBox(height: 4),
                      Text('MTWTFSS'[d - 1], style: theme.textTheme.labelSmall),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: StatTile('${week.length}', 'Workouts')),
                Expanded(child: StatTile(fmtKg(volume), 'kg lifted')),
                Expanded(child: StatTile(fmtDuration(time), 'Time')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkoutTile extends StatelessWidget {
  const _WorkoutTile(this.workout);

  final Workout workout;

  @override
  Widget build(BuildContext context) {
    final w = workout;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    const maxIcons = 6;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => WorkoutDetailScreen(workout: w))),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 54,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    Text(weekdayShort(w.start),
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: scheme.onPrimaryContainer)),
                    Text('${w.start.day}',
                        style: theme.textTheme.titleLarge?.copyWith(
                            color: scheme.onPrimaryContainer,
                            fontWeight: FontWeight.w700)),
                    Text(monthShort(w.start),
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: scheme.onPrimaryContainer)),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${fmtTime(w.start)} – ${fmtTime(w.end!)}  ·  ${fmtDuration(w.duration)}',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [ShiftPill(w.shift), EnergyPill(w.energy)],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final e in w.exercises.take(maxIcons))
                          ExerciseAvatar(store.exercise(e.exerciseId),
                              size: 28),
                        if (w.exercises.length > maxIcons)
                          Text('+${w.exercises.length - maxIcons}',
                              style: theme.textTheme.labelMedium),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${w.exercises.length} exercises · ${w.totalSets} sets · ${fmtKg(w.volume)} kg',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
