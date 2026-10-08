import 'package:flutter/material.dart';

import '../analytics.dart';
import '../format.dart';
import '../models.dart';
import '../store.dart';
import '../widgets.dart';
import 'exercise_progress_screen.dart';
import 'recovery_screen.dart';
import 'coach_tab.dart';

class ProgressTab extends StatefulWidget {
  const ProgressTab(
      {super.key,
      required this.onStartWorkout,
      this.onOpenCoach,
      this.onOpenProgress});
  final VoidCallback onStartWorkout;
  final VoidCallback? onOpenCoach;
  final VoidCallback? onOpenProgress;

  @override
  State<ProgressTab> createState() => _ProgressTabState();
}

class _ProgressTabState extends State<ProgressTab> {
  int _days = 28;

  void _openExercise(String id) => Navigator.push(
      context,
      MaterialPageRoute<void>(
          builder: (_) => ExerciseProgressScreen(exerciseId: id)));

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final theme = Theme.of(context);
          final scheme = theme.colorScheme;
          final now = DateTime.now();
          final from = DateTime(now.year, now.month, now.day - _days + 1);
          final workouts = store.finishedWorkouts
              .where((w) => !w.start.isBefore(from) && isFinishedAt(w, now))
              .toList();
          final trends = exerciseTrends(store, now, _days);
          final repChanges = repTrends(store, now, _days).take(3).toList();
          final week = weeklyReview(store, now);
          final allHistory = store.finishedWorkouts
              .where((w) => isFinishedAt(w, now))
              .toList()
            ..sort((a, b) => b.start.compareTo(a.start));
          final last = allHistory.firstOrNull;
          final gap =
              last == null ? null : calendarDaysBetween(last.start, now);
          final up = trends.where((t) => t.delta > 0).take(3).toList();
          final down =
              trends.reversed.where((t) => t.delta < 0).take(3).toList();
          final ids = {
            for (final w in workouts)
              for (final e in w.exercises)
                if (e.sets.isNotEmpty) e.exerciseId,
          }.toList()
            ..sort((a, b) =>
                store.exercise(a).name.compareTo(store.exercise(b).name));
          final muscleSets = {
            for (final m in Muscle.values)
              m: workouts.fold<int>(
                  0,
                  (n, w) =>
                      n +
                      w.exercises
                          .where(
                              (e) => store.exercise(e.exerciseId).muscle == m)
                          .fold<int>(
                              0,
                              (n, e) =>
                                  n +
                                  e.sets
                                      .where((s) => s.isWarmup != true)
                                      .length)),
          };
          final mostSets =
              muscleSets.values.fold<int>(0, (a, b) => a > b ? a : b);
          final active = store.activeWorkout;
          return ListView(
            key: const PageStorageKey('overview'),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            children: [
              Text(fmtDate(now),
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 4),
              Text('Your training',
                  style: theme.textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.w700, letterSpacing: -1)),
              const SizedBox(height: 20),
              Card(
                color: scheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(children: [
                          Icon(
                              active == null
                                  ? Icons.fitness_center
                                  : Icons.play_circle_outline,
                              color: scheme.onPrimaryContainer),
                          const SizedBox(width: 10),
                          Expanded(
                              child: Text(
                                  active == null
                                      ? (gap != null && gap >= 14
                                          ? 'Welcome back'
                                          : 'Make today count')
                                      : 'Workout in progress',
                                  style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: scheme.onPrimaryContainer))),
                        ]),
                        const SizedBox(height: 8),
                        Text(
                            active == null
                                ? (gap == null
                                    ? 'Check in with your coach and build a session around your goal.'
                                    : gap >= 14
                                        ? '$gap days since your last logged workout. Check in before choosing today’s starting point.'
                                        : 'Start with how you feel. Leave with a clear plan for today.')
                                : '${active.exercises.length} exercises · ${active.totalSets} sets logged',
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(color: scheme.onPrimaryContainer)),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: widget.onStartWorkout,
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: Text(active == null
                              ? 'Start workout'
                              : 'Resume workout'),
                        ),
                      ]),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (widget.onOpenCoach != null)
                  OutlinedButton.icon(
                      onPressed: widget.onOpenCoach,
                      icon: const Icon(Icons.forum_outlined),
                      label: const Text('Talk to coach')),
                if (widget.onOpenProgress != null)
                  OutlinedButton.icon(
                      onPressed: widget.onOpenProgress,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Photos & measurements')),
              ]),
              const SizedBox(height: 16),
              Card(
                  child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Your last 7 days',
                                style: theme.textTheme.titleMedium),
                            const SizedBox(height: 8),
                            Text(
                                week['sessions'] == 0
                                    ? 'A fresh starting point'
                                    : '${week['sessions']} completed ${week['sessions'] == 1 ? 'session' : 'sessions'} · ${week['trainingDays']} training ${week['trainingDays'] == 1 ? 'day' : 'days'}',
                                style: theme.textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 8),
                            Text(
                                week['sessions'] == 0
                                    ? 'Choose a session that fits today. Your earlier history is still here.'
                                    : '${week['workingSets']} working sets · ${week['setsWithEffort']} with effort recorded${week['unclassifiedSets'] == 0 ? '' : ' · ${week['unclassifiedSets']} older or unclassified sets'}.',
                                style: theme.textTheme.bodyMedium
                                    ?.copyWith(color: scheme.onSurfaceVariant)),
                            if (widget.onOpenCoach != null)
                              TextButton(
                                  onPressed: () => Navigator.push(
                                      context,
                                      MaterialPageRoute<void>(
                                          builder: (_) => Scaffold(
                                              appBar: AppBar(
                                                  title: const Text(
                                                      'Weekly review')),
                                              body: const SafeArea(
                                                  child: CoachTab(
                                                      initialQuestion:
                                                          'Review my last seven days against my goal. Recognize progress, explain what is uncertain, and suggest one useful adjustment for next week.'))))),
                                  child: const Text('Review my week')),
                          ]))),
              const SizedBox(height: 12),
              const RecoveryCard(),
              const SizedBox(height: 28),
              Text('Your activity',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              SegmentedButton<int>(
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  textStyle: theme.textTheme.labelMedium
                      ?.copyWith(fontSize: 12, fontWeight: FontWeight.w600),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                segments: const [
                  ButtonSegment(value: 7, label: Text('7 days')),
                  ButtonSegment(value: 28, label: Text('4 weeks')),
                  ButtonSegment(value: 84, label: Text('12 weeks')),
                ],
                selected: {_days},
                onSelectionChanged: (s) => setState(() => _days = s.first),
              ),
              const SizedBox(height: 12),
              Card(
                  child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _Stat('${workouts.length}', 'Workouts')),
                      Expanded(
                          child: _Stat(
                              '${workouts.fold<int>(0, (n, w) => n + w.totalSets)}',
                              'Sets logged')),
                      Expanded(child: _Stat('${ids.length}', 'Exercises')),
                    ]),
              )),
              const SizedBox(height: 28),
              Text('Recent changes',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Card(
                  child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (up.isEmpty && down.isEmpty && repChanges.isEmpty) ...[
                        Icon(Icons.insights_outlined, color: scheme.primary),
                        const SizedBox(height: 12),
                        Text(
                            workouts.isEmpty
                                ? 'Progress starts with your first session'
                                : trends.isEmpty
                                    ? 'More sessions, a clearer picture'
                                    : 'Loads are unchanged',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        Text(
                            trends.isEmpty
                                ? 'Changes appear after logging the same exercise at the same rep count in two sessions.'
                                : 'Comparable loads match across the latest two sessions in this period.',
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(color: scheme.onSurfaceVariant)),
                      ],
                      if (up.isNotEmpty)
                        _trendGroup(context, 'Higher loads', up),
                      if (up.isNotEmpty && down.isNotEmpty)
                        const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Divider()),
                      if (down.isNotEmpty)
                        _trendGroup(context, 'Lower loads', down),
                      if (repChanges.isNotEmpty) ...[
                        if (up.isNotEmpty || down.isNotEmpty)
                          const Divider(height: 24),
                        Text('Reps at the same weight',
                            style: theme.textTheme.labelLarge),
                        for (final t in repChanges)
                          ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.repeat),
                              title: Text(store.exercise(t.exerciseId).name),
                              subtitle: Text(
                                  '${t.previousReps} → ${t.currentReps} reps · ${fmtKg(t.kg)} kg'),
                              onTap: () => _openExercise(t.exerciseId)),
                        Text(
                            'Logged performance at matching weight; effort and technique may differ.',
                            style: theme.textTheme.bodySmall),
                      ],
                      if (up.isNotEmpty || down.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                            'Latest two sessions at matching reps. Lower loads can be intentional; effort and technique may differ.',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant)),
                      ],
                    ]),
              )),
              if (mostSets > 0) ...[
                const SizedBox(height: 28),
                Text('Muscle groups',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('Sets excluding marked warm-ups',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 12),
                Card(
                    child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(children: [
                    for (final m in Muscle.values)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Column(children: [
                          Row(children: [
                            Expanded(
                                child: Text(m.label,
                                    style: theme.textTheme.bodyMedium)),
                            Text('${muscleSets[m]} sets',
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: scheme.onSurfaceVariant)),
                          ]),
                          const SizedBox(height: 7),
                          ExcludeSemantics(
                              child: LinearProgressIndicator(
                            value: muscleSets[m]! / mostSets,
                            minHeight: 5,
                            borderRadius: BorderRadius.circular(4),
                            color: m.color,
                            backgroundColor: scheme.surfaceContainerHighest,
                          )),
                        ]),
                      ),
                    Text(
                        'Primary muscle groups only. Older unclassified sets are included; these bars are not targets.',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                  ]),
                )),
              ],
              if (ids.isNotEmpty) ...[
                const SizedBox(height: 20),
                Card(
                    clipBehavior: Clip.antiAlias,
                    child: ExpansionTile(
                      shape: const Border(),
                      collapsedShape: const Border(),
                      title: const Text('Exercise history'),
                      subtitle: Text('${ids.length} exercises in this period'),
                      children: [
                        for (final id in ids)
                          ListTile(
                            leading:
                                ExerciseAvatar(store.exercise(id), size: 36),
                            title: Text(store.exercise(id).name),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => _openExercise(id),
                          ),
                      ],
                    )),
              ],
            ],
          );
        },
      );

  Widget _trendGroup(
      BuildContext context, String title, List<ExerciseTrend> trends) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title,
          style: theme.textTheme.labelLarge
              ?.copyWith(color: scheme.onSurfaceVariant)),
      for (final t in trends)
        InkWell(
          onTap: () => _openExercise(t.exerciseId),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(t.delta > 0 ? Icons.trending_up : Icons.trending_down,
                  size: 22, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(store.exercise(t.exerciseId).name,
                        style: theme.textTheme.titleSmall),
                    const SizedBox(height: 4),
                    Text(
                        '${fmtKg(t.previousKg)} → ${fmtKg(t.currentKg)} kg · ${t.reps} reps',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 6),
                    Text(
                        '${t.delta > 0 ? '+' : ''}${t.percent.toStringAsFixed(1)}%',
                        style: theme.textTheme.labelLarge
                            ?.copyWith(color: scheme.primary)),
                  ])),
              Icon(Icons.chevron_right_rounded,
                  size: 20, color: scheme.onSurfaceVariant),
            ]),
          ),
        ),
    ]);
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label);
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(children: [
      Text(value,
          style: theme.textTheme.headlineMedium
              ?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      Text(label,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    ]);
  }
}
