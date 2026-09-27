/// A change to the plan that the runner has explicitly agreed to.
///
/// This exists so that adaptation is always a *proposal*, never a silent
/// rewrite. The app's premise is "never too hard", and a plan that quietly
/// changes what it asked for undermines that — the runner has to see the
/// reasoning and agree. So nothing in here is applied automatically; a
/// directive only exists because [CoachProposal] was accepted.
///
/// Passed into `generate()` as an explicit input, so the plan stays a pure
/// function of its inputs.
library;

class PlanDirective {
  const PlanDirective({
    this.capVolume = false,
    this.targetDaysPerWeek,
  });

  /// Hold weekly volume flat from the first incomplete week onward.
  ///
  /// Weeks already completed keep the shape they were built with; only the
  /// future is held. The past is not rewritten.
  final bool capVolume;

  /// Override the number of training days. Null means "no change".
  ///
  /// Clamped to a sensible range by the caller. Three is the floor: below that
  /// the habit the plan is meant to be building stops existing.
  final int? targetDaysPerWeek;

  bool get isEmpty => !capVolume && targetDaysPerWeek == null;

  bool get isNotEmpty => !isEmpty;

  PlanDirective copyWith({
    bool? capVolume,
    int? targetDaysPerWeek,
    bool clearDays = false,
  }) {
    return PlanDirective(
      capVolume: capVolume ?? this.capVolume,
      targetDaysPerWeek:
          clearDays ? null : (targetDaysPerWeek ?? this.targetDaysPerWeek),
    );
  }

  /// A human-readable account of what is in force, for the review screen.
  List<String> get summary => [
        if (capVolume)
          'Volume is being held flat — the plan will not increase your '
              'weekly distance until you say so.',
        if (targetDaysPerWeek != null)
          'Training is set to $targetDaysPerWeek days a week.',
      ];

  Map<String, dynamic> toJson() => {
        'capVolume': capVolume,
        if (targetDaysPerWeek != null) 'targetDaysPerWeek': targetDaysPerWeek,
      };

  static PlanDirective fromJson(Map<String, dynamic> json) => PlanDirective(
        capVolume: json['capVolume'] == true,
        targetDaysPerWeek: (json['targetDaysPerWeek'] as num?)?.toInt(),
      );
}
