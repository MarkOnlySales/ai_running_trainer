/// Training intensity zones.
///
/// ## The anchor
///
/// Zones are multiples of a **marathon-equivalent pace**. When the runner has
/// a goal race, that anchor is the *goal* pace, not their current predicted
/// fitness. You train relative to the race you are preparing for; training to
/// a current-fitness prediction the user never asked for produces a plan that
/// quietly targets the wrong thing.
///
/// ## Provenance of the offsets
///
/// These are Jack Daniels' training-pace relationships from the 3rd edition
/// of *Training and Racing with a Power Meter*, expressed as seconds per mile
/// relative to marathon-equivalent pace.
///
/// Research for this project cross-checked them against published pace tables
/// and they agree closely. At VDOT 50 (marathon-equivalent 7:50/mi) the
/// derived threshold pace is 4:15/km against a published 4:16/km, and the
/// easy band falls inside the published 4:54–5:53/km range. The recovery,
/// easy, marathon and threshold offsets are therefore well corroborated.
///
/// The interval and repetition offsets are less well corroborated — sources
/// disagree by ~10% on these. They are low-stakes: v1 plan templates generate
/// tempo work and MP segments, never interval or repetition sessions, so these
/// values are display-only today. `test/domain/zones_test.dart` pins them so
/// that a future change to the interval-heavy templates is a deliberate act.
library;

import '../models/plan.dart';
import '../models/race.dart';
import '../units.dart';

/// Seconds per mile, relative to marathon-equivalent pace.
/// Positive = slower than marathon pace.
abstract final class ZoneOffset {
  static const int recovery = 100; // +1:40/mi
  static const int easy = 80; // +1:20/mi
  static const int marathon = 0;
  static const int threshold = -60; // -1:00/mi
  static const int interval = -85; // -1:25/mi
  static const int repetition = -125; // -2:05/mi
}

/// Metres in a mile. Used to convert a per-mile offset into a per-kilometre
/// one, which means *dividing* by 1.609 — a pace expressed in s/km is smaller
/// than the same pace in s/mi.
const double _metresPerMile = 1609.344;

/// Converts a per-mile offset in seconds into a per-kilometre offset.
int _toKmOffset(int secPerMile) =>
    (secPerMile / (_metresPerMile / 1000)).round();

/// Derives the five training paces from a marathon-equivalent [Pace].
///
/// This is the single place paces are computed. Both the goal-anchored and
/// the fitness-anchored paths funnel through here.
TrainingPaces pacesFromMarathonPace(Pace marathonPace) => TrainingPaces(
      repetition: marathonPace.plusSeconds(_toKmOffset(ZoneOffset.repetition)),
      interval: marathonPace.plusSeconds(_toKmOffset(ZoneOffset.interval)),
      threshold: marathonPace.plusSeconds(_toKmOffset(ZoneOffset.threshold)),
      marathon: marathonPace,
      easy: marathonPace.plusSeconds(_toKmOffset(ZoneOffset.easy)),
      recovery: marathonPace.plusSeconds(_toKmOffset(ZoneOffset.recovery)),
    );

/// The anchor pace zones should be built from.
///
/// Preference order:
///  1. The goal race pace, when a goal is set — this is the point of the app.
///  2. The equivalent marathon pace implied by current fitness, derived
///     through Riegel from the runner's best recent race.
///
/// When the goal distance is not a marathon, its pace is still the correct
/// anchor: the zone *offsets* are defined relative to marathon-equivalent
/// effort, and a 10K or half goal supplies its own reference point.
Pace zoneAnchorPace({
  required RaceDistance? goalDistance,
  required Duration? goalFinishTime,
  required Duration? equivalentMarathonTime,
  required RaceDistance? anchorRaceDistance,
  required Duration? anchorRaceTime,
}) {
  if (goalDistance != null && goalFinishTime != null) {
    return Pace.fromDuration(goalFinishTime, goalDistance.metres);
  }
  if (equivalentMarathonTime != null) {
    return Pace.fromDuration(equivalentMarathonTime, 42197.5);
  }
  if (anchorRaceDistance != null && anchorRaceTime != null) {
    // No marathon equivalent available (e.g. a stale-only race set). Fall
    // back to projecting from the race we do have, which is what the pure
    // VDOT path would have done anyway.
    return Pace.fromDuration(anchorRaceTime, anchorRaceDistance.metres);
  }
  throw StateError('Cannot derive a zone anchor without any race data.');
}
