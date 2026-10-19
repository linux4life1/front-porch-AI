// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Author seeds occupation, a short job brief, work hours, and weekdays.
// Not an at-work switch. Occupation is the title; [occupationBrief] is
// what the job actually is (empty = today — do not invent it). Hours is the
// story-time picker run twice. Period words ("mornings") are not hours.
// Missing workDays displays Mon–Fri; written [] is every chip off.

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/theme/creator_palette.dart';

/// Fields inside the Work identity card. Header/card chrome lives on
/// [IdentityChipLists] so Work matches Ambitions / Likes.
///
/// Occupation is a short free-text title. **What the job is** binds to
/// `occupationBrief`. Hours is the existing story-time picker shown twice —
/// Start and End. The stored card `hours` is derived from the two pickers
/// ("9am–5pm"), and [hoursMatch] reads that same string. Weekday chips
/// write [workDays]; missing shows Mon–Fri.
class WorkRow extends StatefulWidget {
  final String occupation;
  final String occupationBrief;
  final String hours;
  final List<int>? workDays;
  final ValueChanged<String> onOccupationChanged;
  final ValueChanged<String> onOccupationBriefChanged;
  final ValueChanged<String> onHoursChanged;
  final ValueChanged<List<int>>? onWorkDaysChanged;

  const WorkRow({
    super.key,
    required this.occupation,
    this.occupationBrief = '',
    required this.hours,
    this.workDays,
    required this.onOccupationChanged,
    this.onOccupationBriefChanged = _noop,
    required this.onHoursChanged,
    this.onWorkDaysChanged,
  });

  static void _noop(String _) {}

  @override
  State<WorkRow> createState() => _WorkRowState();
}

class _WorkRowState extends State<WorkRow> {
  static const _defaultStart = TimeOfDay(hour: 9, minute: 0);
  static const _defaultEnd = TimeOfDay(hour: 17, minute: 0);

  late TimeOfDay _start;
  late TimeOfDay _end;
  late bool _rangeSet;

  @override
  void initState() {
    super.initState();
    _apply(widget.hours);
  }

  @override
  void didUpdateWidget(WorkRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hours != widget.hours &&
        widget.hours !=
            formatWorkHoursRange(
              _start.hour * 60 + _start.minute,
              _end.hour * 60 + _end.minute,
            )) {
      _apply(widget.hours);
    }
  }

  void _apply(String hours) {
    final range = parseWorkHoursRange(hours);
    if (range == null) {
      _start = _defaultStart;
      _end = _defaultEnd;
      _rangeSet = false;
      return;
    }
    _start = TimeOfDay(hour: range.$1 ~/ 60, minute: range.$1 % 60);
    _end = TimeOfDay(hour: range.$2 ~/ 60, minute: range.$2 % 60);
    _rangeSet = true;
  }

  Future<void> _pick({required bool isStart}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _start : _end,
      helpText: isStart ? 'Shift starts at…' : 'Shift ends at…',
    );
    if (!mounted || picked == null) return;
    setState(() {
      if (isStart) {
        _start = picked;
      } else {
        _end = picked;
      }
      _rangeSet = true;
    });
    widget.onHoursChanged(
      formatWorkHoursRange(
        _start.hour * 60 + _start.minute,
        _end.hour * 60 + _end.minute,
      ),
    );
    if (widget.workDays == null) {
      widget.onWorkDaysChanged?.call(List<int>.from(kDefaultWorkDays));
    }
  }

  void _toggleDay(int day) {
    final current = resolveWorkDays(widget.workDays);
    final next = List<int>.from(current);
    if (next.contains(day)) {
      next.remove(day);
    } else {
      next
        ..add(day)
        ..sort();
    }
    widget.onWorkDaysChanged?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    final amber =
        context.creatorPalette?.amber ?? AppColors.porchAmberOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _field(
          context,
          key: const ValueKey('work-occupation'),
          label: 'Occupation',
          hint: 'e.g. librarian',
          initial: widget.occupation,
          onChanged: widget.onOccupationChanged,
        ),
        const SizedBox(height: 8),
        _field(
          context,
          key: const ValueKey('work-brief'),
          label: 'What the job is',
          hint: 'e.g. shelves returns, then reads until close',
          initial: widget.occupationBrief,
          onChanged: widget.onOccupationBriefChanged,
          helper: 'Grounds at-work narration. Not a lorebook. Empty is today.',
          maxLines: 3,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _timeChip(
                context,
                amber,
                key: const ValueKey('work-start'),
                label: 'Start',
                t: _start,
                isStart: true,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                '–',
                style: TextStyle(
                  fontSize: 14,
                  color:
                      context.creatorPalette?.muted ??
                      AppColors.textTertiary(context),
                ),
              ),
            ),
            Expanded(
              child: _timeChip(
                context,
                amber,
                key: const ValueKey('work-end'),
                label: 'End',
                t: _end,
                isStart: false,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _daysRow(context, amber),
      ],
    );
  }

  static const _dayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  Widget _daysRow(BuildContext context, Color amber) {
    final selected = resolveWorkDays(widget.workDays).toSet();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Days',
          style: TextStyle(
            fontSize: 11,
            color:
                context.creatorPalette?.muted ??
                AppColors.textTertiary(context),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            for (var i = 0; i < 7; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              Expanded(child: _dayChip(context, amber, i + 1, selected)),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Weekdays unless you tap others.',
          style: TextStyle(
            fontSize: 11,
            height: 1.35,
            color:
                context.creatorPalette?.prose ??
                AppColors.textSecondary(context),
          ),
        ),
      ],
    );
  }

  Widget _dayChip(
    BuildContext context,
    Color amber,
    int day,
    Set<int> selected,
  ) {
    final on = selected.contains(day);
    return InkWell(
      key: ValueKey('work-day-$day'),
      onTap: () => _toggleDay(day),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: on
              ? amber
              : context.creatorPalette?.raise ??
                    AppColors.surfaceContainerOf(context),
          border: Border.all(color: amber.withValues(alpha: on ? 1 : .5)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          _dayLetters[day - 1],
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: on
                ? context.creatorPalette?.amberInk ??
                      AppColors.onAccentOf(context)
                : context.creatorPalette?.ink ?? AppColors.textPrimary(context),
          ),
        ),
      ),
    );
  }

  Widget _field(
    BuildContext context, {
    required Key key,
    required String label,
    required String hint,
    required String initial,
    required ValueChanged<String> onChanged,
    String? helper,
    int maxLines = 1,
  }) {
    final amber =
        context.creatorPalette?.amber ?? AppColors.porchAmberOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color:
                context.creatorPalette?.muted ??
                AppColors.textTertiary(context),
          ),
        ),
        const SizedBox(height: 4),
        TextFormField(
          key: key,
          initialValue: initial,
          onChanged: onChanged,
          maxLines: maxLines,
          style: TextStyle(
            fontSize: 13,
            color:
                context.creatorPalette?.ink ?? AppColors.textPrimary(context),
          ),
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: TextStyle(
              fontSize: 13,
              color:
                  context.creatorPalette?.muted ??
                  AppColors.textTertiary(context),
            ),
            helperText: helper,
            helperMaxLines: 2,
            helperStyle: TextStyle(
              fontSize: 11,
              height: 1.35,
              color:
                  context.creatorPalette?.prose ??
                  AppColors.textSecondary(context),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 8,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color:
                    context.creatorPalette?.line ?? AppColors.borderOf(context),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: amber),
            ),
          ),
        ),
      ],
    );
  }

  Widget _timeChip(
    BuildContext context,
    Color amber, {
    required Key key,
    required String label,
    required TimeOfDay t,
    required bool isStart,
  }) {
    return InkWell(
      key: key,
      onTap: () => _pick(isStart: isStart),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color:
              context.creatorPalette?.raise ??
              AppColors.surfaceContainerOf(context),
          border: Border.all(color: amber.withValues(alpha: .5)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color:
                    context.creatorPalette?.muted ??
                    AppColors.textTertiary(context),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              _rangeSet
                  ? StoryClock.formatClock(
                      DateTime.utc(2000, 1, 1, t.hour, t.minute),
                    )
                  : 'Set',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _rangeSet
                    ? context.creatorPalette?.ink ??
                          AppColors.textPrimary(context)
                    : context.creatorPalette?.muted ??
                          AppColors.textTertiary(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
