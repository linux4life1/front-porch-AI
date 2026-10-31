// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'package:flutter/material.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/group_member_start.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/group_member_summary_row.dart';
import 'package:front_porch_ai/ui/widgets/identity_chip_lists.dart'
    show afterglowEnabledOf;
import 'package:front_porch_ai/ui/widgets/group_realism_dynamics_editor/group_realism_dynamics_editor.dart';
import 'package:front_porch_ai/ui/widgets/story_begins_row.dart';
import 'package:front_porch_ai/utils/utils.dart';

export 'group_realism_dynamics_editor/group_realism_member.dart';

/// The "Realism & Dynamics" editor for an existing group: the group's own
/// switches for new chats (Realism, Afterglow, Needs, scene time), a summary
/// of each member with an Edit that opens their editor (where their start,
/// Needs and Afterglow are), and the intragroup dynamics sliders.
///
/// Everything is keyed by the member `mid` (what the runtime reads). On load it
/// falls back to a member's `originStableId` to recover seeds written by the old
/// (mis-keyed) creator, so opening + saving this tab migrates a legacy group
/// forward. Emits the two ready-to-store blobs through [onChanged] whenever the
/// user edits anything; the host page persists them on Save.
class GroupRealismDynamicsEditor extends StatefulWidget {
  final List<GroupRealismMember> members;
  final String initialDefaultMemberJson;
  final String initialBaselineJson;

  /// Called with (defaultMemberRealismState, baselineRealismState) on every edit.
  final void Function(String defaultMemberJson, String baselineJson) onChanged;

  /// Opens member [mid]'s editor; the summaries have no Edit without it.
  final void Function(String mid)? onEditMember;

  const GroupRealismDynamicsEditor({
    super.key,
    required this.members,
    required this.initialDefaultMemberJson,
    required this.initialBaselineJson,
    required this.onChanged,
    this.onEditMember,
  });

  @override
  State<GroupRealismDynamicsEditor> createState() =>
      _GroupRealismDynamicsEditorState();
}

class _GroupRealismDynamicsEditorState
    extends State<GroupRealismDynamicsEditor> {
  final Map<String, Map<String, dynamic>> _seedsByMid = {};
  bool _realismEnabled = false;
  bool _needsEnabled = true;

  /// The group's Afterglow for new chats ([kGroupAfterglowKey]).
  bool _afterglow = true;
  String _timeOfDay = 'morning';
  int _dayCount = 1;
  // Story Calendar authoring (story-calendar.md §3a).
  String? _storyStartDate;
  String? _storyStartTime;
  List<String> _alternateGreetings = const [];
  List<GreetingRealismSeed?> _greetingSeeds = const [];

  // The offered periods ARE [StoryClock.periods] — the wire format the seed is
  // stored in and the only list `representativeTime` knows. This picker used to
  // offer 'noon' and 'late night', which both silently seeded 09:00 morning;
  // old blobs still carry them, so map each onto the period it plainly meant
  // rather than re-emitting a string the clock throws away.
  static const _legacyPeriods = {'noon': 'late_morning', 'late night': 'night'};

  @override
  void initState() {
    super.initState();
    _alternateGreetings = parseGroupAlternateGreetings(
      widget.initialDefaultMemberJson,
    );
    _greetingSeeds = parseGroupGreetingSeeds(widget.initialDefaultMemberJson);
    _afterglow = groupAfterglowIn(widget.initialDefaultMemberJson);
    final parsed = parseGroupRealismSeeds(widget.initialDefaultMemberJson);
    _realismEnabled = parsed.isNotEmpty;

    // Detect the group-wide needs toggle from the ACTUAL stored seeds (a
    // realism-on/needs-off group has no `needs` sub-map). Fresh/realism-off
    // groups default to needs on, matching the creator.
    // NOTE: this infers the group-wide Needs toggle from whether a needs map
    // is PRESENT. That inference is load-bearing — deleting the map (as opposed
    // to correcting its keys, which is what happened) would silently switch
    // Needs off for existing groups. Replacing it with an explicit stored flag
    // was attempted and backed out: the flag is group-wide, and putting it in
    // the per-member seed breaks the parse(build(x)) == x round trip that
    // group_realism_blobs_test pins. It belongs at the blob's top level, which
    // is a schema decision with its own migration question.
    _needsEnabled = parsed.isEmpty
        ? true
        : parsed.values.any((s) {
            final n = s['needs'];
            return n is Map && n.isNotEmpty;
          });

    for (final m in widget.members) {
      final legacy = m.originStableId;
      final existing =
          parsed[m.mid] ?? (legacy != null ? parsed[legacy] : null);
      // Deep-ish copy so we never mutate the parsed source; ensure a
      // relationships map is always present.
      final seed = existing != null
          ? Map<String, dynamic>.from(existing)
          : groupMemberStartingSeed(m.extensions);
      seed['relationships'] = <String, int>{
        ...((seed['relationships'] as Map?)?.map(
              (k, v) => MapEntry(k.toString(), (v as num).toInt()),
            ) ??
            const {}),
      };
      _seedsByMid[m.mid] = seed;
    }

    // Global scene time: the canonical top-level keys of the defaultMember
    // blob, falling back to the first baseline entry for pre-calendar groups
    // — the exact read parseGroupTimeSeed does at runtime, so the editor
    // always shows what a fresh session would actually seed.
    final seed = parseGroupTimeSeed(
      widget.initialDefaultMemberJson,
      widget.initialBaselineJson,
    );
    if (seed != null) {
      _timeOfDay = StoryClock.periods.contains(seed.timeOfDay)
          ? seed.timeOfDay
          : (_legacyPeriods[seed.timeOfDay] ?? 'morning');
      _dayCount = seed.dayCount;
      _storyStartDate = seed.storyStartDate;
      _storyStartTime = seed.storyStartTime;
    }
  }

  void _emit() {
    if (!_realismEnabled) {
      widget.onChanged(
        withGroupOpeningAlts(
          '{}',
          alternateGreetings: _alternateGreetings,
          greetingSeeds: _greetingSeeds,
        ),
        '{}',
      );
      return;
    }
    final blobs = buildGroupRealismBlobs(
      seeds: _seedsByMid, // already keyed by mid — no remap needed
      needsEnabled: _needsEnabled,
      afterglowEnabled: _afterglow,
      timeOfDay: _timeOfDay,
      dayCount: _dayCount,
      storyStartDate: _storyStartDate,
      storyStartTime: _storyStartTime,
      alternateGreetings: _alternateGreetings,
      greetingSeeds: _greetingSeeds,
    );
    widget.onChanged(blobs.defaultMemberJson, blobs.baselineJson);
  }

  void _updateRelationship(String fromMid, String toMid, int value) {
    setState(() {
      final seed = _seedsByMid[fromMid] ??= groupMemberStartingSeed(
        widget.members.where((m) => m.mid == fromMid).firstOrNull?.extensions,
      );
      final rels = <String, int>{
        ...((seed['relationships'] as Map?)?.map(
              (k, v) => MapEntry(k.toString(), (v as num).toInt()),
            ) ??
            const {}),
      };
      rels[toMid] = value;
      seed['relationships'] = rels;
    });
    _emit();
  }

  final _avatars = GroupRealismAvatars();

  Widget _avatar(GroupRealismMember m, double radius) =>
      _avatars.avatar(context, m, radius);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // tileColor + bordered shape, not a decorated wrapper — ListTile ink
          // paints on the ancestor Material and a colored DecoratedBox above
          // it trips Flutter's ink-visibility assertion.
          SwitchListTile(
            tileColor: AppColors.cardOf(context),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: AppColors.borderOf(context)),
            ),
            title: Text(
              'Realism & Needs Engine',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary(context),
              ),
            ),
            subtitle: Text(
              _realismEnabled
                  ? 'Base bond/trust/emotion, needs, and hidden group feelings apply on new chats & re-entry.'
                  : 'Off — members use neutral defaults. Turn on to seed each member and their feelings.',
              style: TextStyle(color: AppColors.textSecondary(context)),
            ),
            value: _realismEnabled,
            onChanged: (v) {
              setState(() => _realismEnabled = v);
              _emit();
            },
          ),
          if (_realismEnabled) ...[
            // Porch Life (with 18+) allows Afterglow: how new chats start it.
            if (afterglowEnabledOf(context)) ...[
              const SizedBox(height: 16),
              SwitchListTile(
                tileColor: AppColors.cardOf(context),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: AppColors.borderOf(context)),
                ),
                secondary: Icon(
                  Icons.local_fire_department,
                  color: AppColors.lustAccentOf(context),
                ),
                title: Text(
                  'Afterglow',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary(context),
                  ),
                ),
                subtitle: Text(
                  'Lust and recovery in new chats of this group. Chats you '
                  'already have keep their own switch.',
                  style: TextStyle(color: AppColors.textSecondary(context)),
                ),
                value: _afterglow,
                onChanged: (v) {
                  setState(() => _afterglow = v);
                  _emit();
                },
              ),
            ],
            const SizedBox(height: 16),
            SwitchListTile(
              tileColor: AppColors.cardOf(context),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: AppColors.borderOf(context)),
              ),
              secondary: Icon(
                Icons.battery_std,
                color: AppColors.iconSecondary(context),
              ),
              title: Text(
                'Needs',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary(context),
                ),
              ),
              subtitle: Text(
                'Hunger, energy and the rest for every member in new chats '
                "of this group. Each member's own bars are in their editor.",
                style: TextStyle(color: AppColors.textSecondary(context)),
              ),
              value: _needsEnabled,
              onChanged: (v) {
                setState(() => _needsEnabled = v);
                _emit();
              },
            ),
            const SizedBox(height: 16),
            _buildSceneTimeCard(),
            const SizedBox(height: 16),
            ...widget.members.map(_buildMemberSummary),
            const SizedBox(height: 8),
            GroupDynamicsSection(
              members: widget.members,
              seedsByMid: _seedsByMid,
              avatar: _avatar,
              onRelationshipChanged: _updateRelationship,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSceneTimeCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Scene Time & Day',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary(context),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: StoryClock.periods.contains(_timeOfDay)
                      ? _timeOfDay
                      : 'morning',
                  decoration: const InputDecoration(labelText: 'Time of day'),
                  items: [
                    for (final t in StoryClock.periods)
                      DropdownMenuItem(
                        value: t,
                        child: Text(t.replaceAll('_', ' ')),
                      ),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _timeOfDay = v);
                    _emit();
                  },
                ),
              ),
              const SizedBox(width: 16),
              Row(
                children: [
                  Text(
                    'Day',
                    style: TextStyle(color: AppColors.textSecondary(context)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: _dayCount > 1
                        ? () {
                            setState(() => _dayCount--);
                            _emit();
                          }
                        : null,
                  ),
                  Text(
                    '$_dayCount',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: () {
                      setState(() => _dayCount++);
                      _emit();
                    },
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          StoryBeginsRow(
            storyStartDate: _storyStartDate,
            onStoryStartDateChanged: (v) {
              setState(() => _storyStartDate = v);
              _emit();
            },
            storyStartTime: _storyStartTime,
            onStoryStartTimeChanged: (v) {
              setState(() => _storyStartTime = v);
              _emit();
            },
          ),
        ],
      ),
    );
  }

  /// The member's start, read from the seed this tab holds, and their own
  /// Afterglow; Edit opens their editor, which saves the start to the group.
  Widget _buildMemberSummary(GroupRealismMember m) {
    final seed = _seedsByMid[m.mid] ?? groupMemberStartingSeed(m.extensions);
    final edit = widget.onEditMember;
    return GroupMemberSummaryRow(
      key: ValueKey('member-summary-${m.mid}'),
      leading: _avatar(m, 16),
      name: m.name,
      detail: groupMemberSummaryDetail(
        start: groupMemberStartOfSeed(seed),
        afterglow: afterglowEnabledOf(context) && _afterglow
            ? m.extensions?.afterglowEnabled ?? true
            : null,
        lite: m.extensions?.tier == 'lite',
      ),
      onEdit: edit == null ? null : () => edit(m.mid),
    );
  }
}
