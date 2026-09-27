/// Turning a scattered set of race results into one usable fitness picture.
library;

import '../models/race.dart';
import 'riiegel.dart';
import 'vdot.dart';

/// How old a race may be and still be treated as current.
const int freshnessWindowDays = 183; // ~6 months

class FitnessAssessment {
  const FitnessAssessment({
    required this.races,
    required this.anchor,
    required this.equivalents,
    required this.vdot,
    required this.notes,
    required this.hasFreshRace,
  });

  /// Every race supplied, newest first.
  final List<RaceResult> races;

  /// The race everything else is derived from: the longest one recent enough
  /// to trust. Null when the runner supplied no races at all.
  final RaceResult? anchor;

  /// Equivalent times at every supported distance, derived from [anchor].
  final Map<RaceDistance, Duration> equivalents;

  /// VDOT implied by [anchor], or null when outside the calibrated range.
  final double? vdot;

  /// Data-quality notes to surface in the UI. These are shown rather than
  /// silently assumed — a runner should know when the plan is built on a
  /// two-year-old result.
  final List<String> notes;

  /// True if [anchor] falls inside [freshnessWindowDays].
  final bool hasFreshRace;

  bool get hasData => anchor != null;

  /// True when VDOT exists and is inside the calibrated range.
  bool get hasSupportedVdot => vdot != null && isVdotSupported(vdot!);

  Duration? equivalentTo(RaceDistance d) => equivalents[d];
}

/// Picks an anchor race and derives equivalent times across all distances.
///
/// Only one good recent race is actually needed: Riegel is invertible, so the
/// other three distances follow from it. Asking the runner for all four is
/// still worth doing, but completeness is not the point — recency is.
FitnessAssessment assessFitness(List<RaceResult> races, DateTime now) {
  if (races.isEmpty) {
    return const FitnessAssessment(
      races: [],
      anchor: null,
      equivalents: {},
      vdot: null,
      notes: [],
      hasFreshRace: false,
    );
  }

  final sorted = [...races]..sort((a, b) => b.date.compareTo(a.date));
  final notes = <String>[];

  final fresh = sorted.where((r) => r.ageInDays(now) <= freshnessWindowDays).toList();
  final hasFreshRace = fresh.isNotEmpty;

  final pool = hasFreshRace ? fresh : sorted;
  if (!hasFreshRace) {
    final age = pool.first.ageInDays(now);
    notes.add(
      'Your most recent result is $age days old. Everything below is based on it, '
      'so treat the paces as a starting point and adjust by feel.',
    );
  } else {
    // Results outside the freshness window are dropped so a stale PB cannot
    // quietly inflate the plan. But a runner who supplied a 1:56 half marathon
    // and watched it shape nothing deserves to be told rather than left to
    // wonder what happened to it.
    final stale = sorted
        .where((r) => r.ageInDays(now) > freshnessWindowDays)
        .toList();
    if (stale.isNotEmpty) {
      final one = stale.length == 1;
      notes.add(
        'Not used: your ${stale.map((r) => r.distance.label).join(' and ')} '
        '${one ? 'result is' : 'results are'} more than '
        '${freshnessWindowDays ~/ 30} months old, so ${one ? 'it is' : 'they are'} '
        'treated as out of date. Recent form is the safer basis for your paces.',
      );
    }
  }

  // Longest recent race is the most useful anchor: it involves the least
  // extrapolation, and it reflects endurance as well as speed.
  final byDistanceDesc = [...pool]
    ..sort((a, b) {
      final byDistance = b.distance.metres.compareTo(a.distance.metres);
      return byDistance != 0 ? byDistance : b.date.compareTo(a.date);
    });
  final anchor = byDistanceDesc.first;

  // A marathon is the best anchor of all; say so when we have it.
  if (anchor.distance == RaceDistance.marathon) {
    notes.add('Marathon result used as the anchor — the least extrapolation.');
  }

  final vdot = vdotFor(anchor.distance, anchor.time);
  if (vdot == null) {
    notes.add(
      'This result is outside the range where the VDOT model is reliable, so '
      'paces are derived from your race times directly rather than a fitness score.',
    );
  } else if (!hasFreshRace) {
    notes.add('VDOT ${vdot.round()} from a stale result — it is a floor, not a ceiling.');
  }

  final equivalents = <RaceDistance, Duration>{};
  for (final d in RaceDistance.values) {
    if (d == anchor.distance) {
      equivalents[d] = anchor.time;
    } else {
      equivalents[d] = predictFrom(anchor, target: d);
    }
  }

  return FitnessAssessment(
    races: sorted,
    anchor: anchor,
    equivalents: equivalents,
    vdot: vdot,
    notes: notes,
    hasFreshRace: hasFreshRace,
  );
}
