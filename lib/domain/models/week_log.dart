/// What a runner records about a week they have done.
///
/// ## Why per-week, not per-run
///
/// Deliberate product decision. A per-run log grows without bound and would
/// eventually force a real database; per-week keeps a few dozen small records
/// in `shared_preferences`, which is the right tool at this size.
///
/// The trade-off is real and worth stating: per-week adaptation is coarser.
/// You learn that a week was too hard, not *which* session in it was. That is
/// enough to cap progression and to flag a block as too ambitious, but not
/// enough to rewrite a specific workout.
///
/// ## Why difficulty is the important field
///
/// `completed` answers "did you do it". `difficulty` answers "was it too
/// much", and the second question is the one the product exists to handle. A
/// runner who ticks every box while grinding out every week is following a
/// plan that is too hard for them, and only difficulty reveals that.
library;

class WeekLog {
  const WeekLog({
    this.completed = false,
    this.actualKm,
    this.sessionsDone,
    this.difficulty,
    this.note,
  });

  /// The runner marked the week done.
  final bool completed;

  /// Distance actually run, in km. Null if not recorded.
  final double? actualKm;

  /// How many of the prescribed sessions were actually run.
  final int? sessionsDone;

  /// How hard the week felt overall, 1–10. Null if not recorded.
  ///
  /// 1–2 is uncomfortably easy, 3–4 about right, 7+ too hard. Anything
  /// consistently at 8+ means the plan is miscalibrated for this runner.
  final int? difficulty;

  /// Free text. A place for "knee hurt", "holiday", "life happened".
  final String? note;

  bool get hasData =>
      completed ||
      actualKm != null ||
      sessionsDone != null ||
      difficulty != null ||
      (note != null && note!.trim().isNotEmpty);

  /// A week that felt too hard, by the runner's own account.
  bool get feltTooHard => (difficulty ?? 0) >= 8;

  /// A week that was comfortably too easy.
  bool get feltTooEasy => difficulty != null && difficulty! <= 2;

  WeekLog copyWith({
    bool? completed,
    double? actualKm,
    int? sessionsDone,
    int? difficulty,
    String? note,
    bool clearNote = false,
  }) {
    return WeekLog(
      completed: completed ?? this.completed,
      actualKm: actualKm ?? this.actualKm,
      sessionsDone: sessionsDone ?? this.sessionsDone,
      difficulty: difficulty ?? this.difficulty,
      note: clearNote ? null : (note ?? this.note),
    );
  }

  Map<String, dynamic> toJson() => {
        'completed': completed,
        if (actualKm != null) 'actualKm': actualKm,
        if (sessionsDone != null) 'sessionsDone': sessionsDone,
        if (difficulty != null) 'difficulty': difficulty,
        if (note != null && note!.trim().isNotEmpty) 'note': note,
      };

  static WeekLog fromJson(Map<String, dynamic> json) => WeekLog(
        completed: json['completed'] == true,
        actualKm: (json['actualKm'] as num?)?.toDouble(),
        sessionsDone: (json['sessionsDone'] as num?)?.toInt(),
        difficulty: (json['difficulty'] as num?)?.toInt(),
        note: json['note'] as String?,
      );
}
