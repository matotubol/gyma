/// A local calendar day, independent of UTC conversions and DST.
String dayKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

enum BodyArea {
  chest('Chest'),
  upperBack('Upper back'),
  lowerBack('Lower back'),
  shoulders('Shoulders'),
  biceps('Biceps'),
  triceps('Triceps'),
  forearms('Forearms'),
  abs('Abs'),
  glutes('Glutes'),
  quads('Quads'),
  hamstrings('Hamstrings'),
  calves('Calves');

  const BodyArea(this.label);
  final String label;
}

enum Soreness {
  none('None'),
  mild('Mild'),
  moderate('Moderate'),
  severe('Severe');

  const Soreness(this.label);
  final String label;
}

class RecoveryDay {
  RecoveryDay(
      {required this.day,
      Map<BodyArea, Soreness>? muscles,
      Set<BodyArea>? painAreas,
      this.notes = '',
      DateTime? updatedAt})
      : muscles = Map.unmodifiable(muscles ?? {}),
        painAreas = Set.unmodifiable(painAreas ?? {}),
        updatedAt = updatedAt ?? DateTime.now().toUtc();

  final String day;
  final Map<BodyArea, Soreness> muscles;
  final Set<BodyArea> painAreas;
  final String notes;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => {
        'day': day,
        'muscles': {for (final e in muscles.entries) e.key.name: e.value.name},
        'painAreas': [for (final area in painAreas) area.name],
        'notes': notes,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory RecoveryDay.fromJson(Map<String, dynamic> json) => RecoveryDay(
        day: json['day'] as String,
        muscles: {
          for (final e in (json['muscles'] as Map<String, dynamic>).entries)
            BodyArea.values.byName(e.key):
                Soreness.values.byName(e.value as String)
        },
        painAreas: {
          for (final a in json['painAreas'] as List? ?? [])
            BodyArea.values.byName(a as String)
        },
        notes: json['notes'] as String? ?? '',
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );
}
