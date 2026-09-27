/// Progress over a generated plan.
///
/// ## Why this is keyed on week *dates*, not week numbers
///
/// The plan is a pure function of the profile, so changing the goal
/// regenerates it. A week number is therefore not a stable identity — "week 5"
/// can mean a different session before and after a rebuild. Keying completion
/// on [PlanWeek.startDate] makes it stable across regeneration, which is what
/// allows a goal change to stop throwing away the weeks already done.
///
/// ## Why this lives in `domain/`
///
/// It is pure Dart with no Flutter import, so the whole thing is unit-testable
/// without a widget harness — and this is the logic that decides whether a
/// runner is told they are behind. It needs to be easy to test, not
/// convenient to reach.
library;

import 'models/plan.dart';
import 'models/week_log.dart';

/// Stable key for a plan week. ISO `yyyy-MM-dd` of the week start.
String weekKey(DateTime weekStart) {
  final m = weekStart.month.toString().padLeft(2, '0');
  final d = weekStart.day.toString().padLeft(2, '0');
  return '${weekStart.year}-$m-$d';
}

class PlanProgress {
  const PlanProgress({
    required this.plan,
    required this.weekLogs,
    this.now,
  });

  final TrainingPlan plan;

  /// Week-start key → what the runner recorded for that week.
  final Map<String, WeekLog> weekLogs;

  /// Injectable so the calendar logic is testable without a real clock.
  final DateTime? now;

  DateTime get today => now ?? DateTime.now();

  int get weekCount => plan.weekCount;

  String _key(int index) => weekKey(plan.weeks[index].startDate);

  /// The record for a week, or an empty one if nothing was recorded.
  WeekLog logFor(int index) =>
      (index >= 0 && index < weekCount) ? weekLogs[_key(index)] ?? const WeekLog() : const WeekLog();

  bool hasLog(int index) =>
      index >= 0 && index < weekCount && (weekLogs[_key(index)]?.hasData ?? false);

  bool isComplete(int index) =>
      index >= 0 && index < weekCount && logFor(index).completed;

  /// The first week that has not been marked complete.
  int get firstIncompleteIndex {
    for (var i = 0; i < weekCount; i++) {
      if (!isComplete(i)) return i;
    }
    return weekCount;
  }

  int get completedCount {
    var n = 0;
    for (var i = 0; i < weekCount; i++) {
      if (isComplete(i)) n++;
    }
    return n;
  }

  /// Share of the whole block that is done. Only meaningful once the runner is
  /// part-way through; use [missedWeekCount] for "am I behind".
  double get completionRate =>
      weekCount == 0 ? 0 : completedCount / weekCount;

  /// The week the calendar says the runner should be on.
  ///
  /// Clamped at both ends so a plan that has not started yet, or has already
  /// ended, still points somewhere sensible.
  int get calendarWeekIndex {
    if (weekCount == 0) return 0;
    final t = today;
    final midnight = DateTime(t.year, t.month, t.day);
    var index = 0;
    for (var i = 0; i < weekCount; i++) {
      final start = plan.weeks[i].startDate;
      if (!start.isAfter(midnight)) {
        index = i;
      } else {
        break;
      }
    }
    return index;
  }

  /// Weeks that should already have happened but were never marked done.
  ///
  /// Strictly *before* the current week. The week in progress is not missed —
  /// on the first day of week 1 nothing is missed, whatever the state.
  int get missedWeekCount {
    final limit = calendarWeekIndex;
    var n = 0;
    for (var i = 0; i < limit && i < weekCount; i++) {
      if (!isComplete(i)) n++;
    }
    return n;
  }

  /// Where to actually drop the runner.
  ///
  /// If weeks were missed, back to the first one — showing someone week 12 of
  /// a plan they never started is the trap this replaces. If nothing was
  /// missed, never show a week they have already completed: a runner who has
  /// finished four weeks should see week 5 even if the calendar says week 2.
  int get suggestedWeekIndex {
    if (weekCount == 0) return 0;
    final first = firstIncompleteIndex;
    if (missedWeekCount > 0) return first.clamp(0, weekCount - 1);
    final ahead = first < weekCount ? first : weekCount - 1;
    final target = calendarWeekIndex > ahead ? calendarWeekIndex : ahead;
    return target.clamp(0, weekCount - 1);
  }

  /// True if this week is built on a week the runner did not complete.
  ///
  /// Weeks up to the first gap are real; everything after it is still
  /// generated on the assumption that gap does not exist. Saying so out loud
  /// is more honest than presenting it as settled.
  bool isProvisional(int index) {
    for (var i = 0; i < index && i < weekCount; i++) {
      if (!isComplete(i)) return true;
    }
    return false;
  }

  /// How many earlier weeks this one is waiting on.
  int outstandingBefore(int index) {
    var n = 0;
    for (var i = 0; i < index && i < weekCount; i++) {
      if (!isComplete(i)) n++;
    }
    return n;
  }

  /// True if every week is done.
  bool get isFinished => weekCount > 0 && completedCount == weekCount;

  // -------------------------------------------------------------------------
  // Adherence and difficulty. These are the raw signals a coaching layer would
  // read. They are computed here rather than in the controller because they are
  // pure functions of the plan and the logs, and they need to be testable
  // without a widget harness.
  // -------------------------------------------------------------------------

  /// Sessions actually run across all logged weeks, where recorded.
  int get sessionsLogged {
    var n = 0;
    for (var i = 0; i < weekCount; i++) {
      n += logFor(i).sessionsDone ?? 0;
    }
    return n;
  }

  /// Sessions prescribed across all logged weeks, where recorded.
  int get sessionsPrescribedInLoggedWeeks {
    var n = 0;
    for (var i = 0; i < weekCount; i++) {
      if (logFor(i).sessionsDone != null) n += plan.weeks[i].runCount;
    }
    return n;
  }

  /// Share of prescribed sessions actually run, in logged weeks. Null when
  /// nothing has been recorded, because "no data" must not read as "0%".
  double? get sessionAdherence {
    final prescribed = sessionsPrescribedInLoggedWeeks;
    if (prescribed == 0) return null;
    return sessionsLogged / prescribed;
  }

  /// Distance actually run across logged weeks, where recorded.
  double get kmLogged {
    var total = 0.0;
    for (var i = 0; i < weekCount; i++) {
      total += logFor(i).actualKm ?? 0;
    }
    return total;
  }

  /// Distance prescribed for the same logged weeks, in km.
  double get kmPrescribedInLoggedWeeks {
    var total = 0.0;
    for (var i = 0; i < weekCount; i++) {
      if (logFor(i).actualKm != null) total += plan.weeks[i].targetVolumeKm;
    }
    return total;
  }

  /// Share of prescribed distance actually run, in logged weeks. Null when
  /// nothing recorded.
  double? get volumeAdherence {
    final prescribed = kmPrescribedInLoggedWeeks;
    if (prescribed <= 0) return null;
    return kmLogged / prescribed;
  }

  /// Weeks where the runner said it was too hard.
  List<int> get hardWeeks => [
        for (var i = 0; i < weekCount; i++)
          if (logFor(i).feltTooHard) i,
      ];

  /// Mean difficulty across weeks that recorded one. Null when none did.
  double? get averageDifficulty {
    final values = <int>[
      for (var i = 0; i < weekCount; i++)
        if (logFor(i).difficulty != null) logFor(i).difficulty!,
    ];
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a + b) / values.length;
  }

  /// The plan looks miscalibrated for this runner: a third or more of their
  /// logged weeks came back too hard.
  ///
  /// This is the signal that most directly serves the "never too hard"
  /// promise, and it is the reason [difficulty] exists on the log at all.
  bool get looksTooHard =>
      hardWeeks.length >= 3 &&
      averageDifficulty != null &&
      averageDifficulty! >= 7.0;

  /// The number of sessions the plan normally asks for in a week.
  ///
  /// The *mode* across weeks the runner actually logged, not the last week's
  /// count: a race week prescribes two sessions and a cutback prescribes
  /// fewer, so either would badly misrepresent what the plan is asking of
  /// someone. The mode is "what a normal week looks like".
  int? get typicalPrescribedSessions {
    final counts = <int, int>{};
    for (var i = 0; i < weekCount; i++) {
      if (logFor(i).sessionsDone == null) continue;
      final n = plan.weeks[i].runCount;
      counts[n] = (counts[n] ?? 0) + 1;
    }
    if (counts.isEmpty) return null;
    var best = counts.entries.first;
    for (final e in counts.entries) {
      if (e.value > best.value || (e.value == best.value && e.key > best.key)) {
        best = e;
      }
    }
    return best.key;
  }

  /// True if the runner is consistently under-doing, without finding it hard —
  /// the signature of a plan that is pitched too high for their life, not their
  /// fitness.
  bool get looksUnderserved =>
      sessionAdherence != null &&
      sessionAdherence! < 0.7 &&
      (averageDifficulty ?? 10) <= 5;
}
