import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../format.dart';
import '../models.dart';
import '../progression.dart';
import '../recovery.dart';
import '../store.dart';
import '../widgets.dart';

/// Keeps the current set visible while the exercise's history scrolls below it.
class ExerciseLogScreen extends StatefulWidget {
  const ExerciseLogScreen(
      {super.key, required this.workout, required this.entry});

  final Workout workout;
  final WorkoutExercise entry;

  @override
  State<ExerciseLogScreen> createState() => _ExerciseLogScreenState();
}

class _ExerciseLogScreenState extends State<ExerciseLogScreen> {
  final _kg = TextEditingController();
  final _reps = TextEditingController();
  final _repsFocus = FocusNode();
  final _pageScroll = ScrollController();
  int? _editing;
  String? _kgError;
  String? _repsError;
  String? _announcement;
  late final WorkoutExercise? _previous;
  late final Workout? _previousWorkout;
  SetEffort? _effort;
  bool? _isWarmup = false;
  (String, String, SetEffort?, bool?)? _draft;

  bool get _hasPain =>
      (widget.workout.checkIn?.painNote.trim().isNotEmpty ?? false) ||
      (store.recoveryDays[dayKey(widget.workout.start)]?.painAreas.isNotEmpty ??
          false);

  int? get _gap => _previousWorkout == null
      ? null
      : widget.workout.start.difference(_previousWorkout.start).inDays;

  @override
  void initState() {
    super.initState();
    final history = store
        .historyFor(widget.entry.exerciseId)
        .where((record) => record.$1.start.isBefore(widget.workout.start));
    final previous = history.lastOrNull;
    _previous = previous?.$2;
    _previousWorkout = previous?.$1;
    _seedNewSet();
  }

  void _seedNewSet() {
    final canReuse = widget.workout.energy != Energy.poor &&
        !_hasPain &&
        (_gap == null || _gap! < returnAfterBreakDays);
    final target = widget.entry.target;
    final currentSet = target == null
        ? widget.entry.sets.lastOrNull
        : widget.entry.sets.where((set) => set.isWarmup == false).lastOrNull;
    // A new plan takes precedence over historical loads. A null planned load
    // means the user should choose one, not silently inherit an older load.
    _fill(currentSet);
    if (currentSet == null && target != null) {
      if (!_hasPain && target.loadKg != null) {
        _kg.text = fmtKg(target.loadKg!).replaceAll(',', '');
      }
      _reps.text = '${target.repsMin}';
    } else if (currentSet == null && canReuse) {
      final previousWorkingSet = _previous?.sets
          .where((set) =>
              set.isWarmup == false &&
              set.effort != null &&
              set.effort != SetEffort.limit)
          .lastOrNull;
      _fill(previousWorkingSet);
    }
  }

  void _fill(WorkSet? set, {bool editing = false}) {
    _kg.text = set == null ? '' : fmtKg(set.kg).replaceAll(',', '');
    _reps.text = set == null ? '' : '${set.reps}';
    _kgError = null;
    _repsError = null;
    _effort = editing ? set?.effort : null;
    _isWarmup = editing ? set?.isWarmup : false;
  }

  @override
  void dispose() {
    _kg.dispose();
    _reps.dispose();
    _repsFocus.dispose();
    _pageScroll.dispose();
    super.dispose();
  }

  void _saveSet() {
    final kg = parseKg(_kg.text);
    final reps = int.tryParse(_reps.text.trim());
    setState(() {
      _kgError =
          kg == null || !kg.isFinite || kg < 0 ? 'Enter a valid weight' : null;
      _repsError = reps == null || reps <= 0 ? 'Enter at least 1 rep' : null;
    });
    if (_kgError != null || _repsError != null) return;
    FocusScope.of(context).unfocus();
    final index = _editing;
    final set = WorkSet(kg!, reps!, effort: _effort, isWarmup: _isWarmup);
    if (index == null) {
      store.addSet(widget.entry, set);
      setState(() {
        _announcement = 'Set ${widget.entry.sets.length} logged';
        _seedNewSet();
      });
    } else {
      store.updateSet(widget.entry, index, set);
      _cancelEdit();
      setState(() => _announcement = 'Set ${index + 1} updated');
    }
    HapticFeedback.lightImpact();
  }

  void _editSet(int index) {
    FocusScope.of(context).unfocus();
    setState(() {
      if (_editing == null) {
        _draft = (_kg.text, _reps.text, _effort, _isWarmup);
      }
      _editing = index;
      _announcement = null;
      _fill(widget.entry.sets[index], editing: true);
    });
    if (_pageScroll.hasClients) {
      _pageScroll.animateTo(0,
          duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    }
  }

  void _cancelEdit() {
    FocusScope.of(context).unfocus();
    setState(() {
      _editing = null;
      _kg.text = _draft?.$1 ?? '';
      _reps.text = _draft?.$2 ?? '';
      _effort = _draft?.$3;
      _isWarmup = _draft?.$4 ?? false;
      _draft = null;
      _kgError = null;
      _repsError = null;
    });
  }

  Future<void> _setContext() async {
    FocusScope.of(context).unfocus();
    var effort = _effort;
    var warmup = _isWarmup;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(builder: (context, setSheetState) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('How did this set feel?',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                const Text('Optional. Rate each set separately.'),
                const SizedBox(height: 12),
                RadioGroup<SetEffort>(
                  groupValue: effort,
                  onChanged: (value) => setSheetState(() => effort = value),
                  child: Column(children: [
                    for (final value in SetEffort.values)
                      RadioListTile<SetEffort>(
                        contentPadding: EdgeInsets.zero,
                        title: Text(value.label),
                        value: value,
                        toggleable: true,
                      ),
                  ]),
                ),
                TextButton(
                  onPressed: () => setSheetState(() => effort = null),
                  child: const Text('Unsure / skip effort rating'),
                ),
                const Divider(),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Warm-up set'),
                  subtitle: Text(warmup == null
                      ? 'This older set has no type recorded. Choose a type to label it.'
                      : 'Warm-ups do not count toward working-set targets.'),
                  value: warmup == true,
                  onChanged: (value) => setSheetState(() => warmup = value),
                ),
                if (warmup == null)
                  TextButton(
                    onPressed: () => setSheetState(() => warmup = false),
                    child: const Text('Mark as working set'),
                  ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Use for this set'),
                ),
              ],
            ),
          ),
        );
      }),
    );
    if (saved == true && mounted) {
      setState(() {
        _effort = effort;
        _isWarmup = warmup;
      });
    }
  }

  Future<void> _editTarget() async {
    final target = await showDialog<ExerciseTarget>(
      context: context,
      builder: (_) => _TargetEditor(target: widget.entry.target),
    );
    if (target != null && mounted) store.updateTarget(widget.entry, target);
  }

  void _deleteSet(int index) {
    if (_editing == index) {
      _cancelEdit();
    } else if (_editing != null && _editing! > index) {
      setState(() => _editing = _editing! - 1);
    }
    store.removeSet(widget.entry, index);
    setState(() => _announcement = 'Set removed');
  }

  Future<void> _removeExercise() async {
    final count = widget.entry.sets.length;
    if (count > 0) {
      final remove = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Remove exercise?'),
          content: Text(
              'This removes the exercise and its $count logged ${count == 1 ? 'set' : 'sets'} from this workout.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Remove')),
          ],
        ),
      );
      if (remove != true || !mounted) return;
    }
    store.removeExercise(widget.workout, widget.entry);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final def = store.exercise(widget.entry.exerciseId);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final sets = widget.entry.sets;
        final number = (_editing ?? sets.length) + 1;
        final target = widget.entry.target;
        final suggestion = nextSessionSuggestion(widget.entry,
            energy: widget.workout.energy,
            hasPain: _hasPain,
            daysSincePrevious: _gap);
        final previousSets = _previous?.sets ?? <WorkSet>[];
        final previous = number <= previousSets.length
            ? previousSets[number - 1]
            : previousSets.lastOrNull;
        return Scaffold(
          appBar: AppBar(
            title: Tooltip(
                message: def.name,
                child: Text(def.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done')),
              PopupMenuButton<String>(
                tooltip: 'Exercise options',
                onSelected: (_) => _removeExercise(),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'remove', child: Text('Remove exercise'))
                ],
              ),
            ],
          ),
          body: SafeArea(
            top: false,
            child: LayoutBuilder(builder: (context, constraints) {
              final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
              final compact = constraints.maxHeight < 500 * textScale;
              final editor = Padding(
                padding: EdgeInsets.fromLTRB(16, compact ? 4 : 16, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!compact) ...[
                      Align(
                          alignment: Alignment.centerLeft,
                          child: Pill(
                            leading: Icon(def.icon),
                            label: def.muscle.label,
                            color: def.muscle.color,
                          )),
                      const SizedBox(height: 12),
                    ],
                    Card(
                      child: Padding(
                        padding: EdgeInsets.all(compact ? 12 : 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(children: [
                              Expanded(
                                  child: Text(
                                _editing == null
                                    ? 'Set $number'
                                    : 'Edit set $number',
                                style: theme.textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              )),
                              if (_editing != null)
                                TextButton(
                                    onPressed: _cancelEdit,
                                    child: const Text('Cancel'))
                              else
                                Icon(Icons.fitness_center,
                                    size: 20, color: scheme.primary),
                            ]),
                            if (previous != null && !compact) ...[
                              const SizedBox(height: 4),
                              Text(
                                  'Last time (${fmtDate(_previousWorkout!.start)}): ${fmtKg(previous.kg)} kg × ${previous.reps} reps',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant)),
                            ],
                            SizedBox(height: compact ? 12 : 20),
                            Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                      child: _SetInput(
                                    fieldKey: const ValueKey('set-weight'),
                                    controller: _kg,
                                    label: 'Weight (kg)',
                                    decimal: true,
                                    error: _kgError,
                                    onSubmitted: (_) =>
                                        _repsFocus.requestFocus(),
                                  )),
                                  const SizedBox(width: 12),
                                  Expanded(
                                      child: _SetInput(
                                    fieldKey: const ValueKey('set-reps'),
                                    controller: _reps,
                                    focusNode: _repsFocus,
                                    label: 'Reps',
                                    error: _repsError,
                                    onSubmitted: (_) => _saveSet(),
                                  )),
                                ]),
                            TextButton.icon(
                              key: const ValueKey('set-context'),
                              onPressed: _setContext,
                              icon: const Icon(Icons.tune_rounded, size: 18),
                              label: Text([
                                if (_isWarmup == true) 'Warm-up',
                                _effort?.label ?? 'Add effort (optional)',
                              ].join(' · ')),
                            ),
                            const SizedBox(height: 4),
                            FilledButton.icon(
                              key: const ValueKey('save-set'),
                              onPressed: _saveSet,
                              icon: const Icon(Icons.check_rounded),
                              label: Text(_editing == null
                                  ? 'Log set'
                                  : 'Save changes'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                            _announcement ?? 'Sets are saved as you log them.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant)),
                      ),
                    ),
                  ],
                ),
              );
              final history = <Widget>[
                if (target != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Planned working sets',
                              style: theme.textTheme.titleSmall),
                          const SizedBox(height: 6),
                          Text(
                              '${target.sets} sets · ${target.repsMin}–${target.repsMax} reps'
                              '${target.loadKg == null ? '' : ' · ${fmtKg(target.loadKg!)} kg suggested'}'),
                          const SizedBox(height: 4),
                          Text(
                              'Rest about ${target.restSeconds} seconds. ${target.reason}',
                              style: theme.textTheme.bodySmall),
                          const SizedBox(height: 4),
                          Text(
                              '${sets.where((set) => set.isWarmup == false).length} working sets logged',
                              style: theme.textTheme.bodySmall),
                          if (widget.workout.isActive)
                            TextButton(
                              key: const ValueKey('edit-target'),
                              onPressed: _editTarget,
                              child: const Text('Adjust target'),
                            ),
                        ],
                      ),
                    ),
                  ),
                if (target == null && widget.workout.isActive)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const ValueKey('edit-target'),
                      onPressed: _editTarget,
                      icon: const Icon(Icons.flag_outlined),
                      label: const Text('Set a working-set target'),
                    ),
                  ),
                if ((_gap ?? 0) >= returnAfterBreakDays && sets.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                        'Your last logged session of this exercise was a while ago. Choose a comfortable starting load today; your old load is shown only as a reference.'),
                  ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(children: [
                    Expanded(
                        child: Text('Logged sets',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700))),
                    Text('${sets.length}',
                        style: theme.textTheme.labelLarge
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                  ]),
                ),
                if (sets.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text('Tap a set to edit it.',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                  ),
                if (sets.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 24, horizontal: 16),
                    child: Text(
                        'Your first set starts above.\nUse 0 kg for an unweighted set.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                  )
                else
                  Card(
                      clipBehavior: Clip.antiAlias,
                      child: Column(children: [
                        for (var i = 0; i < sets.length; i++) ...[
                          if (i > 0) const Divider(indent: 16, endIndent: 16),
                          ListTile(
                            key: ValueKey('logged-set-$i'),
                            selected: _editing == i,
                            selectedTileColor:
                                scheme.primary.withValues(alpha: 0.08),
                            leading: CircleAvatar(
                              radius: 16,
                              backgroundColor:
                                  scheme.primary.withValues(alpha: 0.1),
                              child: Text('${i + 1}',
                                  style: theme.textTheme.labelMedium
                                      ?.copyWith(color: scheme.primary)),
                            ),
                            title: Text(
                                '${fmtKg(sets[i].kg)} kg × ${sets[i].reps} reps'),
                            subtitle: Text([
                              if (sets[i].isWarmup == true)
                                'Warm-up'
                              else if (sets[i].isWarmup == false)
                                'Working set'
                              else
                                'Set type not recorded',
                              sets[i].effort?.label ?? 'Effort not recorded',
                            ].join(' · ')),
                            onTap: () => _editSet(i),
                            trailing: IconButton(
                              tooltip: 'Delete set ${i + 1}',
                              onPressed: () => _deleteSet(i),
                              icon: const Icon(Icons.remove_circle_outline,
                                  size: 21),
                            ),
                          ),
                        ],
                      ])),
                if (sets.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('For next time · ${suggestion.title}',
                            style: theme.textTheme.titleSmall),
                        const SizedBox(height: 4),
                        Text(suggestion.reason,
                            style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
              ];
              // Very short screens scroll the whole page so both the editor
              // and saved sets remain accessible in landscape or large text.
              if (constraints.maxHeight < 340 * textScale) {
                return SingleChildScrollView(
                  controller: _pageScroll,
                  child: Column(children: [
                    editor,
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: history),
                    ),
                  ]),
                );
              }
              return Column(children: [
                editor,
                Expanded(
                    child: ListView(
                  key: const PageStorageKey('logged-sets'),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  children: history,
                )),
              ]);
            }),
          ),
        );
      },
    );
  }
}

class _TargetEditor extends StatefulWidget {
  const _TargetEditor({this.target});

  final ExerciseTarget? target;

  @override
  State<_TargetEditor> createState() => _TargetEditorState();
}

class _TargetEditorState extends State<_TargetEditor> {
  final _form = GlobalKey<FormState>();
  late final _sets = TextEditingController(text: '${widget.target?.sets ?? 2}');
  late final _min =
      TextEditingController(text: '${widget.target?.repsMin ?? 8}');
  late final _max =
      TextEditingController(text: '${widget.target?.repsMax ?? 12}');
  late final _load = TextEditingController(
      text: widget.target?.loadKg == null
          ? ''
          : fmtKg(widget.target!.loadKg!).replaceAll(',', ''));
  late final _rest =
      TextEditingController(text: '${widget.target?.restSeconds ?? 90}');

  @override
  void dispose() {
    for (final controller in [_sets, _min, _max, _load, _rest]) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _integer(String? raw, int min, int max) {
    final value = int.tryParse(raw?.trim() ?? '');
    return value == null || value < min || value > max
        ? 'Choose $min–$max'
        : null;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Working-set target'),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Form(
              key: _form,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text(
                    'Adjust the plan to suit today. Your logged sets stay as they are.'),
                const SizedBox(height: 16),
                TextFormField(
                  key: const ValueKey('target-sets'),
                  controller: _sets,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Working sets'),
                  validator: (value) => _integer(value, 1, 10),
                ),
                const SizedBox(height: 12),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                      child: TextFormField(
                    controller: _min,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Min reps'),
                    validator: (value) => _integer(value, 1, 50),
                  )),
                  const SizedBox(width: 12),
                  Expanded(
                      child: TextFormField(
                    controller: _max,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Max reps'),
                    validator: (value) => _integer(
                        value, int.tryParse(_min.text.trim()) ?? 1, 50),
                  )),
                ]),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _load,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Suggested kg (optional)'),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return null;
                    final kg = parseKg(value);
                    return kg == null || !kg.isFinite || kg < 0 || kg > 1000
                        ? 'Enter a valid weight or leave blank'
                        : null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _rest,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: 'Rest (seconds)'),
                  validator: (value) => _integer(value, 15, 600),
                ),
              ]),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (!_form.currentState!.validate()) return;
              Navigator.pop(
                  context,
                  ExerciseTarget(
                    sets: int.parse(_sets.text.trim()),
                    repsMin: int.parse(_min.text.trim()),
                    repsMax: int.parse(_max.text.trim()),
                    loadKg:
                        _load.text.trim().isEmpty ? null : parseKg(_load.text),
                    restSeconds: int.parse(_rest.text.trim()),
                    reason: 'Adjusted by you for this session.',
                  ));
            },
            child: const Text('Save target'),
          ),
        ],
      );
}

class _SetInput extends StatelessWidget {
  const _SetInput(
      {required this.fieldKey,
      required this.controller,
      required this.label,
      required this.onSubmitted,
      this.decimal = false,
      this.error,
      this.focusNode});

  final Key fieldKey;
  final TextEditingController controller;
  final String label;
  final bool decimal;
  final String? error;
  final FocusNode? focusNode;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) => TextField(
        key: fieldKey,
        controller: controller,
        focusNode: focusNode,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        textInputAction: decimal ? TextInputAction.next : TextInputAction.done,
        inputFormatters: [
          FilteringTextInputFormatter.allow(
              RegExp(decimal ? r'[0-9.,]' : r'[0-9]'))
        ],
        style: Theme.of(context)
            .textTheme
            .headlineSmall
            ?.copyWith(fontWeight: FontWeight.w600),
        onSubmitted: onSubmitted,
        onTapOutside: (_) => FocusScope.of(context).unfocus(),
        decoration: InputDecoration(
            labelText: label,
            floatingLabelBehavior: FloatingLabelBehavior.always,
            hintText: '0',
            errorText: error,
            errorMaxLines: 2),
      );
}
