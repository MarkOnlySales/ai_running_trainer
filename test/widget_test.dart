import 'package:ai_running_trainer/app/controller.dart';
import 'package:ai_running_trainer/app/storage.dart';
import 'package:ai_running_trainer/domain/models/goal.dart';
import 'package:ai_running_trainer/domain/models/plan.dart';
import 'package:ai_running_trainer/domain/models/profile.dart';
import 'package:ai_running_trainer/domain/models/race.dart';
import 'package:ai_running_trainer/domain/models/week_log.dart';
import 'package:ai_running_trainer/main.dart';
import 'package:ai_running_trainer/ui/onboarding/onboarding_screen.dart';
import 'package:ai_running_trainer/ui/plan/plan_screen.dart';
import 'package:ai_running_trainer/ui/plan/details_screen.dart';
import 'package:ai_running_trainer/ui/plan/review_screen.dart';
import 'package:ai_running_trainer/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

RunnerProfile profile({int months = 36, double? km = 40, int days = 4}) =>
    RunnerProfile(
      name: 'Sam',
      age: 34,
      gender: Gender.preferNotToSay,
      monthsRunning: months,
      daysPerWeek: days,
      estimatedWeeklyKm: km,
    );

RaceResult k10(Duration time, {int daysAgo = 30}) => RaceResult(
      distance: RaceDistance.k10,
      time: time,
      date: DateTime.now().subtract(Duration(days: daysAgo)),
    );

GoalRace marathonGoal({int inWeeks = 18}) => GoalRace(
      distance: RaceDistance.marathon,
      date: DateTime.now().add(Duration(days: inWeeks * 7)),
      finishTimeGoal: const Duration(hours: 3, minutes: 40),
      daysPerWeek: 4,
    );

Future<TrainerController> loaded({
  RunnerProfile? p,
  List<RaceResult> races = const [],
  GoalRace? goal,
  bool onboarded = true,
}) async {
  SharedPreferences.setMockInitialValues({});
  final storage = await TrainerStorage.open();
  final controller = TrainerController(storage);
  if (onboarded) {
    await controller.completeOnboarding(
      profile: p ?? profile(),
      races: races,
      goal: goal,
      startDate: DateTime.now(),
    );
  } else {
    await controller.init();
  }
  return controller;
}

Widget app(TrainerController controller) =>
    RunningTrainerApp(controller: controller);

/// Fails the test if the frame laid out with a RenderFlex overflow.
///
/// This is the whole reason the suite runs at a phone width: the previous
/// tests used a 1200x3000 surface, which built every row at a width no real
/// device has, so a layout that breaks on a phone was never exercised.
void expectNoLayoutError(WidgetTester tester) {
  expect(tester.takeException(), isNull);
}

/// Drags the frontmost list until [f] is on screen.
///
/// Several screens here are long lazy `ListView`s, so anything below the fold
/// does not exist in the tree yet. Asserting on it without scrolling finds
/// nothing, which is a test bug rather than an app one.
Future<void> scrollTo(WidgetTester tester, Finder f) async {
  if (f.evaluate().isNotEmpty) {
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    return;
  }
  await tester.dragUntilVisible(
    f,
    find.byType(ListView).last,
    const Offset(0, -200),
  );
  await tester.pumpAndSettle();
}

/// Mounts an onboarded app and navigates to the details screen.
Future<TrainerController> openDetails(
  WidgetTester tester, {
  RunnerProfile? p,
  List<RaceResult> races = const [],
  GoalRace? goal,
}) async {
  final controller = await loaded(p: p, races: races, goal: goal);
  await tester.pumpWidget(app(controller));
  await tester.tap(find.byIcon(Icons.insights_outlined));
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.person_outline));
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  // A phone-sized viewport, deliberately. Everything below asserts on content
  // that has to fit at this width.
  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.physicalSize = const Size(400, 900);
    view.devicePixelRatio = 1.0;
    addTearDown(() {
      view.resetPhysicalSize();
      view.resetDevicePixelRatio();
    });
  });

  group('routing', () {
    testWidgets('a new user is sent to onboarding', (tester) async {
      final controller = await loaded(onboarded: false);
      await tester.pumpWidget(app(controller));
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.byType(PlanScreen), findsNothing);
      expectNoLayoutError(tester);
    });

    testWidgets('an existing user goes straight to their plan', (tester) async {
      final controller = await loaded();
      await tester.pumpWidget(app(controller));
      expect(find.byType(PlanScreen), findsOneWidget);
      expectNoLayoutError(tester);
    });
  });

  group('onboarding', () {
    testWidgets('walks five steps to the review', (tester) async {
      final controller = await loaded(onboarded: false);
      await tester.pumpWidget(app(controller));

      expect(find.text('About you'), findsOneWidget);
      for (final title in [
        'Your running',
        'Race times',
        'A race to train for',
      ]) {
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
        expect(find.text(title), findsOneWidget);
        expectNoLayoutError(tester);
      }

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('All set'), findsOneWidget);
      expect(find.text('Build my plan'), findsOneWidget);
      expectNoLayoutError(tester);
    });

    testWidgets('completing onboarding builds and shows a plan', (tester) async {
      final controller = await loaded(onboarded: false);
      await tester.pumpWidget(app(controller));

      for (var i = 0; i < 4; i++) {
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Build my plan'));
      await tester.pumpAndSettle();

      expect(controller.hasPlan, isTrue);
      expect(find.byType(PlanScreen), findsOneWidget);
      // The app bar shows the week as "W1 / 12".
      expect(find.text('W1'), findsOneWidget);
      expectNoLayoutError(tester);
    });

    testWidgets('the race and goal steps lay out at phone width', (tester) async {
      final controller = await loaded(onboarded: false);
      await tester.pumpWidget(app(controller));

      // Step 3: race times.
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Race times'), findsOneWidget);
      expectNoLayoutError(tester);

      // Step 4: goal, with a distance selected so the extra fields render.
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('10K'));
      await tester.pumpAndSettle();
      expect(find.text('FINISH TIME GOAL'), findsOneWidget);
      expectNoLayoutError(tester);
    });
  });

  group('plan screen', () {
    testWidgets('shows the week, its sessions and rest days', (tester) async {
      final controller = await loaded();
      await tester.pumpWidget(app(controller));

      expect(find.text('W1'), findsOneWidget);
      expect(find.text('THIS WEEK'), findsOneWidget);
      expect(find.text('Long run'), findsOneWidget);
      expectNoLayoutError(tester);

      // Rest days sit below the fold at phone width, which is exactly the
      // sort of thing a lazy ListView will hide from a test.
      await tester.drag(
        find.byType(Scrollable).first,
        const Offset(0, -500),
      );
      await tester.pumpAndSettle();
      expect(find.text('Rest'), findsWidgets);
      expectNoLayoutError(tester);
    });

    testWidgets('the block section is reachable and lays out', (tester) async {
      final controller = await loaded();
      await tester.pumpWidget(app(controller));

      await tester.scrollUntilVisible(
        find.text('THE BLOCK'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expectNoLayoutError(tester);

      // The phase legend sits below the rail and is built lazily. Its text is
      // deliberately not unique — the rail labels its first and last week
      // with the same phase name — so drag until it appears rather than using
      // scrollUntilVisible, which requires a single match.
      for (var i = 0; i < 5 && find.text('Base building').evaluate().isEmpty; i++) {
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -250));
        await tester.pumpAndSettle();
      }
      expect(find.text('Base building'), findsWidgets);
      expectNoLayoutError(tester);
    });

    testWidgets('a race goal renders the countdown at phone width',
        (tester) async {
      final controller = await loaded(
        races: [k10(const Duration(minutes: 45))],
        goal: marathonGoal(),
      );
      await tester.pumpWidget(app(controller));

      expect(find.textContaining('RACE IN'), findsOneWidget);
      expectNoLayoutError(tester);
    });

    testWidgets('tapping a session opens its detail sheet', (tester) async {
      final controller = await loaded();
      await tester.pumpWidget(app(controller));

      await tester.ensureVisible(find.text('Long run'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Long run'));
      await tester.pumpAndSettle();

      expect(find.text('EFFORT'), findsOneWidget);
      expectNoLayoutError(tester);
    });

    testWidgets('the detail sheet fits a long duration', (tester) async {
      final controller = await loaded(
        races: [k10(const Duration(minutes: 45))],
        goal: marathonGoal(),
      );
      await tester.pumpWidget(app(controller));

      await tester.ensureVisible(find.text('Recovery run'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Recovery run'));
      await tester.pumpAndSettle();
      expect(find.text('EFFORT'), findsOneWidget);
      expectNoLayoutError(tester);
    });
  });

  group('review screen', () {
    testWidgets('lists paces, provenance and equivalents', (tester) async {
      final controller = await loaded(races: [k10(const Duration(minutes: 45))]);
      await tester.pumpWidget(app(controller));

      await tester.tap(find.byIcon(Icons.insights_outlined));
      await tester.pumpAndSettle();

      expect(find.byType(ReviewScreen), findsOneWidget);
      expect(find.text('TRAINING PACES'), findsOneWidget);
      expectNoLayoutError(tester);

      await tester.scrollUntilVisible(
        find.text('WHERE THESE COME FROM'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.textContaining('VDOT'), findsOneWidget);
      expectNoLayoutError(tester);
    });
  });

  group('paths', () {
    testWidgets('a beginner gets a base block, not a race plan', (tester) async {
      final controller = await loaded(p: profile(months: 3, km: 12));
      await tester.pumpWidget(app(controller));
      expect(controller.plan!.path, TrainingPath.beginnerBase);
      expect(find.text('/ 12'), findsOneWidget);
    });

    testWidgets('a runner with a goal gets a periodised block', (tester) async {
      final controller = await loaded(
        races: [k10(const Duration(minutes: 45))],
        goal: marathonGoal(),
      );
      expect(
        controller.plan!.path,
        TrainingPath.trainedRace,
      );
    });
  });

  group('goal editing', () {
    testWidgets('a runner with no goal is offered one', (tester) async {
      final controller = await loaded();
      await tester.pumpWidget(app(controller));
      expect(controller.goal, isNull);
      expect(find.text('NO GOAL RACE SET'), findsOneWidget);
      expectNoLayoutError(tester);
    });

    testWidgets('tapping the add-goal card opens the editor', (tester) async {
      final controller = await loaded();
      await tester.pumpWidget(app(controller));

      await tester.tap(find.byKey(const Key('add-goal-card')));
      await tester.pumpAndSettle();

      expect(find.text('Goal race'), findsOneWidget);
      expect(find.text('RACE DISTANCE'), findsOneWidget);
      expectNoLayoutError(tester);
    });

    testWidgets('setting a goal rebuilds the plan around it', (tester) async {
      final controller = await loaded(
        races: [k10(const Duration(minutes: 45))],
      );
      await tester.pumpWidget(app(controller));
      expect(controller.goal, isNull);

      await tester.tap(find.byKey(const Key('add-goal-card')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Marathon'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '3:40:00');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(controller.goal, isNotNull);
      expect(controller.goal!.distance, RaceDistance.marathon);
      expect(controller.goal!.finishTimeGoal, const Duration(hours: 3, minutes: 40));
      expect(controller.plan!.path, TrainingPath.trainedRace);
      // The plan is now anchored on the goal, and the card reflects it.
      expect(find.textContaining('RACE IN'), findsOneWidget);
      expectNoLayoutError(tester);
    });

    testWidgets('an existing goal card opens the editor pre-filled',
        (tester) async {
      final controller = await loaded(
        races: [k10(const Duration(minutes: 45))],
        goal: marathonGoal(),
      );
      await tester.pumpWidget(app(controller));

      expect(find.textContaining('RACE IN'), findsOneWidget);
      await tester.tap(find.byKey(const Key('race-card')));
      await tester.pumpAndSettle();

      expect(find.text('Goal race'), findsOneWidget);
      // Clear is only offered when there is something to clear.
      expect(find.text('Clear'), findsOneWidget);
      expectNoLayoutError(tester);
    });

    testWidgets('clearing the goal returns a base block', (tester) async {
      final controller = await loaded(
        races: [k10(const Duration(minutes: 45))],
        goal: marathonGoal(),
      );
      expect(controller.plan!.goal, isNotNull);

      await tester.pumpWidget(app(controller));
      await tester.tap(find.byKey(const Key('race-card')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();

      expect(controller.goal, isNull);
      expect(controller.plan!.goal, isNull);
      expect(find.text('NO GOAL RACE SET'), findsOneWidget);
      expectNoLayoutError(tester);
    });

    testWidgets('an edited goal survives a reload from storage', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final storage = await TrainerStorage.open();
      final first = TrainerController(storage);
      await first.completeOnboarding(
        profile: profile(),
        races: [k10(const Duration(minutes: 45))],
        startDate: DateTime.now(),
      );
      await first.setGoal(
        GoalRace(
          distance: RaceDistance.half,
          date: DateTime.now().add(const Duration(days: 84)),
          finishTimeGoal: const Duration(hours: 1, minutes: 45),
          daysPerWeek: 5,
        ),
      );

      final second = TrainerController(await TrainerStorage.open());
      await second.init();

      expect(second.goal, isNotNull);
      expect(second.goal!.distance, RaceDistance.half);
      expect(second.goal!.daysPerWeek, 5);
      expect(
        second.goal!.finishTimeGoal,
        const Duration(hours: 1, minutes: 45),
      );
    });
  });

  group('week completion', () {
    testWidgets('marking a week done moves the runner on', (tester) async {
      final controller = await loaded();
      await tester.pumpWidget(app(controller));

      expect(find.text('MARK DONE'), findsOneWidget);
      await tester.tap(find.byKey(const Key('complete-week')));
      await tester.pumpAndSettle();

      expect(controller.progress!.isComplete(0), isTrue);
      // Finishing the week you are on advances you to the next incomplete one.
      expect(controller.currentWeekIndex, 1);
      expect(find.text('W2'), findsOneWidget);
      expectNoLayoutError(tester);
    });

    testWidgets('un-marking a week clears the ones after it', (tester) async {
      final controller = await loaded();
      await tester.pumpWidget(app(controller));

      // Week 1 done from the header.
      await tester.tap(find.byKey(const Key('complete-week')));
      await tester.pumpAndSettle();
      expect(controller.progress!.completedCount, 1);

      // The whole-block list is a vertical list, so it is straightforward to
      // drive. The horizontal week strip is not scrollable by a vertical drag.
      await tester.scrollUntilVisible(
        find.text('ALL WEEKS'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('ALL WEEKS'));
      await tester.pumpAndSettle();
      expect(find.text('The whole block'), findsOneWidget);

      for (final week in [1, 2]) {
        await tester.tap(find.byKey(Key('block-week-$week')));
        await tester.pumpAndSettle();
        expect(controller.progress!.isComplete(week), isTrue);
      }
      expect(controller.progress!.completedCount, 3);

      // Disown week 1. You cannot claim to have finished weeks that were built
      // on one you just disowned.
      await tester.tap(find.byKey(const Key('block-week-0')));
      await tester.pumpAndSettle();

      expect(controller.progress!.completedCount, 0);
      expectNoLayoutError(tester);
    });

    testWidgets('a week built on an unlogged week says so', (tester) async {
      // Start in the past so later weeks are provisional from the start.
      final controller = await loaded();
      await controller.completeOnboarding(
        profile: profile(),
        races: [k10(const Duration(minutes: 45))],
        goal: marathonGoal(),
        startDate: DateTime.now().subtract(const Duration(days: 30)),
      );
      await tester.pumpWidget(app(controller));

      // The runner is put back on week 1, which is not provisional, but the
      // missed-weeks prompt must be present.
      expect(find.textContaining('WEEKS WENT UNLOGGED'), findsOneWidget);
      expectNoLayoutError(tester);
    });

    testWidgets('the missed-weeks prompt opens the whole block',
        (tester) async {
      final controller = await loaded();
      await controller.completeOnboarding(
        profile: profile(),
        races: [k10(const Duration(minutes: 45))],
        goal: marathonGoal(),
        startDate: DateTime.now().subtract(const Duration(days: 30)),
      );
      await tester.pumpWidget(app(controller));

      await tester.tap(find.text('See the whole block'));
      await tester.pumpAndSettle();
      expect(find.text('The whole block'), findsOneWidget);
      expectNoLayoutError(tester);
    });

    testWidgets('completion survives a reload', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final storage = await TrainerStorage.open();
      final first = TrainerController(storage);
      await first.completeOnboarding(
        profile: profile(),
        races: const [],
        startDate: DateTime.now(),
      );
      await first.markWeekComplete(0);

      SharedPreferences.resetStatic();

      final second = TrainerController(await TrainerStorage.open());
      await second.init();
      await tester.pumpWidget(app(second));
      await tester.pumpAndSettle();

      // Week 1 came back as done, so the runner is on week 2.
      expect(second.progress!.isComplete(0), isTrue);
      expect(find.text('W2'), findsOneWidget);
      expectNoLayoutError(tester);
    });
  });

  group('week logging', () {
    testWidgets('the log sheet opens and records a difficulty', (tester) async {
      final controller = await loaded();
      await tester.pumpWidget(app(controller));

      await tester.scrollUntilVisible(
        find.byKey(const Key('log-week')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('log-week')));
      await tester.pumpAndSettle();

      expect(find.text('Log week 1'), findsOneWidget);

      // The sheet is taller than the viewport, so the difficulty control has
      // to be scrolled into view before it can be driven.
      await tester.scrollUntilVisible(
        find.byKey(const Key('difficulty-9')),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expectNoLayoutError(tester);

      await tester.tap(find.byKey(const Key('difficulty-9')));
      await tester.pumpAndSettle();

      // Save sits below the fold of the sheet on a 900px viewport.
      await tester.scrollUntilVisible(
        find.text('Save log'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Save log'));
      await tester.pumpAndSettle();

      final log = controller.progress!.logFor(0);
      expect(log.difficulty, 9);
      expectNoLayoutError(tester);
    });

    testWidgets('ticking done in the sheet marks the week', (tester) async {
      final controller = await loaded();
      await tester.pumpWidget(app(controller));

      await tester.scrollUntilVisible(
        find.byKey(const Key('log-week')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('log-week')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('I completed this week'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save log'));
      await tester.pumpAndSettle();

      expect(controller.progress!.isComplete(0), isTrue);
    });

    testWidgets('a run of hard weeks proposes holding volume', (tester) async {
      final controller = await loaded();
      // Three weeks logged at 8+ is the pattern the product cares about.
      for (var i = 0; i < 3; i++) {
        await controller.logWeek(
          i,
          WeekLog(completed: true, sessionsDone: 4, difficulty: 8 + i % 2),
        );
      }
      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      expect(controller.progress!.looksTooHard, isTrue);
      expect(find.byKey(const Key('accept-cap-volume')), findsOneWidget);
      expect(find.byKey(const Key('decline-cap-volume')), findsOneWidget);
      expect(find.text('SUGGESTED'), findsWidgets);
      expectNoLayoutError(tester);
    });

    testWidgets('accepting a proposal applies it to the plan', (tester) async {
      final controller = await loaded();
      for (var i = 0; i < 3; i++) {
        await controller.logWeek(
          i,
          WeekLog(completed: true, sessionsDone: 4, difficulty: 9),
        );
      }
      final before = controller.plan!.weeks[0].targetVolumeKm;
      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('accept-cap-volume')));
      await tester.pumpAndSettle();

      expect(controller.coachState.isAccepted('cap-volume'), isTrue);
      expect(controller.directive.capVolume, isTrue);
      // The proposal is gone, replaced by the summary of what is in force.
      expect(find.byKey(const Key('accept-cap-volume')), findsNothing);
      expect(find.text('YOUR ADJUSTMENTS'), findsOneWidget);
      // And the past was not rewritten.
      expect(controller.plan!.weeks[0].targetVolumeKm, before);
      expectNoLayoutError(tester);
    });

    testWidgets('declining hides the proposal', (tester) async {
      final controller = await loaded();
      for (var i = 0; i < 3; i++) {
        await controller.logWeek(
          i,
          WeekLog(completed: true, sessionsDone: 4, difficulty: 9),
        );
      }
      final after = controller.plan!.weeks[2].targetVolumeKm;
      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('decline-cap-volume')));
      await tester.pumpAndSettle();

      expect(controller.coachState.isAccepted('cap-volume'), isFalse);
      expect(find.byKey(const Key('accept-cap-volume')), findsNothing);
      expect(find.text('YOUR ADJUSTMENTS'), findsNothing);
      // The plan is unchanged — declining really means declining.
      expect(controller.plan!.weeks[2].targetVolumeKm, after);
      expectNoLayoutError(tester);
    });

    testWidgets('an accepted change can be put back', (tester) async {
      final controller = await loaded();
      for (var i = 0; i < 3; i++) {
        await controller.logWeek(
          i,
          WeekLog(completed: true, sessionsDone: 4, difficulty: 9),
        );
      }
      final before = controller.plan!.weeks[2].targetVolumeKm;
      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('accept-cap-volume')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('revoke-adjustments')));
      await tester.pumpAndSettle();

      expect(controller.directive.isEmpty, isTrue);
      expect(controller.plan!.weeks[2].targetVolumeKm, before);
      expectNoLayoutError(tester);
    });

    testWidgets('no proposal for a couple of hard weeks', (tester) async {
      final controller = await loaded();
      for (var i = 0; i < 2; i++) {
        await controller.logWeek(
          i,
          const WeekLog(completed: true, sessionsDone: 4, difficulty: 9),
        );
      }
      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('accept-cap-volume')), findsNothing);
      expectNoLayoutError(tester);
    });

    testWidgets('coach decisions survive a reload', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final storage = await TrainerStorage.open();
      final first = TrainerController(storage);
      await first.completeOnboarding(
        profile: profile(),
        races: const [],
        startDate: DateTime.now(),
      );
      for (var i = 0; i < 3; i++) {
        await first.logWeek(
          i,
          const WeekLog(completed: true, sessionsDone: 4, difficulty: 9),
        );
      }
      final proposal = first.outstandingProposals.first;
      await first.acceptProposal(proposal);

      SharedPreferences.resetStatic();

      final second = TrainerController(await TrainerStorage.open());
      await second.init();
      expect(second.coachState.isAccepted('cap-volume'), isTrue);
      expect(second.directive.capVolume, isTrue);
    });

    testWidgets('a logged difficulty shows on the week', (tester) async {
      final controller = await loaded();
      await controller.logWeek(
        0,
        const WeekLog(completed: false, sessionsDone: 2, difficulty: 9),
      );
      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      expect(find.textContaining('too hard'), findsOneWidget);
      expectNoLayoutError(tester);
    });
  });

  testWidgets('reset returns the user to onboarding', (tester) async {
    final controller = await loaded();
    await tester.pumpWidget(app(controller));

    await tester.tap(find.byIcon(Icons.insights_outlined));
    await tester.pumpAndSettle();
    // Start over lives on the details screen, alongside the two other ways to
    // redo a plan, rather than being buried on the review screen.
    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();
    // The plan actions sit below three cards of detail, so they are off-screen
    // at 400x900 and have to be scrolled to.
    await tester.ensureVisible(find.byKey(const Key('action-start-over')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('action-start-over')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Start over'));
    await tester.pumpAndSettle();

    expect(controller.hasPlan, isFalse);
    expect(find.byType(OnboardingScreen), findsOneWidget);
  });

  testWidgets('the plan survives a reload from storage', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = await TrainerStorage.open();
    final first = TrainerController(storage);
    await first.completeOnboarding(
      profile: profile(),
      races: [k10(const Duration(minutes: 45))],
      startDate: DateTime.now(),
    );

    final second = TrainerController(await TrainerStorage.open());
    await second.init();

    expect(second.hasPlan, isTrue);
    expect(second.plan!.weekCount, first.plan!.weekCount);
    expect(second.profile!.name, 'Sam');
  });

  group('your details', () {
    testWidgets('shows what the plan thinks about the runner', (tester) async {
      await openDetails(tester, races: [k10(const Duration(minutes: 45))]);
      expect(find.text('Your details'), findsOneWidget);
      expect(find.text('Sam'), findsOneWidget);
      expect(find.text('40 km'), findsOneWidget);
      await scrollTo(tester, find.text('45:00'));
      expect(find.text('45:00'), findsOneWidget, reason: 'the 10K result');
      expectNoLayoutError(tester);
    });

    testWidgets('says when the weekly volume was never supplied',
        (tester) async {
      // The runner is told the plan is guessing, because a guess that quietly
      // over-prescribes is the whole bug this screen exists to let them fix.
      await openDetails(tester, p: profile(km: null));
      expect(find.text('Estimated from race times'), findsOneWidget);
      await scrollTo(tester, find.textContaining('overestimate a runner who'));
      expect(
        find.textContaining('overestimate a runner who'),
        findsOneWidget,
      );
      expectNoLayoutError(tester);
    });

    testWidgets('offers the three ways to redo a plan', (tester) async {
      await openDetails(tester);
      for (final key in const [
        Key('action-edit-details'),
        Key('action-new-plan'),
        Key('action-start-over'),
      ]) {
        await scrollTo(tester, find.byKey(key));
        expect(find.byKey(key), findsOneWidget, reason: '$key');
      }
      expectNoLayoutError(tester);
    });

    testWidgets('start a new plan needs confirming, and can be cancelled',
        (tester) async {
      final controller = await openDetails(tester);
      final start = controller.startDate;
      final logged = controller.progress!.completedCount;

      await scrollTo(tester, find.byKey(const Key('action-new-plan')));
      await tester.tap(find.byKey(const Key('action-new-plan')));
      await tester.pumpAndSettle();
      expect(find.text('Start a new plan?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        controller.startDate,
        start,
        reason: 'cancelling must change nothing at all',
      );
      expect(controller.progress!.completedCount, logged);
    });

    testWidgets('starting a new plan clears the log but keeps the runner',
        (tester) async {
      final controller = await openDetails(tester, races: [
        k10(const Duration(minutes: 45)),
      ], goal: marathonGoal());
      await controller.markWeekComplete(0);
      await tester.pumpAndSettle();
      expect(controller.progress!.completedCount, 1);

      await scrollTo(tester, find.byKey(const Key('action-new-plan')));
      await tester.tap(find.byKey(const Key('action-new-plan')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Start new plan'));
      await tester.pumpAndSettle();

      expect(controller.progress!.completedCount, 0);
      expect(controller.profile, isNotNull);
      expect(controller.races, isNotEmpty);
      expect(find.byType(DetailsScreen), findsNothing);
    });

    testWidgets('editing details keeps the weeks already logged',
        (tester) async {
      final controller = await openDetails(
        tester,
        races: [k10(const Duration(minutes: 45))],
      );
      await controller.markWeekComplete(0);
      await tester.pumpAndSettle();
      expect(controller.progress!.completedCount, 1);

      await tester.tap(find.byKey(const Key('edit-profile')));
      await tester.pumpAndSettle();

      final field = find.byKey(const Key('profile-weekly-km'));
      await scrollTo(tester, field);
      await tester.enterText(field, '12');
      await tester.pumpAndSettle();

      expect(controller.profile!.estimatedWeeklyKm, 12);
      expect(
        controller.progress!.completedCount,
        1,
        reason: 'an edit rebuilds the plan but must not discard progress',
      );
      expectNoLayoutError(tester);
    });

    testWidgets('the editor can clear a field it previously set',
        (tester) async {
      // A form that can set a value but never clear one cannot represent the
      // truth: "I removed this" and "I never had this" are different answers.
      final controller = await openDetails(tester);
      await tester.tap(find.byKey(const Key('edit-profile')));
      await tester.pumpAndSettle();
      final field = find.byKey(const Key('profile-weekly-km'));
      await scrollTo(tester, field);

      await tester.enterText(field, '30');
      await tester.pumpAndSettle();
      expect(controller.profile!.estimatedWeeklyKm, 30);

      await tester.enterText(field, '');
      await tester.pumpAndSettle();
      expect(controller.profile!.estimatedWeeklyKm, isNull);
    });
  });

  group('the wizard steps do not repeat each other', () {
    // Regression: the first version of the extracted editor rendered *every*
    // field regardless of which step it was on, and hardcoded the step heading.
    // Step 2 was step 1 minus the name box — same title, same age question, and
    // every history field as well. A shared widget is only worth sharing if it
    // can render a part of itself.
    Future<void> goToStep(WidgetTester tester, int step) async {
      final controller = await loaded(onboarded: false);
      await tester.pumpWidget(app(controller));
      for (var i = 0; i < step; i++) {
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
      }
    }

    testWidgets('step 1 asks who is running', (tester) async {
      await goToStep(tester, 0);
      expect(find.text('About you'), findsOneWidget);
      expect(find.byKey(const Key('profile-name')), findsOneWidget);
      expect(find.text('AGE'), findsOneWidget);
      expect(find.text('GENDER'), findsOneWidget);
      expect(
        find.byKey(const Key('profile-weekly-km')),
        findsNothing,
        reason: 'mileage belongs to the running step, not this one',
      );
      expect(
        find.text('HOW LONG HAVE YOU BEEN RUNNING REGULARLY?'),
        findsNothing,
      );
      expectNoLayoutError(tester);
    });

    testWidgets('step 2 asks what and how much they run', (tester) async {
      await goToStep(tester, 1);
      expect(find.text('Your running'), findsOneWidget);
      expect(find.text('AGE'), findsNothing, reason: 'already asked on step 1');
      expect(find.byKey(const Key('profile-name')), findsNothing);
      expect(
        find.text('HOW LONG HAVE YOU BEEN RUNNING REGULARLY?'),
        findsOneWidget,
      );
      expect(
        find.text('HOW MANY DAYS A WEEK DO YOU RUN NOW?'),
        findsOneWidget,
      );
      expectNoLayoutError(tester);
    });

    testWidgets('the two steps show different headings', (tester) async {
      await goToStep(tester, 0);
      final first = find.text('About you');
      expect(first, findsOneWidget);
      expect(find.text('Your running'), findsNothing);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(first, findsNothing, reason: 'the step 1 heading must not persist');
      expect(find.text('Your running'), findsOneWidget);
    });

    testWidgets('the two steps share no field', (tester) async {
      // A field appearing on both steps is the actual complaint, so assert on
      // the set of labels rather than on any one of them.
      const fields = [
        'AGE',
        'GENDER',
        'HOW LONG HAVE YOU BEEN RUNNING REGULARLY?',
        'HOW MANY DAYS A WEEK DO YOU RUN NOW?',
        'ROUGHLY HOW MANY KM A WEEK DO YOU RUN?',
        'HEIGHT AND WEIGHT (OPTIONAL)',
      ];
      final seen = <String>{};
      for (var step = 0; step < 2; step++) {
        await goToStep(tester, step);
        for (final field in fields) {
          if (find.text(field).evaluate().isNotEmpty) {
            expect(
              seen.add(field),
              isTrue,
              reason: '"$field" is on both step ${step + 1} and an earlier one',
            );
          }
        }
      }
      expect(seen.length, fields.length,
          reason: 'every field should be on exactly one step');
    });
  });

  group('the edit form and the wizard ask the same questions', () {
    // The reason ProfileEditor and RaceEditor are shared components rather than
    // one plus a copy. If the wizard grows a field the editor does not have, the
    // two start collecting different information, and nobody notices until the
    // data is already wrong.
    Future<void> openWizard(WidgetTester tester) async {
      final controller = await loaded(onboarded: false);
      await tester.pumpWidget(app(controller));
    }

    Future<void> openEditor(WidgetTester tester) async {
      await openDetails(tester);
      await tester.tap(find.byKey(const Key('edit-profile')));
      await tester.pumpAndSettle();
    }

    testWidgets('the wizard asks for weekly volume', (tester) async {
      await openWizard(tester);
      // Step 2 of 5 — the running-history step.
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await scrollTo(tester, find.byKey(const Key('profile-weekly-km')));
      expect(find.byKey(const Key('profile-weekly-km')), findsOneWidget);
      expectNoLayoutError(tester);
    });

    testWidgets('the editor asks for weekly volume', (tester) async {
      await openEditor(tester);
      await scrollTo(tester, find.byKey(const Key('profile-weekly-km')));
      expect(find.byKey(const Key('profile-weekly-km')), findsOneWidget);
      expectNoLayoutError(tester);
    });

    testWidgets('the wizard asks for every race distance', (tester) async {
      await openWizard(tester);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      for (final d in RaceDistance.values) {
        final field = find.byKey(Key('race-field-${d.name}'));
        await scrollTo(tester, field);
        expect(field, findsOneWidget, reason: d.label);
      }
      expectNoLayoutError(tester);
    });

    testWidgets('the editor asks for every race distance', (tester) async {
      await openDetails(tester);
      await scrollTo(tester, find.byKey(const Key('edit-races')));
      await tester.tap(find.byKey(const Key('edit-races')));
      await tester.pumpAndSettle();
      for (final d in RaceDistance.values) {
        final field = find.byKey(Key('race-field-${d.name}'));
        await scrollTo(tester, field);
        expect(field, findsOneWidget, reason: d.label);
      }
      expectNoLayoutError(tester);
    });
  });

  group('theme', () {
    testWidgets('uses the intended dark surfaces and brand', (tester) async {
      final controller = await loaded();
      await tester.pumpWidget(app(controller));

      final ctx = tester.element(find.byType(PlanScreen));
      final scheme = Theme.of(ctx).colorScheme;

      expect(scheme.brightness, Brightness.dark);
      expect(Theme.of(ctx).scaffoldBackgroundColor, AppColors.bg);
      expect(Theme.of(ctx).scaffoldBackgroundColor, const Color(0xFF0E0D0D));
      expect(scheme.primary, AppColors.brand);
      expect(scheme.primary, const Color(0xFFFF3600));
      expect(scheme.secondary, AppColors.brandAccent);
      expect(scheme.secondary, const Color(0xFFFE7A0D));
    });

    test('zone ramp keeps easy cool and hard hot', () {
      // The ramp is the thing that stops the plan reading as a rainbow, and
      // keeps easy running (most of the week) visually recessive.
      expect(
        ZonePalette.of(IntensityZone.recovery).computeLuminance(),
        lessThan(ZonePalette.of(IntensityZone.easy).computeLuminance()),
      );
      expect(
        ZonePalette.of(IntensityZone.threshold),
        isNot(ZonePalette.of(IntensityZone.easy)),
      );
      // Nothing in the ramp may equal the brand, or hard sessions stop
      // reading as "the important one".
      for (final z in IntensityZone.slowestFirst) {
        if (z == IntensityZone.interval) continue; // intentionally brand
        expect(ZonePalette.of(z), isNot(AppColors.brand));
      }
    });
  });
}
