// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'dart:io';

import 'package:flutter/material.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/group_member_realism_editor.dart';
import 'package:front_porch_ai/ui/widgets/relationship_scale.dart';
import 'package:front_porch_ai/ui/widgets/story_begins_row.dart';
import 'package:front_porch_ai/utils/utils.dart';

part 'group_realism_dynamics_editor.dynamics.dart';

/// A group member as this editor needs it: the RUNTIME id the realism engine
/// reads (`mid`), a display name, the optional legacy `originStableId` (used to
/// recover seeds from groups created before the id-keying fix), and an optional
/// avatar path for the header.
class GroupRealismMember {
  final String mid;
  final String name;
  final String? originStableId;
  final String? avatarPath;

  const GroupRealismMember({
    required this.mid,
    required this.name,
    this.originStableId,
    this.avatarPath,
  });
}

/// The "Realism & Dynamics" editor for an existing group: per-member base
/// realism/needs (via the shared [GroupMemberRealismEditor]) plus the intragroup
/// dynamics sliders — the same controls the create wizard exposes, so there is
/// one UX standard for seeding a group's realism.
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

  const GroupRealismDynamicsEditor({
    super.key,
    required this.members,
    required this.initialDefaultMemberJson,
    required this.initialBaselineJson,
    required this.onChanged,
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
          : defaultGroupMemberRealismSeed();
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
      timeOfDay: _timeOfDay,
      dayCount: _dayCount,
      storyStartDate: _storyStartDate,
      storyStartTime: _storyStartTime,
      alternateGreetings: _alternateGreetings,
      greetingSeeds: _greetingSeeds,
    );
    widget.onChanged(blobs.defaultMemberJson, blobs.baselineJson);
  }

  void _updateMember(String mid, Map<String, dynamic> delta) {
    setState(() {
      _seedsByMid[mid] = {...?_seedsByMid[mid], ...delta};
    });
    _emit();
  }

  void _updateRelationship(String fromMid, String toMid, int value) {
    setState(() {
      final seed = _seedsByMid[fromMid] ??= defaultGroupMemberRealismSeed();
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

  // Memoized per editor: _avatar runs once per member card, once per source
  // row and once per source×target pair, and EVERY relationship-slider drag
  // frame rebuilds the whole editor — N existsSync per frame is the io-lint
  // bug class (same shape as scene_guest_picker_dialog's cache).
  final Map<String, ImageProvider?> _avatarCache = {};

  Widget _avatar(GroupRealismMember m, double radius) {
    final path = m.avatarPath;
    final image = (path == null || path.isEmpty)
        ? null
        : _avatarCache.putIfAbsent(
            path,
            () =>
                File(path)
                    .existsSync() // io-ok: memoized per editor
                ? FileImage(File(path))
                : null,
          );
    if (image != null) {
      return CircleAvatar(radius: radius, backgroundImage: image);
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.surfaceContainerOf(context),
      child: Text(
        m.name.isNotEmpty ? m.name[0].toUpperCase() : '?',
        style: TextStyle(color: AppColors.textPrimary(context)),
      ),
    );
  }

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
            const SizedBox(height: 16),
            _buildSceneTimeCard(),
            const SizedBox(height: 16),
            ...widget.members.map(_buildMemberCard),
            _buildDynamicsSection(),
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

  Widget _buildMemberCard(GroupRealismMember m) {
    final seed = _seedsByMid[m.mid] ?? defaultGroupMemberRealismSeed();
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: _avatar(m, 18),
          title: Text(
            m.name,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary(context),
            ),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            GroupMemberRealismEditor(
              seed: seed,
              needsEnabled: _needsEnabled,
              onNeedsEnabledChanged: (v) {
                setState(() => _needsEnabled = v);
                _emit();
              },
              onUpdate: (delta) => _updateMember(m.mid, delta),
            ),
          ],
        ),
      ),
    );
  }
}
