import 'package:flutter/material.dart';
import '../analytics.dart';
import '../format.dart';
import '../models.dart';
import '../store.dart';
import 'exercise_progress_screen.dart';
import 'recovery_screen.dart';

class ProgressTab extends StatefulWidget {
  const ProgressTab({super.key});
  @override
  State<ProgressTab> createState() => _ProgressTabState();
}

class _ProgressTabState extends State<ProgressTab> {
  int _days = 28;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final now = DateTime.now();
        final from = DateTime(now.year, now.month, now.day - _days + 1);
        final workouts = store.finishedWorkouts
            .where((w) => !w.start.isBefore(from) && !w.start.isAfter(now))
            .toList();
        final trends = exerciseTrends(store, now, _days);
        final up = trends.where((t) => t.delta > 0).take(3).toList();
        final down = trends.reversed.where((t) => t.delta < 0).take(3).toList();
        final ids = {
          for (final w in workouts)
            for (final e in w.exercises) e.exerciseId
        };
        return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            children: [
              Text('Your training, at a glance',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 12),
              SegmentedButton<int>(segments: const [
                ButtonSegment(value: 7, label: Text('7 days')),
                ButtonSegment(value: 28, label: Text('4 weeks')),
                ButtonSegment(value: 84, label: Text('12 weeks'))
              ], selected: {
                _days
              }, onSelectionChanged: (s) => setState(() => _days = s.first)),
              const SizedBox(height: 12),
              Card(
                  child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(children: [
                        Expanded(
                            child: _Stat('${workouts.length}', 'Workouts')),
                        Expanded(
                            child: _Stat(
                                '${workouts.fold<int>(0, (n, w) => n + w.totalSets)}',
                                'Logged sets')),
                        Expanded(child: _Stat('${ids.length}', 'Exercises')),
                      ]))),
              const RecoveryCard(),
              _section(context, 'Top improvements', up,
                  'No comparable increases in this period.'),
              _section(context, 'Needs attention', down,
                  'No comparable decreases in this period.'),
              const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text(
                      'Latest two sessions in this period, at the same rep count. Effort and technique may differ. A decrease can be intentional; it is not automatically lost progress.')),
              Card(
                  child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Training balance',
                                style: Theme.of(context).textTheme.titleMedium),
                            const Text(
                                'Logged sets by primary muscle group. Includes any warm-up sets you logged; no target assumed.'),
                            const SizedBox(height: 12),
                            for (final m in Muscle.values)
                              Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 6),
                                  child: Row(children: [
                                    Expanded(child: Text(m.label)),
                                    Text(
                                        '${workouts.fold<int>(0, (n, w) => n + w.exercises.where((e) => store.exercise(e.exerciseId).muscle == m).fold<int>(0, (a, e) => a + e.sets.length))} sets'),
                                  ])),
                          ]))),
              const SizedBox(height: 16),
              Text('Exercise history',
                  style: Theme.of(context).textTheme.titleMedium),
              if (ids.isEmpty)
                const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                        'Finish a workout to start building your progress.')),
              for (final id in ids)
                ListTile(
                    title: Text(store.exercise(id).name),
                    subtitle: const Text('View sessions and records'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                            builder: (_) =>
                                ExerciseProgressScreen(exerciseId: id)))),
            ]);
      });

  Widget _section(BuildContext context, String title,
          List<ExerciseTrend> trends, String empty) =>
      Card(
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    if (trends.isEmpty) Text(empty),
                    for (final t in trends)
                      ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                              t.delta > 0
                                  ? Icons.trending_up
                                  : Icons.trending_down,
                              color: t.delta > 0
                                  ? const Color(0xFF2E7D32)
                                  : const Color(0xFFB56713)),
                          title: Text(store.exercise(t.exerciseId).name),
                          subtitle: Text(
                              '${fmtKg(t.previousKg)} → ${fmtKg(t.currentKg)} kg × ${t.reps} reps\n2 sessions · limited evidence'),
                          isThreeLine: true,
                          trailing: Text(
                              '${t.delta > 0 ? '+' : ''}${t.percent.toStringAsFixed(1)}%'),
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                  builder: (_) => ExerciseProgressScreen(
                                      exerciseId: t.exerciseId)))),
                  ])));
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label);
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) => Column(children: [
        Text(value, style: Theme.of(context).textTheme.headlineSmall),
        Text(label),
      ]);
}
