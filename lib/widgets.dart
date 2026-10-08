import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'format.dart';
import 'models.dart';

/// Rounded, muscle-coloured tile with the exercise's icon.
class ExerciseAvatar extends StatelessWidget {
  const ExerciseAvatar(this.exercise, {super.key, this.size = 44});

  final ExerciseDef exercise;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = exercise.muscle.color;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(exercise.icon, color: color, size: size * 0.56),
    );
  }
}

/// Small rounded label, e.g. "🙂 Good" or "🌙 Night shift".
class Pill extends StatelessWidget {
  const Pill({super.key, required this.leading, required this.label, this.color});

  final Widget leading;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: (color ?? scheme.primary).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconTheme(
            data: IconThemeData(size: 16, color: color ?? scheme.primary),
            child: leading,
          ),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }
}

class ShiftPill extends StatelessWidget {
  const ShiftPill(this.shift, {super.key});
  final Shift shift;

  @override
  Widget build(BuildContext context) =>
      Pill(leading: Icon(shift.icon), label: shift.label);
}

class EnergyPill extends StatelessWidget {
  const EnergyPill(this.energy, {super.key});
  final Energy energy;

  @override
  Widget build(BuildContext context) => Pill(
        leading: Text(energy.emoji, style: const TextStyle(fontSize: 13)),
        label: energy.label,
        color: energy.color,
      );
}

class StatTile extends StatelessWidget {
  const StatTile(this.value, this.label, {super.key});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState(
      {super.key, required this.icon, required this.title, required this.message});

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal row of shift + energy filter chips. Tapping a selected chip
/// clears that filter.
class FilterBar extends StatelessWidget {
  const FilterBar({
    super.key,
    required this.shift,
    required this.energy,
    required this.onShift,
    required this.onEnergy,
  });

  final Shift? shift;
  final Energy? energy;
  final ValueChanged<Shift?> onShift;
  final ValueChanged<Energy?> onEnergy;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          for (final s in Shift.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                avatar: Icon(s.icon, size: 18),
                label: Text(s.short),
                selected: shift == s,
                showCheckmark: false,
                onSelected: (selected) => onShift(selected ? s : null),
              ),
            ),
          const SizedBox(height: 24, child: VerticalDivider(width: 16)),
          for (final e in Energy.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                avatar: Text(e.emoji),
                label: Text(e.label),
                selected: energy == e,
                showCheckmark: false,
                onSelected: (selected) => onEnergy(selected ? e : null),
              ),
            ),
        ],
      ),
    );
  }
}

/// Times, check-in and totals for one workout.
class WorkoutSummaryCard extends StatelessWidget {
  const WorkoutSummaryCard({super.key, required this.workout, this.onEditCheckIn});

  final Workout workout;
  final VoidCallback? onEditCheckIn;

  @override
  Widget build(BuildContext context) {
    final w = workout;
    final theme = Theme.of(context);
    final when = w.isActive
        ? 'Started ${fmtTime(w.start)}'
        : '${fmtTime(w.start)} – ${fmtTime(w.end!)}  ·  ${fmtDuration(w.duration)}';
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.schedule, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Expanded(child: Text(when, style: theme.textTheme.titleSmall)),
              ],
            ),
            const SizedBox(height: 10),
            InkWell(
              onTap: onEditCheckIn,
              borderRadius: BorderRadius.circular(20),
              child: Row(
                children: [
                  ShiftPill(w.shift),
                  const SizedBox(width: 8),
                  EnergyPill(w.energy),
                  const Spacer(),
                  if (onEditCheckIn != null)
                    Icon(Icons.edit_outlined,
                        size: 18, color: theme.colorScheme.onSurfaceVariant),
                ],
              ),
            ),
            const Divider(height: 28),
            Row(
              children: [
                Expanded(child: StatTile('${w.exercises.length}', 'Exercises')),
                Expanded(child: StatTile('${w.totalSets}', 'Sets')),
                Expanded(child: StatTile(fmtInt(w.totalReps), 'Reps')),
                Expanded(child: StatTile(fmtKg(w.volume), 'kg total')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact numeric input for kg / reps.
class NumberField extends StatelessWidget {
  const NumberField({
    super.key,
    required this.controller,
    required this.label,
    this.decimal = false,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String label;
  final bool decimal;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(decimal ? r'[0-9.,]' : r'[0-9]')),
      ],
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.titleMedium,
      onTapOutside: (_) => FocusScope.of(context).unfocus(),
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    );
  }
}
