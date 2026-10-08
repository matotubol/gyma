import 'package:flutter/material.dart';

import '../models.dart';

/// Bottom sheet asked before every workout: did you work, and how do you feel?
/// Pops with a `(Shift, Energy)` record.
class CheckInSheet extends StatefulWidget {
  const CheckInSheet({super.key, this.shift, this.energy});

  final Shift? shift;
  final Energy? energy;

  @override
  State<CheckInSheet> createState() => _CheckInSheetState();
}

class _CheckInSheetState extends State<CheckInSheet> {
  late Shift? _shift = widget.shift;
  late Energy? _energy = widget.energy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final editing = widget.shift != null;
    final shift = _shift;
    final energy = _energy;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(editing ? 'Edit check-in' : 'Before you start',
                  style: theme.textTheme.headlineSmall),
            ),
            const SizedBox(height: 20),
            const _SectionLabel('Did you work today?'),
            Row(
              children: [
                for (final s in Shift.values)
                  Expanded(
                    child: _ChoiceTile(
                      selected: shift == s,
                      color: theme.colorScheme.primary,
                      leading: Icon(s.icon, size: 26),
                      label: s.short,
                      onTap: () => setState(() => _shift = s),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            const _SectionLabel('How is your energy?'),
            Row(
              children: [
                for (final e in Energy.values)
                  Expanded(
                    child: _ChoiceTile(
                      selected: energy == e,
                      color: e.color,
                      leading: Text(e.emoji, style: const TextStyle(fontSize: 26)),
                      label: e.label,
                      onTap: () => setState(() => _energy = e),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 28),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52)),
                onPressed: shift == null || energy == null
                    ? null
                    : () => Navigator.pop(context, (shift, energy)),
                icon: Icon(editing ? Icons.check : Icons.play_arrow_rounded),
                label: Text(editing ? 'Save' : "Let's go"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.selected,
    required this.color,
    required this.leading,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final Color color;
  final Widget leading;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: selected
            ? color.withValues(alpha: 0.16)
            : scheme.surfaceContainerHighest,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
              color: selected ? color : Colors.transparent, width: 2),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
            child: Column(
              children: [
                IconTheme(
                  data: IconThemeData(
                      color: selected ? color : scheme.onSurfaceVariant),
                  child: leading,
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
