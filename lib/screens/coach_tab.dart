import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../analytics.dart';
import '../models.dart';
import '../recovery.dart';
import '../store.dart';
import 'active_workout_screen.dart';
import 'api_key_screen.dart';
import 'coach_widgets.dart';
import 'session_prepare_screen.dart';

class CoachTab extends StatefulWidget {
  const CoachTab({super.key, this.initialQuestion});
  final String? initialQuestion;

  @override
  State<CoachTab> createState() => _CoachTabState();
}

class _CoachTabState extends State<CoachTab> {
  late final _question = TextEditingController(text: widget.initialQuestion);
  late final _goal = TextEditingController(text: store.trainingProfile['goal']);
  late final _schedule =
      TextEditingController(text: store.trainingProfile['schedule']);
  late final _equipment =
      TextEditingController(text: store.trainingProfile['equipment']);
  late final _experience =
      TextEditingController(text: store.trainingProfile['experience']);
  late final _constraints =
      TextEditingController(text: store.trainingProfile['constraints']);
  final _scroll = ScrollController();
  bool _busy = false;
  String? _error;
  late Map<String, String> _storedProfile;
  late int _restoreGeneration;

  @override
  void initState() {
    super.initState();
    _storedProfile = _normalizedProfile(store.trainingProfile);
    _restoreGeneration = store.restoreGeneration;
    store.addListener(_syncProfile);
  }

  Map<String, TextEditingController> get _profileControllers => {
        'goal': _goal,
        'schedule': _schedule,
        'equipment': _equipment,
        'experience': _experience,
        'constraints': _constraints,
      };

  Map<String, String> _normalizedProfile(Map<String, String> profile) => {
        for (final key in [
          'goal',
          'schedule',
          'equipment',
          'experience',
          'constraints'
        ])
          key: profile[key] ?? '',
      };

  Map<String, String> get _profileValues => {
        for (final entry in _profileControllers.entries)
          entry.key: entry.value.text.trim(),
      };

  void _syncProfile() {
    final restored = _restoreGeneration != store.restoreGeneration;
    final next = _normalizedProfile(store.trainingProfile);
    if (restored ||
        (!mapEquals(next, _storedProfile) &&
            mapEquals(_profileValues, _storedProfile))) {
      for (final entry in _profileControllers.entries) {
        entry.value.text = next[entry.key]!;
      }
      if (mounted) setState(() {});
    }
    _storedProfile = next;
    _restoreGeneration = store.restoreGeneration;
  }

  @override
  void dispose() {
    store.removeListener(_syncProfile);
    for (final controller in [
      _question,
      _goal,
      _schedule,
      _equipment,
      _experience,
      _constraints
    ]) {
      controller.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  void _saveProfile() => store.saveProfile({
        'goal': _goal.text.trim(),
        'schedule': _schedule.text.trim(),
        'equipment': _equipment.text.trim(),
        'experience': _experience.text.trim(),
        'constraints': _constraints.text.trim(),
      });

  Future<void> _ask() async {
    final question = _question.text.trim();
    if (_busy) return;
    if (question.isEmpty) {
      setState(() => _error = 'Tell your coach what you want to work on.');
      return;
    }
    _saveProfile();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final exchange = await requestCoachReply(context, question: question);
      if (!mounted || exchange == null) return;
      if (exchange.sourceRevision != store.revision ||
          exchange.sourceDay != dayKey(DateTime.now())) {
        setState(() => _error =
            'Your training data changed while your coach was replying. Send again to use your current history.');
        return;
      }
      final saved = store.saveCoachExchange(question, exchange.reply,
          sourceRevision: exchange.sourceRevision,
          sourceDay: exchange.sourceDay);
      if (!saved) {
        setState(() => _error =
            'Training data changed while your coach was replying. Ask again to use your current history.');
        return;
      }
      setState(() => _question.clear());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut);
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = coachError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _prepare([Map<String, dynamic>? session]) async {
    if (_busy || store.activeWorkout != null) return;
    _saveProfile();
    final draft = store.coachDraft;
    final workout = await Navigator.push<Workout>(
        context,
        MaterialPageRoute(
          builder: (_) => SessionPrepareScreen(
            initialReply: session == null || draft == null
                ? null
                : {
                    ...draft,
                    'plan': [session]
                  },
            initialSourceRevision: store.coachDraftRevision,
            initialSourceDay: store.coachDraftDay,
          ),
        ));
    if (!mounted || workout == null) return;
    await Navigator.push(
        context,
        MaterialPageRoute<void>(
            builder: (_) => ActiveWorkoutScreen(workout: workout)));
  }

  Future<void> _preview() async {
    _saveProfile();
    final json = const JsonEncoder.withIndent('  ').convert({
      'trainingContext': trainingContext(store, DateTime.now()),
      'conversation': store.coachConversation,
    });
    await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Data sent to your coach'),
              content: SizedBox(
                  width: 600,
                  child: SingleChildScrollView(child: SelectableText(json))),
              actions: [
                TextButton(
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: json)),
                    child: const Text('Copy')),
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close')),
              ],
            ));
  }

  Future<void> _reviewActivePlan(Map<String, dynamic> session) async {
    final workout = store.activeWorkout;
    final sourceRevision = store.coachDraftRevision;
    final sourceDay = store.coachDraftDay;
    if (_busy ||
        workout == null ||
        sourceRevision == null ||
        sourceDay == null) {
      return;
    }
    if (sourceRevision != store.revision ||
        sourceDay != dayKey(DateTime.now())) {
      setState(() => _error =
          'Ask your coach for an updated plan before applying changes.');
      return;
    }
    final plan = <WorkoutExercise>[
      for (final item in session['exercises'] as List)
        WorkoutExercise(item['exerciseId'] as String)
          ..target =
              ExerciseTarget.fromJson(Map<String, dynamic>.from(item as Map)),
    ];
    final ids = plan.map((e) => e.exerciseId).toSet();
    final omitted =
        workout.exercises.where((e) => !ids.contains(e.exerciseId)).toList();
    final apply = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Review workout changes'),
              content: SizedBox(
                  width: 560,
                  child: SingleChildScrollView(
                      child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                          'Your logged sets stay exactly as recorded. Targets count working sets across this session; warm-ups are excluded. Unlabelled sets are shown separately.'),
                      for (final exercise in plan)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(_workingSetProgress(workout, exercise)),
                        ),
                      for (final exercise in omitted)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(exercise.sets.isEmpty
                              ? '${store.exercise(exercise.exerciseId).name}: remove this unstarted exercise.'
                              : '${store.exercise(exercise.exerciseId).name}: keep ${exercise.sets.length} logged sets; remove its remaining target.'),
                        ),
                      CoachDraftCard(reply: {
                        'plan': [session],
                        'rationale': <String>[],
                        'limitations': <String>[],
                        'evidenceWorkoutIds': <String>[],
                      }, activeSession: true),
                    ],
                  ))),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Keep current plan')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Apply to this workout')),
              ],
            ));
    if (!mounted || apply != true) return;
    try {
      store.applyPlanToActiveWorkout(workout, plan,
          planTitle: session['title'] as String,
          sourceRevision: sourceRevision,
          sourceDay: sourceDay);
      setState(() => _error = null);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Workout targets updated. Your logged sets are preserved.')));
    } catch (_) {
      setState(() => _error =
          'Your workout changed while you were reviewing. Ask your coach to refresh the plan.');
    }
  }

  String _workingSetProgress(Workout workout, WorkoutExercise planned) {
    final sets = workout.exercises
        .where((e) => e.exerciseId == planned.exerciseId)
        .expand((e) => e.sets)
        .toList();
    final working = sets.where((s) => s.isWarmup == false).length;
    final unknown = sets.where((s) => s.isWarmup == null).length;
    final progress =
        '${store.exercise(planned.exerciseId).name}: $working working ${working == 1 ? 'set' : 'sets'} logged → ${planned.target!.sets} total target';
    return unknown == 0
        ? progress
        : '$progress\n$unknown unlabelled ${unknown == 1 ? 'set' : 'sets'}; confirm ${unknown == 1 ? 'its' : 'their'} type before counting ${unknown == 1 ? 'it' : 'them'}.';
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final reply = store.coachDraft;
          final theme = Theme.of(context);
          return ListView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            children: [
              Text('Your coach', style: theme.textTheme.headlineMedium),
              const SizedBox(height: 8),
              const Text(
                  'Make a plan, talk through a difficult day, or decide your next small step. Your conversation stays here between sessions.'),
              const SizedBox(height: 16),
              if (store.activeWorkout == null)
                FilledButton.icon(
                    onPressed: _busy ? null : _prepare,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Check in & plan today')),
              if (store.activeWorkout != null)
                OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                            builder: (_) => ActiveWorkoutScreen(
                                workout: store.activeWorkout!))),
                    icon: const Icon(Icons.fitness_center),
                    label: const Text('Return to your workout')),
              const SizedBox(height: 12),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Your goals & preferences'),
                subtitle: Text(
                    _goal.text.isEmpty
                        ? 'Give your coach a starting point'
                        : _goal.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                initiallyExpanded: store.trainingProfile.isEmpty,
                children: [
                  _field(_goal, 'What does better shape mean to you?',
                      'Build muscle, get leaner, or both…'),
                  _field(_schedule, 'Days and time available',
                      '3 days a week, 45 minutes'),
                  _field(_equipment, 'Equipment you have',
                      'Gym machines, dumbbells, home gym…'),
                  _field(_experience, 'Training experience',
                      'Beginner, returning after a break…'),
                  _field(_constraints, 'Preferences and limitations',
                      'Exercises you enjoy, want to avoid, or need help with'),
                  TextButton(
                      onPressed: () {
                        _saveProfile();
                        setState(() {});
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Preferences saved')));
                      },
                      child: const Text('Save preferences')),
                ],
              ),
              if (store.coachConversation.isEmpty)
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Text('Start with what matters today.',
                        style: theme.textTheme.titleMedium)),
              const CoachConversation(),
              if (reply != null)
                CoachDraftCard(
                    reply: reply,
                    activeSession: store.activeWorkout != null,
                    stale: store.coachDraftRevision != store.revision ||
                        store.coachDraftDay != dayKey(DateTime.now()),
                    startLabel: store.activeWorkout == null
                        ? 'Prepare this session'
                        : 'Review workout changes',
                    onStart: _busy
                        ? null
                        : store.activeWorkout == null
                            ? _prepare
                            : _reviewActivePlan),
              const SizedBox(height: 16),
              Wrap(spacing: 8, runSpacing: 6, children: [
                _prompt('Coming back',
                    'I’m coming back after a break. Help me figure out a manageable starting point, and ask how I’m feeling before suggesting a session.'),
                _prompt('Review my week',
                    'Review my last week of training in the context of my goals. What went well, what is missing, and what should I focus on next week?'),
                _prompt('My next increase',
                    'Look at my recent sets and effort. What should I aim for next time, and what information do you still need before suggesting a weight or rep increase?'),
              ]),
              const SizedBox(height: 12),
              TextField(
                  controller: _question,
                  minLines: 2,
                  maxLines: 6,
                  maxLength: 2000,
                  decoration: InputDecoration(
                      filled: true,
                      fillColor: theme.colorScheme.surface,
                      labelText: 'Talk to your coach',
                      hintText:
                          'How you feel, what is getting in the way, or what to change…')),
              FilledButton.icon(
                  onPressed: _busy ? null : _ask,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.arrow_upward_rounded),
                  label:
                      Text(_busy ? 'Thinking it through…' : 'Send to coach')),
              if (_error != null)
                Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(_error!,
                        style: TextStyle(color: theme.colorScheme.error))),
              const SizedBox(height: 16),
              Wrap(alignment: WrapAlignment.center, children: [
                TextButton.icon(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                            builder: (_) => const ApiKeyScreen())),
                    icon: const Icon(Icons.key, size: 18),
                    label: const Text('OpenAI settings')),
                TextButton(
                    onPressed: _preview,
                    child: const Text('Preview shared data')),
                if (store.coachConversation.isNotEmpty)
                  TextButton(
                      onPressed: _busy
                          ? null
                          : () {
                              store.clearCoachConversation();
                              setState(() => _error = null);
                            },
                      child: const Text('Clear conversation')),
              ]),
            ],
          );
        },
      );

  Widget _prompt(String label, String question) => ActionChip(
      label: Text(label),
      onPressed:
          _busy ? null : () => setState(() => _question.text = question));

  Widget _field(TextEditingController controller, String label, String hint) =>
      Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: TextField(
              controller: controller,
              maxLength: 500,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surface,
                  labelText: label,
                  hintText: hint,
                  counterText: '')));
}
