import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../format.dart';
import '../store.dart';
import 'api_key_screen.dart';

class DataScreen extends StatelessWidget {
  const DataScreen({super.key});
  Future<void> _restore(BuildContext context) async {
    final input = TextEditingController();
    final text = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Restore backup'),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text(
                    'This replaces all current data. Copy a backup first. Paste a Gyma JSON backup below.'),
                TextField(
                    controller: input,
                    maxLines: 6,
                    decoration:
                        const InputDecoration(labelText: 'Backup JSON')),
              ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, input.text),
                    child: const Text('Replace and restore'))
              ],
            ));
    // Dialog exit animations may still reference its controller.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    input.dispose();
    if (text == null || !context.mounted) return;
    try {
      final data = jsonDecode(text) as Map<String, dynamic>;
      if (data['workouts'] is! List || data['version'] is! int) {
        throw const FormatException();
      }
      store.restoreBackup(data);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Backup restored')));
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Invalid or unsupported backup. Your data was not replaced.')));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: store,
      builder: (context, _) => Scaffold(
            appBar: AppBar(title: const Text('Settings')),
            body: ListView(padding: const EdgeInsets.all(16), children: [
              ListTile(
                  leading: const Icon(Icons.key_outlined),
                  title: const Text('OpenAI API key'),
                  subtitle: const Text('Add, replace or remove your saved key'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                          builder: (_) => const ApiKeyScreen()))),
              const SizedBox(height: 24),
              Text('Your data', style: Theme.of(context).textTheme.titleLarge),
              if (store.storageError != null) Text(store.storageError!),
              const Text(
                  'Workout backups include sessions, targets, effort, check-ins, daily soreness, training preferences, saved coach conversations and recent corrections. Progress photos and body measurements are stored separately and are not included. Keep backups private.'),
              FilledButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(
                        text: const JsonEncoder.withIndent('  ')
                            .convert(store.toJson())));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text(
                              'Backup copied. Paste it into a private file to keep it.')));
                    }
                  },
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy backup JSON')),
              OutlinedButton(
                  onPressed: () => _restore(context),
                  child: const Text('Restore from JSON')),
              const SizedBox(height: 24),
              Text('Deleted workouts',
                  style: Theme.of(context).textTheme.titleLarge),
              if (store.deletedWorkouts.isEmpty)
                const Text('No deleted workouts.'),
              for (final w in store.deletedWorkouts)
                ListTile(
                    title: Text(fmtDate(w.start)),
                    subtitle: Text(
                        '${w.totalSets} sets${w.isActive ? ' · unfinished' : ''}'),
                    trailing: TextButton(
                        onPressed: () {
                          try {
                            store.restoreWorkout(w);
                          } on StateError catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(e.message)));
                          }
                        },
                        child: const Text('Restore'))),
              const SizedBox(height: 24),
              Text('Recent corrections',
                  style: Theme.of(context).textTheme.titleLarge),
              const Text(
                  'The most recent 100 corrections. Expand to inspect the previous values.'),
              for (final entry in store.editHistory)
                ExpansionTile(
                    title: Text(entry['action'] as String),
                    subtitle: Text(entry['at'] as String),
                    children: [
                      Padding(
                          padding: const EdgeInsets.all(12),
                          child: SelectableText(
                              const JsonEncoder.withIndent('  ')
                                  .convert(entry['before'])))
                    ]),
            ]),
          ));
}
