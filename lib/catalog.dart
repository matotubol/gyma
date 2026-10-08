import 'models.dart';

/// Exercises that ship with the app. Ids are stored in workouts, so never
/// change an existing id — only add new ones.
const List<ExerciseDef> builtInExercises = [
  // Chest
  ExerciseDef('bench_press', 'Bench press', Muscle.chest, 'barbell'),
  ExerciseDef('incline_bench', 'Incline bench press', Muscle.chest, 'barbell'),
  ExerciseDef('dumbbell_press', 'Dumbbell press', Muscle.chest, 'barbell'),
  ExerciseDef('chest_fly', 'Chest fly', Muscle.chest, 'gymnastics'),
  ExerciseDef('chest_press', 'Chest press machine', Muscle.chest, 'body'),
  ExerciseDef('dips', 'Dips', Muscle.chest, 'gymnastics'),
  // Back
  ExerciseDef('deadlift', 'Deadlift', Muscle.back, 'barbell'),
  ExerciseDef('lat_pulldown', 'Lat pulldown', Muscle.back, 'gymnastics'),
  ExerciseDef('pull_ups', 'Pull-ups', Muscle.back, 'gymnastics'),
  ExerciseDef('seated_row', 'Seated row', Muscle.back, 'row'),
  ExerciseDef('barbell_row', 'Barbell row', Muscle.back, 'barbell'),
  // Legs
  ExerciseDef('squat', 'Squat', Muscle.legs, 'barbell'),
  ExerciseDef('leg_press', 'Leg press', Muscle.legs, 'legs'),
  ExerciseDef('leg_extension', 'Leg extension', Muscle.legs, 'legs'),
  ExerciseDef('leg_curl', 'Leg curl', Muscle.legs, 'legs'),
  ExerciseDef('lunges', 'Lunges', Muscle.legs, 'walk'),
  ExerciseDef('calf_raises', 'Calf raises', Muscle.legs, 'stairs'),
  ExerciseDef('hip_thrust', 'Hip thrust', Muscle.legs, 'barbell'),
  // Shoulders
  ExerciseDef('shoulder_press', 'Shoulder press', Muscle.shoulders, 'barbell'),
  ExerciseDef('lateral_raise', 'Lateral raise', Muscle.shoulders, 'body'),
  ExerciseDef('rear_delt_fly', 'Rear delt fly', Muscle.shoulders, 'body'),
  // Arms
  ExerciseDef('biceps_curl', 'Biceps curl', Muscle.arms, 'arm'),
  ExerciseDef('hammer_curl', 'Hammer curl', Muscle.arms, 'arm'),
  ExerciseDef('triceps_pushdown', 'Triceps pushdown', Muscle.arms, 'arm'),
  ExerciseDef('skull_crushers', 'Skull crushers', Muscle.arms, 'barbell'),
  // Core
  ExerciseDef('crunches', 'Crunches', Muscle.core, 'core'),
  ExerciseDef('plank', 'Plank', Muscle.core, 'core'),
  ExerciseDef('cable_crunch', 'Cable crunch', Muscle.core, 'core'),
];
