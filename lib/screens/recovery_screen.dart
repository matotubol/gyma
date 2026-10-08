import 'package:flutter/material.dart';
import '../recovery.dart';
import '../store.dart';

class RecoveryScreen extends StatefulWidget {
  const RecoveryScreen({super.key, this.date});
  final DateTime? date;
  @override
  State<RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends State<RecoveryScreen> {
  late DateTime _date;
  final _notes = TextEditingController();
  Map<BodyArea, Soreness> _muscles = {};
  Set<BodyArea> _pain = {};
  bool _dirty = false;
  @override
  void initState() {
    super.initState();
    _load(widget.date ?? DateTime.now());
  }

  void _load(DateTime date) {
    _date = date;
    final day = store.recoveryDays[dayKey(date)];
    _muscles = Map.of(day?.muscles ?? {});
    _pain = Set.of(day?.painAreas ?? {});
    _notes.text = day?.notes ?? '';
    _dirty = false;
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<bool> _canLeave() async {
    if (!_dirty) return true;
    return await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
                  title: const Text('Discard unsaved changes?'),
                  content: const Text(
                      'Save this day first if you want to keep your changes.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Keep editing')),
                    TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Discard'))
                  ],
                )) ??
        false;
  }

  Future<void> _pickDate() async {
    if (!await _canLeave() || !mounted) return;
    final date = await showDatePicker(
        context: context,
        initialDate: _date,
        firstDate: DateTime(2000),
        lastDate: DateTime.now());
    if (date != null && mounted) setState(() => _load(date));
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_dirty,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          if (await _canLeave() && context.mounted) {
            setState(() => _dirty = false);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) Navigator.pop(context);
            });
          }
        },
        child: Scaffold(
          appBar: AppBar(title: const Text('Daily soreness'), actions: [
            TextButton(
                onPressed: () {
                  store.saveRecovery(RecoveryDay(
                      day: dayKey(_date),
                      muscles: _muscles,
                      painAreas: _pain,
                      notes: _notes.text.trim()));
                  setState(() => _dirty = false);
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Daily check-in saved')));
                },
                child: const Text('Save')),
          ]),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today),
                label: Text(dayKey(_date))),
            const SizedBox(height: 12),
            Text('How do your muscles feel?',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text(
                'Optional, including rest days. Tap a level to record it; tap again to clear. Unrecorded muscles stay unknown.'),
            const SizedBox(height: 8),
            const Text(
                'Soreness (spierpijn) is context, not a measure of muscle growth. Flag sharp, joint or unusual pain separately.'),
            const SizedBox(height: 12),
            for (final area in BodyArea.values)
              Card(
                  child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Expanded(
                                  child: Text(area.label,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium)),
                              if (!_muscles.containsKey(area))
                                const Text('Not recorded',
                                    style: TextStyle(fontSize: 12))
                            ]),
                            Wrap(spacing: 6, children: [
                              for (final level in Soreness.values)
                                ChoiceChip(
                                    label: Text(level.label),
                                    selected: _muscles[area] == level,
                                    onSelected: (selected) => setState(() {
                                          if (selected) {
                                            _muscles[area] = level;
                                          } else {
                                            _muscles.remove(area);
                                          }
                                          _dirty = true;
                                        }))
                            ]),
                            CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                title: const Text(
                                    'Pain different from ordinary soreness'),
                                value: _pain.contains(area),
                                onChanged: (value) => setState(() {
                                      if (value == true) {
                                        _pain.add(area);
                                      } else {
                                        _pain.remove(area);
                                      }
                                      _dirty = true;
                                    })),
                          ]))),
            TextField(
                controller: _notes,
                maxLength: 1000,
                minLines: 2,
                maxLines: 4,
                onChanged: (_) => setState(() => _dirty = true),
                decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    hintText: 'For example: stairs felt harder today')),
            const SizedBox(height: 24),
          ]),
        ),
      );
}

class RecoveryCard extends StatelessWidget {
  const RecoveryCard({super.key});
  @override
  Widget build(BuildContext context) {
    final day = store.recoveryDays[dayKey(DateTime.now())];
    final recorded = day?.muscles.length ?? 0;
    final sore =
        day?.muscles.entries.where((e) => e.value != Soreness.none).toList() ??
            [];
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Today’s recovery',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(recorded == 0
                  ? 'Muscle soreness not recorded today.'
                  : '$recorded of ${BodyArea.values.length} muscle groups recorded'),
              if (sore.isNotEmpty)
                Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(spacing: 6, runSpacing: 4, children: [
                      for (final e in sore)
                        Chip(label: Text('${e.key.label}: ${e.value.label}'))
                    ])),
              if (day != null && day.painAreas.isNotEmpty)
                Text(
                    'Pain flagged: ${day.painAreas.map((a) => a.label).join(', ')}. Tell your coach before planning.'),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                          builder: (_) => const RecoveryScreen())),
                  icon: const Icon(Icons.accessibility_new),
                  label: Text(day == null
                      ? 'Log soreness (optional)'
                      : 'Edit daily check-in')),
            ])));
  }
}
