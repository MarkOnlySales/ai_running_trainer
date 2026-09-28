# AGENTS.md

## Project

Flutter running-plan generator (`ai_running_trainer`). Flutter 3.47.1 / Dart 3.13.1. Metric units.
Only third-party dependency is `shared_preferences`; the typeface is bundled, not fetched.

## Commands

```bash
flutter pub get
flutter test                        # 501 unit + widget, mocked storage
flutter test integration_test -d emulator-5554   # 12 on-device, REAL storage
flutter analyze                     # must be clean
flutter build web --release
flutter build apk --profile         # NOT --debug, see Android notes
```

To view it: `python -m http.server 8732 --directory build\web`, then open Edge. `flutter run -d edge`
exits as soon as the debug connection drops, so it is not a reliable way to leave the app on screen.

## Architecture

```
lib/
  domain/           PURE DART — must not import package:flutter
    models/         profile, race, goal, plan, week_log, plan_directive
    engine/         vdot, riegel, zones, fitness, volume, validation
    plan/           generate.dart (entry), beginner_plan, race_plan
    progress.dart   completion, adherence and orientation over a plan
    coaching.dart   pure proposals from logged experience
    units.dart      Pace, formatting, clampD/clampI
  app/              controller.dart (ChangeNotifier), storage.dart
  ui/
    theme.dart      AppColors, ZonePalette, AppType, shared components
    goal/           goal_editor.dart — the goal form, shared
    onboarding/, plan/, profile/
  main.dart
assets/fonts/       Barlow 400/500/600/700 + OFL.txt
test/domain/        the real suite — see per-file counts
test/widget_test.dart  runs at 400x900
```

`generate({profile, races, goal, startDate})` is the single entry point. The plan is a **pure
function** of those four inputs and is never persisted — `TrainerController` regenerates it on load
so plan and profile cannot drift apart.

## Coach proposals (adaptation)

`domain/coaching.dart` turns logged experience into proposals. **Nothing is ever applied
automatically** — the product premise is "never too hard", which is a promise about the runner's
experience, so the runner decides the plan changes. A silent rewrite is nagging with extra steps.

- `propose(PlanProgress)` is pure and returns 0–2 candidates:
  - `cap-volume` when `looksTooHard` (≥3 weeks rated 8+). Holds volume flat from the **first
    incomplete week**, so completed weeks keep their shape — the past is not rewritten.
  - `fewer-days` when `looksUnderserved` (adherence <70% *and* nothing felt hard). That's a schedule
    problem, not a fitness one, so the answer is less work, not more. Floors at 3 days.
- `PlanDirective` is passed into `generate()` as an explicit input, so the plan stays pure.
- **Declining is keyed on the hard-week count, not a boolean.** Declining after three hard weeks
  still re-surfaces if a fourth appears — staying silent while it gets worse is the wrong default.
- **Every accepted change is reversible** via `revokeProposal`. Accepting must not be a trap.
- `typicalPrescribedSessions` uses the **mode** across logged weeks, not the last week: a race week
  prescribes two sessions and a cutback fewer, so either would misrepresent what's being asked.
- Cutbacks and the taper still apply while the cap holds.

## App name

User-visible name is **AI Running Trainer**, and it is set in five places, not one:
`web/manifest.json`, `android/app/src/main/AndroidManifest.xml` (`android:label`),
`ios/Runner/Info.plist` (`CFBundleDisplayName` + `CFBundleName`),
`windows/runner/Runner.rc` (`FileDescription` + `ProductName`), and
`pubspec.yaml` `description`.

**The Dart package name is deliberately still `ai_running_trainer`.** Renaming it would rewrite
every import in 20+ files for zero user-visible benefit. Do not "tidy" it up.

`applicationId` is still `com.example.ai_running_trainer` and **blocks any store submission** — the
user chose to defer it. A reverse-domain ID is needed and it cannot be changed after publication.

## Editing details, and the three ways to redo a plan

**Profile and race times have always been persisted** — `storage.dart` writes all six inputs. The gap
was that only the *goal* was editable, because `setGoal` was the controller's only mutation.
`setProfile`, `setRaces` and `restartPlan` now join it.

**`estimatedWeeklyKm` was a model field the form never asked for**, so it was always null and the plan
seeded from `_impliedVolume(fitness)` — a marathon-pace guess. A 52:25 10K implies ~31 km/week, which
was being handed to a runner doing 15 km on three days. It is now an optional question on the
running-history step, and the details screen says out loud when the guess is in use.

**`copyWith` cannot express "clear this".** `Optional<T>` in `models/profile.dart` distinguishes an
omitted argument from an explicit null. Without it, a form can set a value but never clear one, and
"I removed this" silently becomes "I never had this". `RunnerProfile.cleared(...)` is the readable
wrapper over the three nullable fields.

- **An edit keeps logged weeks.** The start date does not move, so `weekKey`-based completion carries
  over. Same property that makes `setGoal` safe.
- **A restart clears them.** New start dates mean new keys, and carrying old weeks across would credit
  a fresh block with work done in the last one. Coach state is cleared too — an accepted cap was a
  judgement about the block that just ended.

**`ProfileEditor` and `RaceEditor` are shared components**, composed by both the wizard and the details
screen, exactly as `GoalEditor` already was. `Pill`, `Counter` and `FieldLabel` moved to `theme.dart`
because they had three private copies. `formatTimeInput`/`parseTimeInput`/`formatDate` moved to
`domain/units.dart` — pure formatting with no Flutter dependency, duplicated in three files.

**A shared widget must be able to render a *part* of itself.** The first extraction gave
`ProfileEditor` a `showName` boolean and left it rendering every field, so wizard step 2 was step 1
minus the name box — same heading, the same age question, and every history field as well. `ProfileSection`
(aboutYou / runningHistory / all) is the fix: a boolean cannot describe "the other half". There is a
test asserting the two steps share no field. **Extracting a form is not the same as parameterising it** —
check that each consumer sees what it should.

**Destructive actions must pop before they mutate.** Clearing the plan turns every screen that reads
one into a loading state, so a screen left on the stack becomes an infinite spinner over the
onboarding form. Both destructive actions use `popUntil((r) => r.isFirst)` *then* mutate. This was a
real bug, caught by a `pumpAndSettle` timeout in the widget suite.

## The long run must be the longest run

**Found via a real report, not a hypothetical.** A runner with two years' training, three days a
week, 15 km a week, a 24:10 5K and a 52:25 10K was given a **3 km long run and 4.9 km easy runs**.
Four separate faults, all now fixed and pinned in `test/domain/regression_real_runner_test.dart`:

- **`isBeginnerPath` used an absolute 24 km/week threshold.** A three-day runner cannot reach that
  without already doing the long run it was gating, so a two-year athlete was routed to a beginner
  block. The volume gate is now **scaled to days per week**, and can only demote someone who *has*
  race data — without an anchor race there are no paces to derive, so no-race-data is always the
  beginner path.
- **The long run's share was a flat 30%.** Below four run days that is arithmetically impossible to
  keep the long run longest: the remainder splits across fewer days, so each easy day exceeds it.
  `longRunShare` is now 60% / 45% / 30% for 2 / 3 / 4+ days.
- **`maxLongRunFraction` was a flat 32% and sat *below* the 30% target**, so `enforceSafety` silently
  undid the generator. `maxLongRunFractionFor` is now day-aware and always sits above
  `longRunShare` — there is a test asserting exactly that coupling.
- **The share cap is a fixed point, not a single trim.** The long run is part of the total it is
  measured against, so the requirement is `L ≤ f(R + L)`, i.e. `L ≤ f·R/(1−f)`. Capping to
  `f·(R+L)` instead leaves it fractionally over its own cap.

**The related lesson: a 3-day week cannot host a 30% long run, and flat constants hide it.** Any
per-session constant must be checked against the smallest week that can contain it. `easyRunCapKm`
and `qualityDistanceKm` exist for the same reason — a flat 9 km tempo was 57% of a 15 km week, and
an 18 km *recovery run* appeared once a long run hit its distance cap.

## A week's reported volume is what its sessions prescribe

`enforceSafety` normalises `targetVolumeKm` to the sum of the workouts, unconditionally, and
normalises *before* the long-run cap so the two cannot disagree. Generators build a workout list and
then trim it — via `applyDayConstraint`, the race-week shakeout, the distance cap — so a target
derived from the pre-trim list is a budget the runner cannot meet. A peak week once prescribed two
quality sessions while budgeting for one: 8 km more running than the plan claimed.

`beginner_plan.dart` must call `applyDayConstraint` **before** computing the volume. `race_plan.dart`
must route race weeks through `enforceSafety` too. `plan_test.dart` asserts
`closeTo(targetVolumeKm, runVolumeKm)` across ten plan shapes — that assertion is the guard.

## Heart rate is an annotation, never an input

`RaceResult.averageHr` is `int?`, serialized only when present. It reaches **no** part of plan
generation — not `vdotFor`, not `riiegel`, not `zoneAnchorPace`. Three notes come off it, all
arithmetic on the runner's own data:

- **Goal-realism caveat** (in `validation.dart`): their anchor race was run at pace X on HR H; if the
  goal pace is >5% faster, say it will demand more than they have sustained. `FlagSeverity.info` only.
- **Out-of-band sanity** (in `fitness.dart`): wide per-distance bounds, a 5K at 205 is a typo. Error
  detection, not zone boundaries.
- **Mixed devices**: some races with HR and some without is disclosed.

**`test/domain/heart_rate_guard_test.dart` is the enforcement.** It asserts a plan generated with and
without HR is identical — volumes, session distances, every zone's pace, VDOT, and the flag set. It
was written *before* the field existed and has been verified to fail when HR is wired into
`vdotFor`. The field's doc comment points at it. If you add a `plannedDistanceKm` to `Workout` and
want the same guarantee, copy the pattern rather than trusting the comment.

## Per-session logging, bounded by the plan

`SessionLog { dayOfWeek, felt, actualKm? }` nested in `WeekLog`, **one per prescribed session, capped
at `maxSessionsPerWeek` (7)**. Phase 5 rejected a per-run log as unbounded; that objection is about
free-form history, not this. A 20-week block is ~140 records. `sessionsDone`/`actualKm` on `WeekLog`
are **not** removed — `looksUnderserved` and `volumeAdherence` consume them.

- **`Workout.weekday` exists so a session log can be matched to the session it refers to.** Without
  it, "the tempo was hard" and "the long run was hard" are indistinguishable — two problems with
  opposite fixes. Set by `attachWeekdays(workouts, pattern)` in `volume.dart`, once per generator,
  because a new session type forgetting to attach its own day fails *silently*.
  **`enforceSafety` rebuilds the long run and must carry `weekday` across** — losing it there would
  detach a capped long run from its day, which is precisely the signal this feature produces.
- **`markWeekComplete` keeps `sessions`.** It is still authoritative for the *self-reported* week
  fields (`clearedForQuickDone`), because stale self-report is what makes the button unpredictable.
  Per-session records are what the runner actually did and are the most expensive data here. Un-marking
  still wipes everything.
- **One three-state tap, in the session detail sheet** — a place the runner already opens. A row of
  controls on the week itself would be 4–7 taps and would not get done on bad weeks.
- **Unrecorded is neutral, never bad.** `observedIntensity` returns null when nothing is recorded.
  `observedIntensity` lives in `progress.dart` (not `generate.dart`) because `validate` runs *before*
  the plan exists and both callers need it — same shape as the existing `adherenceByWeek`.

## `drop-quality`: a more specific answer than `cap-volume`

`PlanDirective.suppressQuality` removes hard sessions and leaves long runs and easy days alone. It
fires at **3+ individual hard quality sessions**, not 3 weeks — a week can hold two, and the two units
are not the same evidence. Two hard days is a bad week, not a miscalibration.

It is safe by construction: hard work becomes easy, so `easyFraction` can only rise. Asserted. Total
weekly mileage may drift a couple of percent either way (the unsuppressed week loses volume to the cap
that keeps quality shorter than the long run); the invariant tested is `hardVolumeKm == 0`, not an
exact total.

`slow-down` is informational and changes nothing — it fires at 4+ hard *easy-day* sessions and says
the prescribed pace may be too fast, because that is usually a pace to hold rather than a plan to
change.

## A trained plan must contain hard sessions — enforced

**Found via a second real report.** A runner with a 1:56 half marathon, a 52:25 10K, 35 km a week,
four days a week and a 10K goal in February was given twelve weeks of `Easy | Easy | Long` and no
hard sessions at all.

**Cause: `monthsRunning` was stored as `3`.** The runner meant three *years*. The experience counter
was a bare month stepper with **no unit stated anywhere**, and "3" is a natural answer to "how long
have you been running" if you think in years. `isBeginnerPath` read three months, took the
`monthsRunning < 12` branch, and returned the beginner base block — which has **zero quality sessions
by design**. Everything else in the profile was correct and could not save them.

- The counter now speaks in **years**, and answers in the same unit it asks
  (`ProfileEditor._yearsRunningLabel`). An 18-month history shows as 2 years, because rounding *down*
  would put someone on the wrong side of the 12-month gate.
- **The volume gate no longer demotes on its own.** A single self-reported number must not override
  months of training plus race data.
- `test/domain/hard_session_invariant_test.dart` asserts **a trained plan carries at least one tempo
  or interval in every non-cutback, non-taper week**, at 3/4/5/6 days a week, base and race blocks —
  and that the beginner block has none, so the two paths are distinguishable by construction. That
  assertion is the guard, and it did not exist before this bug.

**The lesson, and it repeats last session's: two wrong diagnoses in a row, both from reading the
source instead of the state.** The app could not tell the runner either — a beginner route renders
identically to a deliberately all-easy plan. When a rendering ambiguity hides the cause, instrument
the real stored state. Both this bug and the earlier long-run bug came from the runner's numbers,
never from a test; when a report contradicts the code, the stored data wins.

Still open, unchanged by this fix:

- **Without a goal race, intervals are structurally unreachable.** `buildTrainedBasePlan` sets
  `phases = List.filled(12, PlanPhase.base)`, and `_quality` only emits intervals in
  `PlanPhase.specific`. Twelve identical tempos.
- **The week view does not say when a plan has no hard sessions**, so a beginner route reads as a
  design choice rather than a routing outcome. This is what made the bug invisible to the runner.
- **`suppressQuality` is blunt at 3 days a week**, where the tempo is the only quality session. The
  beginner-block "zero quality is safe" property covers a *starting* block, not an end state for a
  trained runner.
- **No 400m or 1000m rep formats** — `intervalRep`/`intervalRecovery` are hardcoded to 3 min / 3 min.

## The 90% rule (reactive volume curve)

`generate()` takes `weekLogs` as an **explicit input**, so the plan is still a pure function — the
logs are data, not hidden state. `TrainerController.logWeek` calls `_rebuild()`; without that the
curve silently never fires. There is a regression test for it.

- `minimumAdherenceToProgress = 0.9`. A week that fell short **holds the next week flat** instead
  of increasing it.
- **The hold is local, not cumulative.** Each week depends only on its immediate predecessor, so
  missing one week and then doing the next resumes the build from there. A running total would
  flatten the entire remaining block for one bad week.
- **A week with no record is unknown, not failed.** It must not block growth, or a plan generated for
  someone who has not started logging would never build at all.
- Prescribed sessions come from the day pattern, not from a generated plan — reading run counts off a
  plan that does not exist yet would be circular.
- `markWeekComplete` is **authoritative, not a merge**: it sets a clean completed state and discards
  stale partial detail. A predictable button beats one whose effect depends on invisible prior state.
  Use the log sheet to keep detail alongside "completed".
- Cutbacks and the taper still apply while progression is held, and the taper still descends from a
  held peak.

## Week log (per-week, not per-run)

**The scope decision:** per-week. A per-run log grows without bound and would eventually force a
real database; per-week keeps a few dozen small records in `shared_preferences`, which is the right
tool at this size. The trade-off is real: adaptation is coarser — you learn a week was too hard, not
*which* session in it was.

`WeekLog` (`domain/models/week_log.dart`): `completed`, `actualKm`, `sessionsDone`, `difficulty`
(1–10), `note`. Every field optional. `difficulty` is the important one — `completed` answers "did
you do it", `difficulty` answers "was it too much", and a runner ticking every box while grinding is
following a plan that is too hard for them.

- **Keys are week-start dates, not week numbers** — see below.
- `markWeekComplete(false)` clears the week's own data as well as everything after it. A
  half-recorded incomplete week produces misleading adherence figures.
- `PlanProgress.looksTooHard` needs **≥3 weeks rated 8+** and an average ≥7. The threshold is
  deliberately demanding: one hard week is a bad week, three is a miscalibrated plan.
- Adherence getters return **null, not 0**, when nothing is recorded. "No data" must not read as
  "0% adherence".
- `loadWeekLogs` migrates the older `completedWeeks` boolean-list format and skips individual
  unreadable entries rather than losing the whole history.

## Week completion

Completion is keyed on `PlanWeek.startDate` (ISO `yyyy-MM-dd` via `weekKey`), **not** on week number —
the plan is a pure function of the profile, so a goal change regenerates it and "week 5" can mean a
different session afterwards. Keying on the date is what lets a goal change stop discarding
completed weeks. See `domain/progress.dart`.

Rules that are easy to get wrong:

- **`missedWeekCount` is strictly *before* the current week.** The week in progress is not missed —
  on day one of week 1, nothing is missed.
- **`suggestedWeekIndex` never shows a completed week.** A runner who finished four weeks sees week
  5 even if the calendar says week 2. This replaced a trap where returning after a month dumped you
  on week 5 of a block you never started.
- **Un-marking a week also clears every week after it.** You cannot claim to have finished weeks
  built on one you just disowned.
- `PlanProgress` takes an injectable `now` so the calendar logic is testable without a real clock.
- The week strip in the plan screen is **horizontally** scrollable — a vertical `drag` will not
  scroll it. Use the "ALL WEEKS" route (a vertical list) for driving it in tests.

## Goal editing

`setGoal()` regenerates the plan from week 1 and persists. The form lives in
`ui/goal/goal_editor.dart` as a **controlled** component and is used by both the onboarding wizard
and the post-onboarding edit sheet — they must not drift apart, so do not duplicate it.

Two affordances reach it: the tappable race card / "no goal set" card on the plan screen, and the
Edit goal button on the review screen. Both are keyed (`race-card`, `add-goal-card`) for tests;
match on those keys, not on strings like "Marathon", which also appear in flag text.

Save is explicit rather than per-keystroke, so a half-typed finish time cannot silently become the
runner's target.

## Tests

```bash
flutter test                                  # 288 unit + widget, mocked storage
flutter test integration_test -d emulator-5554 # 4 on-device, REAL storage
```

`integration_test/persistence_test.dart` deliberately does **not** mock SharedPreferences. It writes
a profile, calls `SharedPreferences.resetStatic()` to drop the in-memory cache, then reads through
a fresh controller — so the read is forced off disk. A test that passes proves the file was written,
not just the map.

## Building for Android

**The project is on `I:` but the Pub cache is on `C:`.** Kotlin's incremental compiler requires a
source file and its base file to share a root, so any plugin containing Kotlin sources fails:

```
IllegalArgumentException: this and base files have different roots: ...Pub\Cache\...\Foo.kt and I:\...\android
Could not close incremental caches ... class-fq-name-to-source.tab
```

`android/gradle.properties` therefore sets `kotlin.incremental=false`. This is a deliberate
workaround, not a leftover. `flutter clean` does **not** fix it — the cause is the drive split, not
a corrupt cache. It can be removed if the project moves to `C:` or `PUB_CACHE` moves to `I:`.

`shared_preferences_android` is the plugin that triggers it, so this is invisible until the first
APK build.

## Device verification

Primary target is the `Medium_Phone` AVD: 1080×2400 @ 420dpi → **411×914 dp logical**. The widget
suite runs at 400×900, which is close but not identical — if layout looks wrong on the device,
trust the device.

Storage is verified by inspecting the app's data directory rather than assumed:

```bash
adb shell run-as com.example.ai_running_trainer ls shared_prefs
adb shell run-as com.example.ai_running_trainer cat shared_prefs/FlutterSharedPreferences.xml
```

`shared_preferences` writes to the app data dir and survives restarts and reboots, but not
reinstall or "clear data". Note `flutter test integration_test` **uninstalls the app** when it
finishes, so reinstall before inspecting.

**Do not use the debug APK to judge performance.** A debug build on this 2 GB emulator ANRs on
launch ("Input dispatching timed out") purely because the 153 MB unstripped debug build cannot
produce a first frame inside the 5 s input-dispatch budget. The 68 MB profile build launches
cleanly. If something looks slow or hangs, reproduce it in profile before investigating.

**Flutter does not expose its semantics tree to `uiautomator`** without an accessibility service,
so `uiautomator dump` returns no text and the screen cannot be read that way. Use the integration
test suite to assert on-device behaviour instead of scraping the view hierarchy.

## Known limitations

- **`applicationId` is still `com.example.ai_running_trainer`**, the Flutter template placeholder.
  Not publishable. It needs a real reverse-domain ID, which requires a domain the user owns — the
  user has deferred this. It cannot be changed after a store submission.



## Design system

Read `ui/theme.dart` before touching any screen. The rules that are easy to break:

- **The `ColorScheme` is hand-authored, not `fromSeed`.** `fromSeed` derives a whole tonal palette
  from one seed and produces the default Flutter look regardless of which seed you pass. Do not
  "simplify" it back.
- **Dark only.** `#0E0D0D` is the base; surfaces step up from it. A light theme would be a second
  tuned system, not an inversion.
- **`#FF3600` is the only brand colour.** `#FE7A0D` is a gradient partner, never a competing
  primary — they are ~14° apart in hue and read as muddled if both carry roles.
- **Zone colours are a single heat ramp, not six hues.** Easy and recovery are deliberately cool and
  desaturated so the ~80% of a week that is easy recedes; only threshold/interval glow. Nothing in
  the ramp may equal the brand except `interval`.
- **Type lives in the `AppType` extension on `ThemeData`** (`theme.display`, `theme.label`,
  `theme.tabular`, …). It is named `AppType`, not `AppTheme`, because a class and an extension cannot
  share a name — the class would shadow the extension and every `theme.display` would fail.
- **`tabular` on any numeral that re-renders.** Times and paces jitter sideways with proportional
  figures.
- **No `Colors.black26` or other palette literals in screens.** Pull from `AppColors` / `ZonePalette`.
- **Stat rows use `FittedBox(scaleDown)`.** A stat is a third of a phone-width row and the content
  is unbounded — three-digit volumes, seven-character durations. This is not optional; without it
  the week header overflows at 400px.
- **`ZoneRule` (a 3px bar) replaced the pill badge.** Chips and outlined cards are the clearest
  markers of an unstyled app; there are none left in the screens.


## Things an agent would get wrong

- **`lib/domain/` must not import `package:flutter`.** All the pace math lives there so it is
  unit-testable without a widget harness. Adding a Flutter import breaks that boundary.
- **Pace conversion is `s/mi ÷ 1.609344`, not `×`.** An earlier version multiplied, which put
  threshold pace a full minute off. `zones_test.dart` pins the published VDOT 50 values to catch it.
- **VDOT is a table, not the raw equation.** `engine/vdot.dart` embeds the published equivalent-time
  table and interpolates. The raw Daniels equation was deliberately not reproduced: implementations
  of it disagree by up to ~4%, and at least one popular calculator is simply wrong. Change the table
  only against a source, and update the anchors in `vdot_test.dart` with it.
- **Cutback weeks are defined once**, in `volume.isCutbackWeek`. The volume curve and both generators
  once disagreed about which weeks were cutbacks, which produced 4 km long-run jumps.
- **A cutback is a dip, not a downgrade.** The volume curve returns to the pre-cutback level
  afterwards; without that a 12-week block ends up smaller than it started.
- **The growth baseline is the *enforced* long run**, not the pre-enforcement one, or growth exceeds
  the cap after a cutback.
- **`Workout.hardFractionOfDistance` exists because 80/20 is otherwise unreachable.** A tempo is
  mostly easy by distance. Without it, one quality session counts as a third of the week at
  threshold.
- **Zone anchor is the goal race pace, not predicted current fitness.** Current fitness is only used
  to *validate* the goal. See `engine/zones.dart`.
- **Riegel is optimistic at long distances.** `riiegel.conservativeMargin` is a deliberate, exposed
  heuristic. Do not remove it without replacing it.
- **Beginner path contains zero quality sessions.** That is a safety property, asserted in
  `plan_test.dart`. Do not add threshold work there.
- **The 80/20, long-run-share, and taper-monotonic rules are invariants**, enforced in
  `enforceSafety`/`buildVolumeCurve` and asserted across 10 plan shapes in `plan_test.dart`. A
  generator change that breaks them should fail the test, not be papered over. The long-run share is
  **day-aware** (`maxLongRunFractionFor`), and a plan week must satisfy *two* invariants at once:
  the long run is the longest run of the week, **and** the reported target equals the sum of the
  sessions. Either alone is satisfiable while the plan is still wrong.
- **Widget tests run at 400x900 on purpose.** They used to run at 1200x3000, which built every row
  at a width no device has — that is why a phone-width overflow shipped. `expectNoLayoutError` is
  the guard; do not widen the surface back.

## Known limitations

Resolved since v1, and previously listed here: goal changes no longer lose progress (completion is
keyed on week start dates), and the "only progress if the last week was completed" rule is now
implemented as the 90% rule.

Remaining:

- **`applicationId` is still `com.example.ai_running_trainer`**, the Flutter template placeholder.
  Not publishable. It needs a real reverse-domain ID, which requires a domain the user owns — the
  user has deferred this. It cannot be changed after a store submission.
- **No imperial units.** Everything is SI internally; display conversion is not built. Metric was an
  explicit product decision.
- **Plan is anchored to the next Monday after onboarding**, not the onboarding day. A mid-week start
  wastes week 1 and makes the runner look behind before running a step. `alignToNextMonday`; today
  being a Monday is used as-is. The review screen states the start date so it is not silent.
- **Goal realism is judged against *trained* fitness, not the bare PB.** `currentExpectation` in
  `validation.dart` nudges the anchor equivalent by ±1% from logged difficulties. A fitter athlete
  has less ground to cover to a given time, so absorbed training makes a goal look *less* ambitious
  and hard weeks make it look *more* — which is the useful direction, because a goal that has quietly
  become unreachable then gets flagged. The adjustment is deliberately small; claiming to know more
  than the logs do would be worse than leaving the PB alone.
- **No light theme**, and no elevation/shadow system — the design is flat surfaces plus hairlines.
- `Pace` rounds to whole seconds, so zone paces can differ by ~1 s/km from an exact calculation.