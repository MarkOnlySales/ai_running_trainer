/// The race-time form, as a controlled component.
///
/// Extracted from the wizard for the same reason as `ProfileEditor`: the
/// onboarding and edit flows must ask for identical things, and a second copy
/// of a form is a second set of rules to keep in sync.
library;

import 'package:flutter/material.dart';

import '../../domain/models/race.dart';
import '../../domain/units.dart';
import '../theme.dart';

/// One field per distance, with a date on each.
///
/// Emits only the races that have both a parseable time and a date. A half-typed
/// entry is *not* emitted — it reads as "not supplied" rather than as a
/// completion, so a runner mid-entry never has their plan rebuilt on a partial
/// time.
class RaceEditor extends StatefulWidget {
  const RaceEditor({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final List<RaceResult> value;
  final ValueChanged<List<RaceResult>> onChanged;

  @override
  State<RaceEditor> createState() => _RaceEditorState();
}

class _RaceEditorState extends State<RaceEditor> {
  final _times = <RaceDistance, TextEditingController>{};
  final _dates = <RaceDistance, DateTime>{};

  @override
  void initState() {
    super.initState();
    _seed();
  }

  @override
  void didUpdateWidget(RaceEditor old) {
    super.didUpdateWidget(old);
    if (!identical(widget.value, old.value)) _seed();
  }

  void _seed() {
    for (final d in RaceDistance.values) {
      _times[d]?.dispose();
      _times[d] = TextEditingController();
      _dates[d] = DateTime.now().subtract(const Duration(days: 60));
    }
    for (final r in widget.value) {
      _times[r.distance]!.text = formatTimeInput(r.time);
      _dates[r.distance] = r.date;
    }
  }

  @override
  void dispose() {
    for (final c in _times.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _emit() {
    final races = <RaceResult>[];
    for (final d in RaceDistance.values) {
      final t = parseTimeInput(_times[d]!.text);
      if (t == null) continue;
      races.add(RaceResult(distance: d, time: t, date: _dates[d]!));
    }
    widget.onChanged(races);
  }

  String _age(RaceDistance d) {
    final days = DateTime.now().difference(_dates[d]!).inDays;
    if (days > 365) return 'Over a year old';
    if (days > 30) return '${(days / 30).round()} months ago';
    return 'Recent';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final d in RaceDistance.values) ...[
          RaceField(
            distance: d,
            controller: _times[d]!,
            date: _dates[d]!,
            dateLabel: _age(d),
            onChanged: (_) => _emit(),
            onPickDate: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _dates[d]!,
                firstDate: DateTime.now().subtract(const Duration(days: 3650)),
                lastDate: DateTime.now(),
              );
              if (picked != null) {
                setState(() => _dates[d] = picked);
                _emit();
              }
            },
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Leave anything blank you are not sure about.',
          style: theme.bodyMuted.copyWith(fontSize: 12),
        ),
      ],
    );
  }
}

/// One distance's time and date.
///
/// Public because the onboarding review step renders the same shape read-only,
/// and a private copy of this card in two files is the drift this extraction
/// exists to prevent.
class RaceField extends StatelessWidget {
  const RaceField({
    super.key,
    required this.distance,
    required this.controller,
    required this.date,
    required this.onPickDate,
    required this.dateLabel,
    this.onChanged,
  });

  final RaceDistance distance;
  final TextEditingController controller;
  final DateTime date;
  final VoidCallback onPickDate;
  final String dateLabel;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: Key('race-field-${distance.name}'),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  distance.label,
                  style: theme.title.copyWith(fontSize: 15),
                ),
              ),
              GestureDetector(
                onTap: onPickDate,
                behavior: HitTestBehavior.opaque,
                child: Row(
                  children: [
                    Text(
                      dateLabel,
                      style: theme.bodyMuted.copyWith(fontSize: 11.5),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.edit_calendar_outlined,
                      size: 14,
                      color: AppColors.textTertiary,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: controller,
            onChanged: onChanged,
            style: theme.tabular.copyWith(fontSize: 18),
            decoration: InputDecoration(
              hintText: switch (distance) {
                RaceDistance.k5 => '22:30',
                RaceDistance.k10 => '45:00',
                RaceDistance.half => '1:45:00',
                RaceDistance.marathon => '3:30:00',
              },
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}
