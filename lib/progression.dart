import 'models.dart';

/// A transparent suggestion for the next session, never an automatic change.
enum ProgressionAction { observe, recover, hold, addReps, considerLoad }

class ProgressionSuggestion {
  const ProgressionSuggestion(this.action, this.title, this.reason);

  final ProgressionAction action;
  final String title;
  final String reason;
}

/// Fourteen days is a cautious app rule, not a medical threshold. The caller
/// uses the last session of this exercise, including older training history.
const returnAfterBreakDays = 14;

ProgressionSuggestion nextSessionSuggestion(
  WorkoutExercise entry, {
  required Energy energy,
  bool hasPain = false,
  int? daysSincePrevious,
}) {
  if (hasPain) {
    return const ProgressionSuggestion(
      ProgressionAction.recover,
      'Check in before progressing',
      'Pain was reported for this session. Avoid increasing the load; choose a comfortable alternative and discuss persistent pain with a qualified professional.',
    );
  }
  if (energy == Energy.poor ||
      (daysSincePrevious != null &&
          daysSincePrevious >= returnAfterBreakDays)) {
    return ProgressionSuggestion(
      ProgressionAction.recover,
      'Build back comfortably',
      energy == Energy.poor
          ? 'You checked in with low energy. Reassess how you feel next time and keep the session manageable before considering an increase.'
          : 'This exercise followed a longer break. Use another comfortable session to check your current capacity before increasing the load.',
    );
  }
  if (entry.sets.any((set) => set.isWarmup == null)) {
    return const ProgressionSuggestion(
      ProgressionAction.observe,
      'Gather a little more context',
      'Some sets have no warm-up or working-set label. Log that and how hard working sets felt next time before deciding on an increase.',
    );
  }
  final working = entry.sets.where((set) => set.isWarmup == false).toList();
  if (working.isEmpty || working.any((set) => set.effort == null)) {
    return const ProgressionSuggestion(
      ProgressionAction.observe,
      'Log how your working sets feel',
      'Weight and reps alone do not show how demanding a session was. Add an effort rating to each working set to guide your next step.',
    );
  }
  if (working.any((set) => set.effort == SetEffort.limit)) {
    return const ProgressionSuggestion(
      ProgressionAction.hold,
      'Keep the next session manageable',
      'At least one working set was at your limit. Repeat a comfortable load or reduce it if needed, with controlled reps before adding more.',
    );
  }
  final target = entry.target;
  if (target == null) {
    return const ProgressionSuggestion(
      ProgressionAction.observe,
      'Set a repeatable target',
      'There was no planned set and rep range for this exercise. Use these working sets as a reference and agree a target with your coach.',
    );
  }
  if (working.length < target.sets ||
      working.any((set) => set.reps < target.repsMin)) {
    return const ProgressionSuggestion(
      ProgressionAction.hold,
      'Repeat the target',
      'The planned working sets or minimum reps were not all completed. Reassess the load and available time before adding more work.',
    );
  }
  final sameLoad = working.every((set) => set.kg == working.first.kg);
  final plannedLoadMet =
      target.loadKg == null || working.every((set) => set.kg >= target.loadKg!);
  final atTop = working.every((set) => set.reps >= target.repsMax);
  final easy = working.every((set) => set.effort == SetEffort.easy);
  if (atTop && easy && sameLoad && plannedLoadMet) {
    return const ProgressionSuggestion(
      ProgressionAction.considerLoad,
      'Consider the smallest available increase',
      'All planned working sets reached the top of the rep range at a consistent load and felt comfortable. If you feel recovered next time, try the smallest available increase and return to the lower end of the range.',
    );
  }
  if (!sameLoad || !plannedLoadMet) {
    return const ProgressionSuggestion(
      ProgressionAction.hold,
      'Find a repeatable working load',
      'Working loads varied or were below the plan. Pick a comfortable load you can repeat across the target range before increasing it.',
    );
  }
  if (!atTop && easy) {
    return const ProgressionSuggestion(
      ProgressionAction.addReps,
      'Try one more controlled rep',
      'The working sets felt comfortable and met the minimum target. Keep the load and consider one more rep on a set, within the planned range.',
    );
  }
  return const ProgressionSuggestion(
    ProgressionAction.hold,
    'Keep the load and build consistency',
    'You completed the target, but the sets were still challenging. Repeat it with controlled reps and reassess effort before increasing the load.',
  );
}
