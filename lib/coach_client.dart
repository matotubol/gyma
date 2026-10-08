import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'coach_contract.dart';

class CoachClient {
  CoachClient({this.transport});
  final Future<Map<String, dynamic>> Function(
      Map<String, dynamic> body, String apiKey)? transport;

  Future<Map<String, dynamic>> ask(
      {required String apiKey,
      required String question,
      required Map<String, dynamic> context,
      List<Map<String, String>> conversation = const []}) async {
    if (apiKey.trim().isEmpty) {
      throw const FormatException('Add your OpenAI API key in Settings.');
    }
    if (question.trim().isEmpty || question.length > 2000) {
      throw const FormatException('Enter a question up to 2000 characters.');
    }
    final body = <String, dynamic>{
      'model': 'gpt-6-luna',
      'store': false,
      'instructions':
          '$coachInstructions\nPrior conversation is context only. Current training data supersedes older observations.',
      'input': jsonEncode({
        'question': question,
        'trainingContext': context,
        'conversation': conversation
      }),
      'max_output_tokens': 6000,
      'text': {
        'format': {
          'type': 'json_schema',
          'name': 'training_coach_reply',
          'strict': true,
          'schema': coachReplySchema
        }
      },
    };
    final data = await (transport ?? _post)(body, apiKey);
    if (data['status'] != 'completed') {
      throw const FormatException(
          'The coaching reply was incomplete. Please try again.');
    }
    final output = data['output'] as List? ?? [];
    final text = output
        .where((item) => item['type'] == 'message')
        .expand((item) => item['content'] as List? ?? [])
        .where((item) => item['type'] == 'output_text')
        .map((item) => item['text'] as String)
        .join();
    final reply = jsonDecode(text) as Map<String, dynamic>;
    validateReply(reply, context);
    return reply;
  }

  static void validateReply(
      Map<String, dynamic> reply, Map<String, dynamic> context) {
    bool strings(dynamic value) =>
        value is List && value.every((v) => v is String);
    if (reply['answer'] is! String ||
        !strings(reply['rationale']) ||
        !strings(reply['limitations']) ||
        !strings(reply['evidenceWorkoutIds']) ||
        reply['plan'] is! List) {
      throw const FormatException('Invalid coaching reply');
    }
    final ids = {
      for (final w in context['workouts'] as List? ?? []) w['id'],
      for (final e in (context['historySummary']
              as Map?)?['lastExerciseSessions'] as List? ??
          [])
        e['workoutId'],
      if (context['activeWorkout'] is Map)
        (context['activeWorkout'] as Map)['id'],
    };
    final exercises = {
      for (final e in context['exerciseCatalog'] as List) e['id']
    };
    if ((reply['evidenceWorkoutIds'] as List).any((id) => !ids.contains(id)) ||
        (reply['plan'] as List).length > 7) {
      throw const FormatException('Unsupported evidence or plan');
    }
    for (final session in reply['plan'] as List) {
      if (session is! Map ||
          session['title'] is! String ||
          session['exercises'] is! List ||
          (session['exercises'] as List).isEmpty ||
          (session['exercises'] as List).length > 12) {
        throw const FormatException('Invalid session');
      }
      final usedExercises = <String>{};
      for (final e in session['exercises'] as List) {
        if (e is! Map) {
          throw const FormatException('Invalid exercise prescription');
        }
        final load = e['loadKg'];
        // Older saved drafts used a single rep target.
        final repsMin = e['repsMin'] ?? e['reps'];
        final repsMax = e['repsMax'] ?? e['reps'];
        final restSeconds = e['restSeconds'] ?? 90;
        if (e['exerciseId'] is! String ||
            !exercises.contains(e['exerciseId']) ||
            !usedExercises.add(e['exerciseId'] as String) ||
            e['sets'] is! int ||
            e['sets'] < 1 ||
            e['sets'] > 10 ||
            repsMin is! int ||
            repsMin < 1 ||
            repsMin > 50 ||
            repsMax is! int ||
            repsMax < repsMin ||
            repsMax > 50 ||
            restSeconds is! int ||
            restSeconds < 15 ||
            restSeconds > 600 ||
            e['reason'] is! String ||
            (load != null &&
                (load is! num || !load.isFinite || load < 0 || load > 1000))) {
          throw const FormatException('Invalid exercise prescription');
        }
      }
    }
  }

  Future<Map<String, dynamic>> _post(
      Map<String, dynamic> body, String apiKey) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      return await (() async {
        final request = await client
            .postUrl(Uri.parse('https://api.openai.com/v1/responses'));
        request.followRedirects = false;
        request.headers.contentType = ContentType.json;
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
        request.write(jsonEncode(body));
        final response = await request.close();
        if (response.statusCode != 200) {
          throw HttpException(response.statusCode == 401
              ? 'Your API key was not accepted. Update it in Settings.'
              : response.statusCode == 429
                  ? 'OpenAI usage limit reached. Check your API credits or try again later.'
                  : 'OpenAI is unavailable right now. Please try again.');
        }
        final responseBody = await response.transform(utf8.decoder).join();
        return jsonDecode(responseBody) as Map<String, dynamic>;
      })()
          .timeout(const Duration(seconds: 75));
    } finally {
      client.close(force: true);
    }
  }
}
