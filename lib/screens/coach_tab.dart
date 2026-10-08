import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../analytics.dart';
import '../coach_client.dart';
import '../api_key_store.dart';
import '../store.dart';
import '../recovery.dart';
import '../format.dart';
import 'workout_detail_screen.dart';
import 'api_key_screen.dart';

class CoachTab extends StatefulWidget {
  const CoachTab({super.key});
  @override
  State<CoachTab> createState() => _CoachTabState();
}

class _CoachTabState extends State<CoachTab> {
  final _conversation = <Map<String, String>>[];
  final _question = TextEditingController(
      text:
          'Help me design my next training session using my progress and daily muscle soreness.');
  late final _goal = TextEditingController(text: store.trainingProfile['goal']);
  late final _schedule =
      TextEditingController(text: store.trainingProfile['schedule']);
  late final _equipment =
      TextEditingController(text: store.trainingProfile['equipment']);
  late final _experience =
      TextEditingController(text: store.trainingProfile['experience']);
  late final _constraints =
      TextEditingController(text: store.trainingProfile['constraints']);
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _reply;
  int? _sourceRevision;
  String? _sourceDay;
  @override
  void dispose() {
    for (final c in [
      _question,
      _goal,
      _schedule,
      _equipment,
      _experience,
      _constraints
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _saveProfile() => store.saveProfile({
        'goal': _goal.text.trim(),
        'schedule': _schedule.text.trim(),
        'equipment': _equipment.text.trim(),
        'experience': _experience.text.trim(),
        'constraints': _constraints.text.trim()
      });

  Future<void> _ask() async {
    if (_question.text.trim().isEmpty) {
      setState(() => _error = 'Enter a question for your coach.');
      return;
    }
    String? apiKey;
    try { apiKey = await ApiKeyStore().read(); } catch (_) {
      if (mounted) setState(() => _error = 'Could not read your API key. Unlock your device and check Settings.');
      return;
    }
    if (!mounted) return;
    if (apiKey == null || apiKey.isEmpty) {
      await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const ApiKeyScreen()));
      return;
    }
    _saveProfile();
    final contextData = trainingContext(store, DateTime.now());
    final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Send training context?'),
              content: Text(
                  'Send your question, recent conversation, profile, last 28 days of workouts, soreness and pain notes directly to OpenAI. Deleted workouts and edit history are excluded.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Send'))
              ],
            ));
    if (ok != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final reply = await CoachClient().ask(
          apiKey: apiKey,
          question: _question.text.trim(),
          context: contextData, conversation: List.of(_conversation));
      if (mounted) {
        setState(() {
          _conversation.addAll([{'role': 'user', 'content': _question.text.trim()},
            {'role': 'assistant', 'content': jsonEncode(reply)}]);
          while (_conversation.length > 6) { _conversation.removeRange(0, 2); }
          _reply = reply;
          _sourceRevision = contextData['dataRevision'] as int;
          _sourceDay = contextData['localToday'] as String;
        });
      }
    } on HttpException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Could not get a complete coaching reply. Check your internet connection and API key in Settings, then try again. Your workout data is still on this device.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final reply = _reply;
        final today = dayKey(DateTime.now());
        return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            children: [
              Text('Train with context',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              const Text(
                  'Ask about your progress or draft a routine. Soreness helps explain your day; it cannot prove which routine is best for your body.'),
              ExpansionTile(
                  title: const Text('Your training preferences'),
                  initiallyExpanded: store.trainingProfile.isEmpty,
                  children: [
                    _field(
                        _goal, 'Goal', 'Strength, muscle growth, consistency…'),
                    _field(_schedule, 'Days and time available',
                        '3 days per week, 45 minutes'),
                    _field(_equipment, 'Equipment',
                        'Gym machines, barbell, dumbbells…'),
                    _field(_experience, 'Training experience',
                        'Beginner, returning, years training…'),
                    _field(_constraints, 'Preferences and limitations',
                        'Exercises you enjoy or need to avoid'),
                    TextButton(
                        onPressed: () {
                          _saveProfile();
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Preferences saved')));
                        },
                        child: const Text('Save preferences')),
                  ]),
              TextButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const ApiKeyScreen())),
                icon: const Icon(Icons.key), label: const Text('OpenAI settings')),
              TextButton.icon(
                  onPressed: () async {
                    _saveProfile();
                    final json = const JsonEncoder.withIndent('  ')
                        .convert(trainingContext(store, DateTime.now()));
                    await showDialog<void>(
                        context: context,
                        builder: (context) => AlertDialog(
                                title: const Text('AI context preview'),
                                content: SizedBox(
                                    width: 600,
                                    child: SingleChildScrollView(
                                        child: SelectableText(json))),
                                actions: [
                                  TextButton(
                                      onPressed: () {
                                        Clipboard.setData(
                                            ClipboardData(text: json));
                                      },
                                      child: const Text('Copy JSON')),
                                  TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('Close'))
                                ]));
                  },
                  icon: const Icon(Icons.data_object),
                  label: const Text('Preview data sent to AI')),
              TextField(
                  controller: _question,
                  minLines: 2,
                  maxLines: 5,
                  maxLength: 2000,
                  decoration:
                      const InputDecoration(labelText: 'Ask your coach')),
              FilledButton.icon(
                  onPressed: _busy ? null : _ask,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.auto_awesome),
                  label: Text(_busy ? 'Reviewing your data…' : 'Ask coach')),
              if (_error != null)
                Padding(
                    padding: const EdgeInsets.all(12), child: Text(_error!)),
              if (_conversation.isNotEmpty) TextButton(onPressed: _busy ? null : () => setState(() {
                _conversation.clear(); _reply = null; _error = null;
              }), child: const Text('Start a new conversation')),
              if (reply != null)
                Card(
                    child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_sourceRevision != store.revision ||
                                  _sourceDay != today)
                                const Text(
                                    'OUTDATED: your data or the day has changed. Ask again before using this draft.',
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold)),
                              Text('Coach’s draft',
                                  style:
                                      Theme.of(context).textTheme.titleLarge),
                              const Text(
                                  'Review and adjust before training. Nothing is added to your workout history.'),
                              const SizedBox(height: 12),
                              SelectableText(reply['answer'] as String? ?? ''),
                              for (final reason
                                  in reply['rationale'] as List? ?? [])
                                Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text('• $reason')),
                              for (final session
                                  in reply['plan'] as List? ?? []) ...[
                                const SizedBox(height: 16),
                                Text(session['title'] as String,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium),
                                for (final e in session['exercises'] as List)
                                  ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(store
                                          .exercise(e['exerciseId'] as String)
                                          .name),
                                      subtitle: Text(
                                          '${e['sets']} sets × ${e['reps']} reps · ${e['loadKg'] == null ? 'choose a comfortable load' : '${e['loadKg']} kg'}\n${e['reason']}')),
                              ],
                              const SizedBox(height: 12),
                              Text('Sessions used', style: Theme.of(context).textTheme.titleSmall),
                              if ((reply['evidenceWorkoutIds'] as List? ?? []).isEmpty)
                                const Text('No previous sessions cited.'),
                              for (final w in store.finishedWorkouts.where((w) => (reply['evidenceWorkoutIds'] as List? ?? []).contains(w.id)))
                                TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => WorkoutDetailScreen(workout: w))),
                                  child: Text(fmtDate(w.start))),
                              for (final note
                                  in reply['limitations'] as List? ?? [])
                                Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text('$note')),
                            ]))),
            ]);
      });
  Widget _field(TextEditingController controller, String label, String hint) =>
      Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: TextField(
              controller: controller,
              maxLength: 500,
              decoration: InputDecoration(labelText: label, hintText: hint)));
}
