import 'package:flutter/material.dart';

import '../analytics.dart';
import '../coach_client.dart';
import '../models.dart';
import '../recovery.dart';
import '../store.dart';
import 'coach_widgets.dart';

/// Returns the new (or resumed) workout to its caller, which opens the logger.
class SessionPrepareScreen extends StatefulWidget {
  const SessionPrepareScreen(
      {super.key,
      this.initialReply,
      this.initialSourceRevision,
      this.initialSourceDay,
      this.client});
  final Map<String, dynamic>? initialReply;
  final int? initialSourceRevision;
  final String? initialSourceDay;
  final CoachClient? client;

  @override
  State<SessionPrepareScreen> createState() => _SessionPrepareScreenState();
}

class _SessionPrepareScreenState extends State<SessionPrepareScreen> {
  final _form = GlobalKey<FormState>();
  final _sleep = TextEditingController();
  final _notes = TextEditingController();
  final _recentTraining = TextEditingController();
  final _pain = TextEditingController();
  final _question = TextEditingController();
  final _scroll = ScrollController();
  Shift? _shift;
  Energy? _energy;
  int _minutes = 45;
  int _checkInVersion = 0;
  int? _planCheckInVersion;
  int? _sourceRevision;
  String? _sourceDay;
  Map<String, dynamic>? _reply;
  String? _error;
  bool _busy = false;
  bool _missingCheckIn = false;

  @override
  void initState() {
    super.initState();
    _reply = widget.initialReply;
    _sourceRevision = widget.initialSourceRevision;
    _sourceDay = widget.initialSourceDay;
    for (final controller in [_sleep, _notes, _recentTraining, _pain]) {
      controller.addListener(_changedCheckIn);
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _sleep,
      _notes,
      _recentTraining,
      _pain,
      _question
    ]) {
      controller.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  void _changedCheckIn() => setState(() => _checkInVersion++);

  SessionCheckIn get _checkIn => SessionCheckIn(
        shift: _shift!,
        energy: _energy!,
        timeMinutes: _minutes,
        sleepHours: _sleep.text.trim().isEmpty
            ? null
            : double.tryParse(_sleep.text.replaceAll(',', '.')),
        notes: _notes.text.trim(),
        recentTrainingNote: _recentTraining.text.trim(),
        painNote: _pain.text.trim(),
      );

  bool get _stale =>
      _sourceRevision != store.revision ||
      _sourceDay != dayKey(DateTime.now()) ||
      _planCheckInVersion != _checkInVersion;

  bool _validateCheckIn() {
    final validForm = _form.currentState!.validate();
    if (_shift == null || _energy == null) {
      setState(() {
        _missingCheckIn = true;
        _error = 'Choose your energy and work shift before continuing.';
      });
      _scroll.animateTo(0,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      return false;
    }
    // The optional sleep field may be collapsed and therefore unmounted.
    // Validate its controller too before making a request or saving a session.
    final sleepText = _sleep.text.trim();
    final hours = double.tryParse(sleepText.replaceAll(',', '.'));
    if (sleepText.isNotEmpty &&
        (hours == null || !hours.isFinite || hours < 0 || hours > 24)) {
      setState(() => _error =
          'Enter sleep hours between 0 and 24, or leave the sleep field blank.');
      return false;
    }
    return validForm;
  }

  Future<void> _ask() async {
    if (_busy || !_validateCheckIn()) return;
    final checkIn = _checkIn;
    final checkInVersion = _checkInVersion;
    final question = _question.text.trim().isNotEmpty
        ? _question.text.trim()
        : _reply == null
            ? 'Prepare a manageable session for today using my check-in and goals. Ask me about anything essential that is missing before planning.'
            : 'Refresh the session draft using my current check-in and history. Explain any changes. Ask me about anything essential that is missing.';
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final exchange = await requestCoachReply(context,
          question: question, checkIn: checkIn, client: widget.client);
      if (!mounted || exchange == null) return;
      final saved = store.saveCoachExchange(question, exchange.reply,
          sourceRevision: exchange.sourceRevision,
          sourceDay: exchange.sourceDay);
      setState(() {
        _reply = exchange.reply;
        _sourceRevision = exchange.sourceRevision;
        _sourceDay = exchange.sourceDay;
        _planCheckInVersion = checkInVersion;
        _question.clear();
        if (!saved) {
          _error =
              'Training data changed while your coach was replying. Ask again to use your current history.';
        }
      });
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

  void _start([Map<String, dynamic>? session]) {
    if (!mounted || _busy || !_validateCheckIn()) return;
    if (store.activeWorkout != null) {
      setState(() => _error =
          'A workout is already running. Resume it before starting another.');
      return;
    }
    if (session != null && _stale) {
      setState(() => _error =
          'Refresh your draft so it includes your latest check-in and training history.');
      return;
    }
    try {
      final exercises = <WorkoutExercise>[];
      if (session != null) {
        // Validate again at the point of applying a draft, including restored
        // drafts, so suggestions can never turn into invalid logged records.
        CoachClient.validateReply({
          'answer': '',
          'rationale': <String>[],
          'limitations': <String>[],
          'evidenceWorkoutIds': <String>[],
          'plan': [session],
        }, {
          'workouts': [],
          'exerciseCatalog': store.exercises.map((e) => e.toJson()).toList()
        });
        for (final e in session['exercises'] as List) {
          exercises.add(WorkoutExercise(e['exerciseId'] as String)
            ..target = ExerciseTarget(
              sets: e['sets'] as int,
              repsMin: (e['repsMin'] ?? e['reps']) as int,
              repsMax: (e['repsMax'] ?? e['reps']) as int,
              loadKg: (e['loadKg'] as num?)?.toDouble(),
              restSeconds: e['restSeconds'] as int? ?? 90,
              reason: e['reason'] as String,
            ));
        }
      }
      final workout = store.startWorkout(_shift!, _energy!,
          checkIn: _checkIn,
          exercises: exercises,
          planTitle: session?['title'] as String?);
      Navigator.pop(context, workout);
    } catch (_) {
      setState(() => _error =
          'This session could not be started. Refresh the draft or start a workout yourself.');
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final theme = Theme.of(context);
          final now = DateTime.now();
          final history = store.finishedWorkouts
              .where((w) => !w.start.isAfter(now) && !w.end!.isAfter(now))
              .toList()
            ..sort((a, b) => b.start.compareTo(a.start));
          final last = history.firstOrNull;
          final days =
              last == null ? null : calendarDaysBetween(last.start, now);
          final active = store.activeWorkout;
          return Scaffold(
            appBar: AppBar(title: const Text('Before you train')),
            body: SafeArea(
              child: Form(
                key: _form,
                child: Column(children: [
                  Expanded(
                      child: ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    children: [
                      Text('Let’s meet you where you are.',
                          style: theme.textTheme.headlineSmall),
                      const SizedBox(height: 8),
                      Text(last == null
                          ? 'Your first logged session starts here. Tell your coach a little about today.'
                          : days == 0
                              ? 'Your last logged session was today. How are you feeling now?'
                              : 'Your last logged session was $days ${days == 1 ? 'day' : 'days'} ago. Have you trained since?'),
                      if (active != null)
                        Card(
                            child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Text(
                                    'You already have a workout in progress.'),
                                FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(context, active),
                                    child: const Text('Resume workout')),
                              ]),
                        )),
                      const SizedBox(height: 20),
                      Text('How is your energy?',
                          style: theme.textTheme.titleSmall),
                      if (_missingCheckIn && _energy == null)
                        Text('Choose how you feel today.',
                            style: TextStyle(color: theme.colorScheme.error)),
                      const SizedBox(height: 6),
                      Wrap(spacing: 8, runSpacing: 4, children: [
                        for (final energy in Energy.values)
                          ChoiceChip(
                              label: Text('${energy.emoji} ${energy.label}'),
                              selected: _energy == energy,
                              onSelected: (_) => setState(() {
                                    _energy = energy;
                                    _checkInVersion++;
                                  })),
                      ]),
                      const SizedBox(height: 16),
                      Text('Your work shift',
                          style: theme.textTheme.titleSmall),
                      if (_missingCheckIn && _shift == null)
                        Text('Choose your shift or day off.',
                            style: TextStyle(color: theme.colorScheme.error)),
                      const SizedBox(height: 6),
                      Wrap(spacing: 8, runSpacing: 4, children: [
                        for (final shift in Shift.values)
                          ChoiceChip(
                              label: Text(
                                  shift == Shift.off ? 'Day off' : shift.short),
                              selected: _shift == shift,
                              onSelected: (_) => setState(() {
                                    _shift = shift;
                                    _checkInVersion++;
                                  })),
                      ]),
                      const SizedBox(height: 16),
                      Text('Time for today', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 6),
                      Wrap(spacing: 8, runSpacing: 4, children: [
                        for (final minutes in [20, 30, 45, 60, 90])
                          ChoiceChip(
                              label: Text('$minutes min'),
                              selected: _minutes == minutes,
                              onSelected: (_) => setState(() {
                                    _minutes = minutes;
                                    _checkInVersion++;
                                  })),
                      ]),
                      const SizedBox(height: 16),
                      _textField(_notes, 'How are you feeling?',
                          'Tired, motivated, nervous about returning…'),
                      _textField(
                          _recentTraining,
                          'Training since your last logged session',
                          'No training, a run, another gym session…'),
                      _textField(_pain, 'Any pain or movement limitations?',
                          'Optional · different from normal muscle soreness'),
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: const Text('Sleep · optional'),
                        children: [
                          TextFormField(
                              controller: _sleep,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration: InputDecoration(
                                  filled: true,
                                  fillColor: theme.colorScheme.surface,
                                  labelText: 'Hours of sleep',
                                  hintText: 'Optional, e.g. 7.5'),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return null;
                                }
                                final hours =
                                    double.tryParse(value.replaceAll(',', '.'));
                                return hours == null ||
                                        !hours.isFinite ||
                                        hours < 0 ||
                                        hours > 24
                                    ? 'Enter hours between 0 and 24, or leave blank.'
                                    : null;
                              }),
                          const SizedBox(height: 16),
                        ],
                      ),
                      if (_reply != null ||
                          store.coachConversation.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        const CoachConversation(recentCount: 4),
                      ],
                      if (_reply != null)
                        CoachDraftCard(
                            reply: _reply!,
                            stale: _stale,
                            staleMessage: _planCheckInVersion != _checkInVersion
                                ? 'Ask your coach to review this draft with today’s check-in before starting.'
                                : null,
                            onStart: _busy || active != null ? null : _start,
                            startLabel: 'Start this session'),
                      const SizedBox(height: 16),
                      TextFormField(
                          controller: _question,
                          minLines: 1,
                          maxLines: 4,
                          maxLength: 2000,
                          decoration: InputDecoration(
                              filled: true,
                              fillColor: theme.colorScheme.surface,
                              labelText: _reply == null
                                  ? 'Anything to ask your coach?'
                                  : 'Talk it through with your coach',
                              hintText: _reply == null
                                  ? 'Optional · your check-in is included'
                                  : 'Less leg work today, swap a machine, explain the load…')),
                      const SizedBox(height: 6),
                      Text(
                          'Your check-in is saved with your session. Coaching needs your OpenAI key; manual workouts work offline.',
                          style: theme.textTheme.bodySmall,
                          textAlign: TextAlign.center),
                    ],
                  )),
                  _actions(theme, active),
                ]),
              ),
            ),
          );
        },
      );

  Widget _actions(ThemeData theme, Workout? active) => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          border:
              Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
        ),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_error!,
                      style: TextStyle(color: theme.colorScheme.error)),
                ),
              FilledButton.icon(
                onPressed: _busy || active != null ? null : _ask,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.auto_awesome),
                label: Text(_busy
                    ? 'Thinking about your session…'
                    : _reply == null
                        ? 'Plan with my coach'
                        : 'Update with my coach'),
              ),
              TextButton.icon(
                onPressed: _busy || active != null ? null : () => _start(),
                style:
                    TextButton.styleFrom(visualDensity: VisualDensity.compact),
                icon: const Icon(Icons.fitness_center, size: 17),
                label: const Text('Start a workout myself'),
              ),
            ]),
      );

  Widget _textField(
          TextEditingController controller, String label, String hint) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: TextFormField(
              controller: controller,
              minLines: 1,
              maxLines: 3,
              maxLength: 500,
              decoration: InputDecoration(
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surface,
                  labelText: label,
                  hintText: hint,
                  counterText: '')));
}
