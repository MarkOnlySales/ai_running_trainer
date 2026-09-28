import 'package:ai_running_trainer/domain/engine/fitness.dart';
import 'package:ai_running_trainer/domain/engine/validation.dart';
import 'package:ai_running_trainer/domain/engine/vdot.dart';
import 'package:ai_running_trainer/domain/engine/zones.dart';
import 'package:ai_running_trainer/domain/models/goal.dart';
import 'package:ai_running_trainer/domain/models/plan.dart';
import 'package:ai_running_trainer/domain/models/profile.dart';
import 'package:ai_running_trainer/domain/models/race.dart';
import 'package:ai_running_trainer/domain/plan/generate.dart';
import 'package:ai_running_trainer/domain/units.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dump paces', () {
    final now = DateTime(2026, 9, 28);
    final out = StringBuffer();
    void say(String s) => out.writeln(s);

    final races = [
      RaceResult(
          distance: RaceDistance.k5,
          time: const Duration(minutes: 24, seconds: 10),
          date: now.subtract(const Duration(days: 5))),
      RaceResult(
          distance: RaceDistance.k10,
          time: const Duration(minutes: 52, seconds: 25),
          date: now.subtract(const Duration(days: 1))),
      RaceResult(
          distance: RaceDistance.half,
          time: const Duration(hours: 1, minutes: 56, seconds: 10),
          date: now.subtract(const Duration(days: 36))),
    ];
    const profile = RunnerProfile(
      name: 'Mark',
      age: 34,
      gender: Gender.preferNotToSay,
      monthsRunning: 24,
      daysPerWeek: 4,
      estimatedWeeklyKm: 35,
    );
    final goal = GoalRace(
      distance: RaceDistance.k10,
      date: now.add(const Duration(days: 120)),
      finishTimeGoal: const Duration(minutes: 49),
      daysPerWeek: 4,
    );

    final f = assessFitness(races, now);
    say('VDOT per race:');
    for (final r in races) {
      say('  ${r.distance.label.padRight(16)} ${r.time.toString().padRight(12)} '
          'vdot ${vdotFor(r.distance, r.time)?.toStringAsFixed(1)}');
    }
    say('ANCHOR: ${f.anchor}  vdot ${f.vdot?.toStringAsFixed(1)}');
    say('marathon equivalent: ${f.equivalents[RaceDistance.marathon]}');
    say('10K equivalent from anchor: ${f.equivalents[RaceDistance.k10]}');
    say('');

    // What the goal asks for.
    final goalPace =
        Pace.fromDuration(goal.finishTimeGoal, goal.distance.metres);
    say('GOAL ${goal.distance.label} in ${goal.finishTimeGoal} '
        '= ${goalPace.format()}/km');
    final pb10k = Pace.fromDuration(
        const Duration(minutes: 52, seconds: 25), RaceDistance.k10.metres);
    final improvement =
        (pb10k.secPerKm - goalPace.secPerKm) / pb10k.secPerKm;
    say('  10K PB pace      ${pb10k.format()}/km');
    say('  improvement asked: ${(improvement * 100).toStringAsFixed(1)}%');
    say('');

    // The two candidate anchors.
    final goalAnchored = zoneAnchorPace(
      goalDistance: goal.distance,
      goalFinishTime: goal.finishTimeGoal,
      equivalentMarathonTime: f.equivalents[RaceDistance.marathon],
      anchorRaceDistance: f.anchor!.distance,
      anchorRaceTime: f.anchor!.time,
    );
    final fitnessAnchored = zoneAnchorPace(
      goalDistance: null,
      goalFinishTime: null,
      equivalentMarathonTime: f.equivalents[RaceDistance.marathon],
      anchorRaceDistance: f.anchor!.distance,
      anchorRaceTime: f.anchor!.time,
    );
    say('ANCHOR A — goal race pace (what the app does today): '
        '${goalAnchored.format()}/km');
    say('ANCHOR B — current fitness (marathon equivalent): '
        '${fitnessAnchored.format()}/km');
    say('');

    String ladder(String label, Pace anchor) {
      final p = pacesFromMarathonPace(anchor);
      say(label);
      for (final z in IntensityZone.slowestFirst) {
        say('  ${z.name.padRight(11)} ${p.forZone(z).format()}/km');
      }
      return '';
    }

    ladder('LADDER A — goal-anchored (current behaviour)', goalAnchored);
    say('');
    ladder('LADDER B — fitness-anchored', fitnessAnchored);
    say('');
    say('DIFFERENCE (A minus B, sec/km):');
    final pa = pacesFromMarathonPace(goalAnchored);
    final pb = pacesFromMarathonPace(fitnessAnchored);
    for (final z in IntensityZone.slowestFirst) {
      say('  ${z.name.padRight(11)} '
          '${(pa.forZone(z).secPerKm - pb.forZone(z).secPerKm).toStringAsFixed(0)}s');
    }
    say('');

    // What flags did the app raise about the goal?
    final flags = validate(
      profile: profile,
      fitness: f,
      goal: goal,
      today: now,
    );
    say('FLAGS ON THE GOAL (${flags.length}):');
    for (final fl in flags) {
      say('  [${fl.severity.name}] ${fl.title}');
    }

    // ignore: avoid_print
    print(out.toString());
  });
}
