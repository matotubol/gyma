import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../widgets.dart';

/// Searchable exercise list. Pops with the chosen exercise id.
class ExercisePickerScreen extends StatefulWidget {
  const ExercisePickerScreen({super.key, this.alreadyAdded = const {}});

  final Set<String> alreadyAdded;

  @override
  State<ExercisePickerScreen> createState() => _ExercisePickerScreenState();
}

class _ExercisePickerScreenState extends State<ExercisePickerScreen> {
  String _query = '';
  Muscle? _muscle;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _createCustom() async {
    final def = await showDialog<ExerciseDef>(
      context: context,
      builder: (_) =>
          _NewExerciseDialog(initialMuscle: _muscle ?? Muscle.chest),
    );
    if (def == null || !mounted) return;
    Navigator.pop(context, def.id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final query = _query.trim().toLowerCase();
    final shown = [
      for (final e in store.exercises)
        if ((_muscle == null || e.muscle == _muscle) &&
            e.name.toLowerCase().contains(query))
          e
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add exercise'),
        actions: [
          TextButton.icon(
            onPressed: _createCustom,
            icon: const Icon(Icons.add),
            label: const Text('New'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
          top: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  controller: _search,
                  onChanged: (v) => setState(() => _query = v),
                  onTapOutside: (_) => FocusScope.of(context).unfocus(),
                  decoration: InputDecoration(
                    hintText: 'Search exercises',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            onPressed: () {
                              _search.clear();
                              setState(() => _query = '');
                            },
                            icon: const Icon(Icons.close, size: 20),
                          ),
                    filled: true,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(28),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: const Text('All'),
                        selected: _muscle == null,
                        showCheckmark: false,
                        onSelected: (_) => setState(() => _muscle = null),
                      ),
                    ),
                    for (final m in Muscle.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          avatar:
                              CircleAvatar(backgroundColor: m.color, radius: 5),
                          label: Text(m.label),
                          selected: _muscle == m,
                          showCheckmark: false,
                          onSelected: (_) => setState(() => _muscle = m),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: shown.isEmpty
                    ? EmptyState(
                        icon: Icons.search_off,
                        title: 'Nothing found',
                        message:
                            'Tap "New" to add "${_query.trim()}" yourself.',
                      )
                    : ListView.separated(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.all(16),
                        separatorBuilder: (_, index) =>
                            const SizedBox(height: 8),
                        itemCount: shown.length,
                        itemBuilder: (context, i) {
                          final e = shown[i];
                          final added = widget.alreadyAdded.contains(e.id);
                          return Card(
                            clipBehavior: Clip.antiAlias,
                            child: ListTile(
                              key: ValueKey('pick-${e.id}'),
                              enabled: !added,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              leading: ExerciseAvatar(e, size: 44),
                              title: Text(e.name,
                                  style: theme.textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w600)),
                              subtitle: Text(added
                                  ? '${e.muscle.label} · Already in workout'
                                  : e.muscle.label),
                              trailing: Icon(
                                  added
                                      ? Icons.check_circle_outline
                                      : Icons.add_circle_outline,
                                  color: added
                                      ? theme.colorScheme.onSurfaceVariant
                                      : theme.colorScheme.primary),
                              onTap: added
                                  ? null
                                  : () => Navigator.pop(context, e.id),
                            ),
                          );
                        },
                      ),
              ),
            ],
          )),
    );
  }
}

class _NewExerciseDialog extends StatefulWidget {
  const _NewExerciseDialog({required this.initialMuscle});

  final Muscle initialMuscle;

  @override
  State<_NewExerciseDialog> createState() => _NewExerciseDialogState();
}

class _NewExerciseDialogState extends State<_NewExerciseDialog> {
  final _name = TextEditingController();
  late Muscle _muscle = widget.initialMuscle;
  String _icon = 'barbell';

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(context, store.addCustomExercise(name, _muscle, _icon));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('New exercise'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            Text('Muscle group', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final m in Muscle.values)
                  ChoiceChip(
                    label: Text(m.label),
                    selected: _muscle == m,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _muscle = m),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Icon', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final key in exerciseIcons.keys)
                  GestureDetector(
                    onTap: () => setState(() => _icon = key),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          width: 2,
                          color:
                              _icon == key ? _muscle.color : Colors.transparent,
                        ),
                      ),
                      child: ExerciseAvatar(
                          ExerciseDef('preview', '', _muscle, key),
                          size: 40),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _name.text.trim().isEmpty ? null : _save,
          child: const Text('Add'),
        ),
      ],
    );
  }
}
