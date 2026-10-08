import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../analytics.dart';
import '../api_key_store.dart';
import '../coach_client.dart';
import '../format.dart';
import '../models.dart';
import '../store.dart';
import 'api_key_screen.dart';
import 'workout_detail_screen.dart';

class CoachExchange {
  const CoachExchange(this.reply, this.sourceRevision, this.sourceDay);
  final Map<String, dynamic> reply;
  final int sourceRevision;
  final String sourceDay;
}

/// No request or data mutation happens after a dismissed screen. The caller
/// saves a completed exchange only while it is still mounted.
Future<CoachExchange?> requestCoachReply(BuildContext context,
    {required String question,
    SessionCheckIn? checkIn,
    CoachClient? client}) async {
  String? apiKey;
  try {
    apiKey = await ApiKeyStore().read();
  } catch (_) {
    throw const HttpException(
        'Could not read your API key. Unlock your device and check OpenAI settings.');
  }
  if (!context.mounted) return null;
  if (apiKey == null || apiKey.isEmpty) {
    await Navigator.push(
        context, MaterialPageRoute<void>(builder: (_) => const ApiKeyScreen()));
    return null;
  }
  final send = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Send training context?'),
      content: const Text(
          'Send your message, saved coaching conversation, preferences, recent workouts, older last-exercise baselines, current workout, today’s check-in, soreness and pain notes directly to OpenAI. Photos, deleted workouts and edit history are excluded.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Send')),
      ],
    ),
  );
  if (send != true || !context.mounted) return null;
  final data = trainingContext(store, DateTime.now(), checkIn: checkIn);
  final reply = await (client ?? CoachClient()).ask(
    apiKey: apiKey,
    question: question,
    context: data,
    conversation: List.of(store.coachConversation),
  );
  return CoachExchange(
      reply, data['dataRevision'] as int, data['localToday'] as String);
}

String coachError(Object error) => error is HttpException
    ? error.message
    : 'Could not get a complete reply. Check your connection and OpenAI settings, then try again. You can still start a workout yourself.';

class CoachConversation extends StatelessWidget {
  const CoachConversation({super.key, this.recentCount = 6});
  final int recentCount;

  @override
  Widget build(BuildContext context) {
    final messages = store.coachConversation;
    final split = (messages.length - recentCount).clamp(0, messages.length);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (split > 0)
          ExpansionTile(
            title: const Text('Earlier conversation'),
            children: [
              for (final message in messages.take(split))
                _bubble(context, message)
            ],
          ),
        for (final message in messages.skip(split)) _bubble(context, message),
      ],
    );
  }

  Widget _bubble(BuildContext context, Map<String, String> message) {
    final isUser = message['role'] == 'user';
    var text = message['content'] ?? '';
    if (!isUser) {
      try {
        text = (jsonDecode(text) as Map)['answer'] as String;
      } catch (_) {
        // Plain-text historical messages remain readable.
      }
    }
    final theme = Theme.of(context);
    return Container(
      margin: EdgeInsets.only(
          top: 8, left: isUser ? 24 : 0, right: isUser ? 0 : 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isUser
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(isUser ? 'You' : 'Your coach', style: theme.textTheme.labelMedium),
        const SizedBox(height: 4),
        SelectableText(text),
      ]),
    );
  }
}

class CoachDraftCard extends StatelessWidget {
  const CoachDraftCard(
      {super.key,
      required this.reply,
      this.stale = false,
      this.staleMessage,
      this.onStart,
      this.activeSession = false,
      this.startLabel = 'Prepare this session'});
  final Map<String, dynamic> reply;
  final bool stale;
  final String? staleMessage;
  final void Function(Map<String, dynamic> session)? onStart;
  final String startLabel;
  final bool activeSession;

  @override
  Widget build(BuildContext context) {
    final plan = reply['plan'] as List? ?? [];
    final rationale = reply['rationale'] as List? ?? [];
    final limitations = reply['limitations'] as List? ?? [];
    final evidence = reply['evidenceWorkoutIds'] as List? ?? [];
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(plan.isEmpty ? 'Coach’s reasoning' : 'Your session draft',
              style: Theme.of(context).textTheme.titleLarge),
          if (stale)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                  staleMessage ??
                      'Your data or the day has changed. Ask your coach to refresh this draft before training.',
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          if (plan.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(activeSession
                  ? 'Targets for working sets, including those already logged. Warm-ups do not count.'
                  : 'Targets for your next workout. Log each set as you complete it.'),
            ),
          for (final item in plan) ...[
            const SizedBox(height: 16),
            Text(item['title'] as String,
                style: Theme.of(context).textTheme.titleMedium),
            for (final exercise in item['exercises'] as List)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          store.exercise(exercise['exerciseId'] as String).name,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 3),
                      Text(
                          '${exercise['sets']} sets × ${_reps(exercise)} reps · ${exercise['loadKg'] == null ? 'choose a comfortable load' : '${fmtKg((exercise['loadKg'] as num).toDouble())} kg'}'),
                      Text(
                          '${exercise['restSeconds'] ?? 90}s rest · ${exercise['reason']}',
                          style: Theme.of(context).textTheme.bodySmall),
                    ]),
              ),
            if (onStart != null)
              FilledButton.icon(
                onPressed: stale
                    ? null
                    : () => onStart!(Map<String, dynamic>.from(item as Map)),
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(startLabel),
              ),
          ],
          if (rationale.isNotEmpty ||
              limitations.isNotEmpty ||
              evidence.isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Why this plan?'),
              children: [
                for (final reason in [...rationale, ...limitations])
                  Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text('• $reason'))),
                for (final workout in store.finishedWorkouts
                    .where((w) => evidence.contains(w.id)))
                  TextButton.icon(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                            builder: (_) =>
                                WorkoutDetailScreen(workout: workout))),
                    icon: const Icon(Icons.history, size: 18),
                    label: Text('Session used · ${fmtDate(workout.start)}'),
                  ),
              ],
            ),
        ]),
      ),
    );
  }

  String _reps(dynamic e) {
    final min = e['repsMin'] ?? e['reps'];
    final max = e['repsMax'] ?? e['reps'];
    return min == max ? '$min' : '$min–$max';
  }
}
