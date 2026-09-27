/// Phase 9 diagnostic — TEMPORARY. Delete once the cause is found.
///
/// Prints why `isBeginnerPath` returned what it did, and what each generated
/// week actually contains. Two attempts to diagnose this by reading the code
/// both reached the wrong answer, so this reads the real stored state instead.
///
/// Save as: integration_test/diagnostic_hard_sessions_test.dart
/// Run:   flutter test integration_test/diagnostic_hard_sessions_test.dart -d emulator-5554
///
/// NOTE: it writes a profile, so it replaces whatever is stored on the device.
library;

import 'package:ai_running_trainer/app/controller.dart';
import 'package:ai_running_trainer/app/storage.dart';
import 'package:ai_running_trainer/domain/engine/fitness.dart';
import 'package:ai_running_trainer/domain/engine/validation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('DIAGNOSTIC: why is there no hard session', (tester) async {
    final out = StringBuffer();
    void say(String s) => out.writeln(s);

    final storage = await TrainerStorage.open();
    final storedProfile = storage.loadProfile();
    final storedRaces = storage.loadRaces();
    final storedGoal = storage.loadGoal();
    final storedStart = storage.loadStartDate();

    say('=== STORED ON DEVICE ===');
    say('profile: ${storedProfile == null ? 'NONE' : '${storedProfile.name}, '
        'months ${storedProfile.monthsRunning}, '
        'days ${storedProfile.daysPerWeek}, '
        'weeklyKm ${storedProfile.estimatedWeeklyKm}'}');
    say('races: ${storedRaces.length}');
    for (final r in storedRaces) {
      say('  ${r.distance.label} ${r.time} on ${r.date.toIso8601String()} '
          '(hr ${r.averageHr}) age ${r.ageInDays(DateTime.now())}d');
    }
    say('goal: ${storedGoal == null ? 'NONE' : '${storedGoal.distance.label} '
        '${storedGoal.date.toIso8601String()} target ${storedGoal.finishTimeGoal}'}');
    say('startDate: ${storedStart?.toIso8601String() ?? 'NONE'}');

    say('');
    say('=== isBeginnerPath STEP BY STEP ===');
    final profile = storedProfile;
    if (profile == null) {
      say('no stored profile — cannot diagnose. Run the app and complete '
          'onboarding first, then re-run this.');
      // ignore: avoid_print
      print(out.toString());
      return;
    }
    // generate() passes the PLAN START date here, not today's date.
    final now = storedStart ?? DateTime.now();
    say('assessFitness given "now" = ${now.toIso8601String()}');
    say('  (that is the plan start date, not today)');
    final fitness = assessFitness(storedRaces, now);
    say('  hasData: ${fitness.hasData}');
    say('  anchor: ${fitness.anchor}');
    say('  vdot: ${fitness.vdot}');
    say('  hasFreshRace: ${fitness.hasFreshRace}');

    say('');
    say('branch 1  !hasData            -> beginner : ${!fitness.hasData}');
    say('branch 2  monthsRunning < 12  -> beginner : '
        '${profile.monthsRunning < 12}  (${profile.monthsRunning})');
    final km = profile.estimatedWeeklyKm;
    final threshold = profile.daysPerWeek * 5.0 * 0.6;
    say('branch 3  km < days*5*0.6     -> beginner : '
        '${km != null && km < threshold}  '
        '(km=$km threshold=$threshold)');
    say('');
    say('VERDICT isBeginnerPath = ${isBeginnerPath(profile, fitness)}');

    say('');
    say('=== GENERATED WEEKS ===');
    final controller = TrainerController(storage);
    await controller.completeOnboarding(
      profile: profile,
      races: storedRaces,
      goal: storedGoal,
      startDate: storedStart ?? DateTime.now(),
    );
    final plan = controller.plan!;
    say('path: ${plan.path}');
    say('directive: suppressQuality=${controller.directive.suppressQuality} '
        'capVolume=${controller.directive.capVolume}');
    var noQuality = 0;
    for (final w in plan.weeks) {
      final q = w.qualityCount;
      if (q == 0) noQuality++;
      final sessions = w.workouts
          .where((s) => s.type.name != 'rest')
          .map((s) => '${s.title}[${s.type.name}]')
          .join(' | ');
      say('w${w.weekNumber.toString().padLeft(2)} '
          '${w.phase.name.padRight(11)} '
          '${w.isCutback ? 'CUTBACK ' : '         '}'
          'quality=$q  $sessions');
    }
    say('');
    say('weeks with no hard session: $noQuality of ${plan.weekCount}');

    // ignore: avoid_print
    print(out.toString());
  });
}
