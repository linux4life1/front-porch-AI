// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/group_member_realism_editor.dart';
import 'package:front_porch_ai/ui/widgets/relationship_scale.dart';
import 'package:front_porch_ai/utils/group_realism_blobs.dart';

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

  static const _timeOptions = [
    'dawn',
    'morning',
    'noon',
    'afternoon',
    'evening',
    'night',
    'late night',
  ];

  @override
  void initState() {
    super.initState();
    final parsed = parseGroupRealismSeeds(widget.initialDefaultMemberJson);
    _realismEnabled = parsed.isNotEmpty;

    // Detect the group-wide needs toggle from the ACTUAL stored seeds (a
    // realism-on/needs-off group has no `needs` sub-map). Fresh/realism-off
    // groups default to needs on, matching the creator.
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

    // Global scene time/day live on every baseline entry (identical across
    // members); read them off the first entry. baselineRealismState =
    // { mid: {affection, trust, ..., timeOfDay, dayCount} }.
    try {
      final b = widget.initialBaselineJson;
      if (b.isNotEmpty && b != '{}') {
        final decoded = jsonDecode(b);
        if (decoded is Map && decoded.isNotEmpty && decoded.values.first is Map) {
          final first = decoded.values.first as Map;
          _timeOfDay = (first['timeOfDay'] as String?) ?? _timeOfDay;
          _dayCount = (first['dayCount'] as num?)?.toInt() ?? _dayCount;
        }
      }
    } catch (_) {}
  }

  void _emit() {
    if (!_realismEnabled) {
      widget.onChanged('{}', '{}');
      return;
    }
    final blobs = buildGroupRealismBlobs(
      seeds: _seedsByMid, // already keyed by mid — no remap needed
      needsEnabled: _needsEnabled,
      timeOfDay: _timeOfDay,
      dayCount: _dayCount,
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

  Widget _avatar(GroupRealismMember m, double radius) {
    final path = m.avatarPath;
    if (path != null && path.isNotEmpty && File(path).existsSync()) {
      return CircleAvatar(radius: radius, backgroundImage: FileImage(File(path)));
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
          Container(
            decoration: BoxDecoration(
              color: AppColors.cardOf(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.borderOf(context)),
            ),
            child: SwitchListTile(
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
                  initialValue: _timeOptions.contains(_timeOfDay)
                      ? _timeOfDay
                      : 'morning',
                  decoration: const InputDecoration(labelText: 'Time of day'),
                  items: _timeOptions
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
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
                  Text('Day', style: TextStyle(color: AppColors.textSecondary(context))),
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

  Widget _buildDynamicsSection() {
    final members = widget.members;
    if (members.length < 2) return const SizedBox.shrink();
    if (members.length > 4) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.cardOf(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderOf(context)),
        ),
        child: Text(
          'Group Dynamics (hidden intra-group feelings) are available for groups '
          'of 4 or fewer, per the engine limits. Larger groups use different '
          'social-dynamics modeling.',
          style: TextStyle(
            color: AppColors.textTertiary(context),
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

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
            'Group Dynamics',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Pre-seed how members privately feel toward each other (hidden, '
            '-300..+300). These influence behavior in small groups.',
            style: TextStyle(color: AppColors.textSecondary(context)),
          ),
          const SizedBox(height: 16),
          ...members.map((source) {
            final rels =
                (_seedsByMid[source.mid]?['relationships'] as Map?)?.map(
                  (k, v) => MapEntry(k.toString(), (v as num).toInt()),
                ) ??
                const <String, int>{};
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _avatar(source, 16),
                      const SizedBox(width: 10),
                      Text(
                        'How ${source.name} feels about others',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary(context),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...members.where((t) => t.mid != source.mid).map((target) {
                    final value = rels[target.mid] ?? 0;
                    final color = relationshipScaleColor(context, value);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _avatar(target, 13),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                target.name,
                                style: TextStyle(
                                  color: AppColors.textPrimary(context),
                                ),
                              ),
                            ),
                            Text(
                              value > 0 ? '+$value' : '$value',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: color,
                              ),
                            ),
                          ],
                        ),
                        SliderTheme(
                          data: SliderThemeData(
                            activeTrackColor: color,
                            inactiveTrackColor: AppColors.borderOf(
                              context,
                            ).withValues(alpha: 0.3),
                            thumbColor: color,
                            trackHeight: 4,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 8,
                            ),
                          ),
                          child: Slider(
                            value: value.toDouble().clamp(-300, 300),
                            min: -300,
                            max: 300,
                            divisions: 120,
                            label: '$value',
                            onChanged: (v) => _updateRelationship(
                              source.mid,
                              target.mid,
                              v.round(),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            relationshipTierName(value),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: color,
                            ),
                          ),
                        ),
                      ],
                    );
                  }),
                  Divider(color: AppColors.borderOf(context)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
