import 'package:flutter/material.dart';

import '../format.dart';
import '../line_chart.dart';
import '../models.dart';
import '../store.dart';
import '../widgets.dart';

enum _Metric {
  top('Top kg'),
  oneRm('Est. 1RM'),
  volume('Volume');

  const _Metric(this.label);
  final String label;
}

/// Growth of one exercise over time, filterable by shift and energy.
class ExerciseProgressScreen extends StatefulWidget {
  const ExerciseProgressScreen({super.key, required this.exerciseId});

  final String exerciseId;

  @override
  State<ExerciseProgressScreen> createState() => _ExerciseProgressScreenState();
}

class _ExerciseProgressScreenState extends State<ExerciseProgressScreen> {
  _Metric _metric = _Metric.top;
  Shift? _shift;
  Energy? _energy;

  double _value(WorkoutExercise e) => switch (_metric) {
        _Metric.top => e.topKg,
        _Metric.oneRm => e.best1rm,
        _Metric.volume => e.volume,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final def = store.exercise(widget.exerciseId);
        final history = [
          for (final h in store.historyFor(widget.exerciseId))
            if ((_shift == null || h.$1.shift == _shift) &&
                (_energy == null || h.$1.energy == _energy))
              h
        ];
        final values = [for (final h in history) _value(h.$2)];

        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                ExerciseAvatar(def, size: 34),
                const SizedBox(width: 10),
                Flexible(child: Text(def.name, overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.only(top: 8, bottom: 32),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SegmentedButton<_Metric>(
                  showSelectedIcon: false,
                  segments: [
                    for (final m in _Metric.values)
                      ButtonSegment(value: m, label: Text(m.label)),
                  ],
                  selected: {_metric},
                  onSelectionChanged: (s) => setState(() => _metric = s.first),
                ),
              ),
              const SizedBox(height: 12),
              FilterBar(
                shift: _shift,
                energy: _energy,
                onShift: (s) => setState(() => _shift = s),
                onEnergy: (e) => setState(() => _energy = e),
              ),
              const SizedBox(height: 12),
              if (history.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('No sessions match these filters.',
                      textAlign: TextAlign.center),
                )
              else ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 20, 16, 12),
                      child: SizedBox(
                        height: 200,
                        child: LineChart(values: values, color: def.muscle.color),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: StatTile(
                            fmtKg(values.reduce((a, b) => a > b ? a : b)), 'Best'),
                      ),
                      Expanded(child: StatTile(fmtKg(values.last), 'Latest')),
                      Expanded(
                        child: StatTile(
                          '${values.last >= values.first ? '+' : ''}${fmtKg(values.last - values.first)}',
                          'Since first',
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 16, 4),
                  child: Text('Sessions', style: theme.textTheme.titleMedium),
                ),
                for (final h in history.reversed)
                  ListTile(
                    leading: Icon(h.$1.shift.icon),
                    title: Text(
                        '${fmtDate(h.$1.start)}  ·  ${h.$1.energy.emoji} ${h.$1.energy.label}'),
                    subtitle: Text(
                      h.$2.sets
                          .map((s) => '${fmtKg(s.kg)}×${s.reps}')
                          .join('   '),
                      style: muted,
                    ),
                    trailing: Text(
                      fmtKg(_value(h.$2)),
                      style: theme.textTheme.titleMedium
                          ?.copyWith(color: def.muscle.color),
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}
