// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'package:flutter/material.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/edit_character_page/edit_character_draft.dart';
import 'package:front_porch_ai/ui/pages/edit_character_page/member_group_view.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/needs_form_section.dart';
import 'package:front_porch_ai/ui/widgets/realism_form_section/realism_form_section.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// The character editor's Realism section (engine toggles + seeds). Every
/// edit marks [EditCharacterDraft.realismSettingsModified] so Save writes the
/// extensions even while the engine is off.
class EditCharacterRealismSection extends StatelessWidget {
  final EditCharacterDraft draft;
  final VoidCallback onChanged;

  /// Set when this is a group member's editor. The member's own settings are
  /// switches; the group's (Realism, time and day, Chaos, Afterglow, Needs)
  /// are read-only lines from [group], and the start is the group's seed for
  /// the member ([start]), never their card's.
  final String? memberName;

  /// The member's group: its lines and links.
  final MemberGroupView? group;

  /// Where the member starts in new chats of the group, as edited.
  final GroupMemberStart? start;
  final ValueChanged<GroupMemberStart>? onStartChanged;

  /// A lite member: Realism, Needs and Afterglow start at promotion.
  final bool lite;

  const EditCharacterRealismSection({
    super.key,
    required this.draft,
    required this.onChanged,
    this.memberName,
    this.group,
    this.start,
    this.onStartChanged,
    this.lite = false,
  });

  void _edit(VoidCallback fn) {
    fn();
    draft.realismSettingsModified = true;
    onChanged();
  }

  /// Why the member's Realism, Needs and Afterglow are hidden, or null.
  String? _hiddenNote(String member) {
    if (lite) {
      return "$member's Realism, Needs and Afterglow start when they are "
          'promoted to a full member of this group.';
    }
    if (group?.realismAllowed == false) {
      return 'Realism, Needs and Afterglow are hidden: the Realism Engine is '
          "off in Porch Life. $member's settings are kept.";
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final changes = group?.changes;
    if (changes == null) return _build(context);
    return ListenableBuilder(
      listenable: changes,
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final d = draft;
    final member = memberName;
    final view = group;
    final values = view?.read();
    final hidden = member == null ? null : _hiddenNote(member);
    var rows = view == null || values == null || member == null
        ? null
        : memberGroupRows(context, view, values, memberName: member);
    if (rows != null && hidden != null) {
      // The Optional Features card is hidden with the engine, so the
      // group's Chaos line joins the others.
      rows = MemberGroupRows(
        header: Column(children: [rows.header, rows.chaos]),
        chaos: const SizedBox.shrink(),
        startNote: rows.startNote,
      );
    }
    final s = start;
    void setStart(GroupMemberStart next) => onStartChanged?.call(next);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Playful disclaimer note
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.formAccentOf(context).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.formAccentOf(context).withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('😉', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  member != null
                      ? "These are $member's own settings in this group. A "
                            'line that ends "for this group" is the group\'s '
                            'own, set for everyone in it.'
                      : 'These settings only affect new conversations with this character — '
                            'your existing chats won\'t be changed. No cheating with the relationship values!',
                  style: TextStyle(
                    color: AppColors.formAccentOf(
                      context,
                    ).withValues(alpha: 0.8),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (hidden != null) MemberEditorNote(hidden),

        // Full editable Realism Engine form
        RealismFormSection(
          enabled: member != null ? hidden == null : d.realismEnabled,
          showMasterEnabledToggle: member == null,
          showTimeAndDay: member == null,
          showChaosToggle: member == null,
          showStartingState: member == null || s != null,
          memberRows: rows,
          afterglowLabel: member == null ? null : 'Afterglow for $member',
          afterglowSubtitle: member == null
              ? null
              : "Track $member's Lust and recovery in this group. The "
                    "group's Afterglow has to be on too.",
          onEnabledChanged: (v) => _edit(() => d.realismEnabled = v),
          timeOfDay: d.realismTimeOfDay,
          onTimeOfDayChanged: (v) => _edit(() => d.realismTimeOfDay = v),
          dayCount: d.realismDayCount,
          onDayCountChanged: (v) => _edit(() => d.realismDayCount = v),
          storyStartDate: d.realismStoryStartDate,
          onStoryStartDateChanged: (v) =>
              _edit(() => d.realismStoryStartDate = v),
          storyStartTime: d.realismStoryStartTime,
          onStoryStartTimeChanged: (v) =>
              _edit(() => d.realismStoryStartTime = v),
          // A member's start is the group's seed for them (s), never the
          // bonds and mood on their card.
          shortTermBond: s?.shortTerm ?? d.realismShortTermBond,
          onShortTermBondChanged: (v) => s != null
              ? setStart(s.copyWith(shortTerm: v))
              : _edit(() => d.realismShortTermBond = v),
          longTermBond: s?.longTerm ?? d.realismLongTermBond,
          onLongTermBondChanged: (v) => s != null
              ? setStart(s.copyWith(longTerm: v))
              : _edit(() => d.realismLongTermBond = v),
          trustLevel: s?.trust ?? d.realismTrustLevel,
          onTrustLevelChanged: (v) => s != null
              ? setStart(s.copyWith(trust: v))
              : _edit(() => d.realismTrustLevel = v),
          emotion: s?.emotion ?? d.realismEmotion,
          onEmotionChanged: (v) => s != null
              ? setStart(s.copyWith(emotion: v))
              : _edit(() => d.realismEmotion = v),
          emotionIntensity: s?.emotionIntensity ?? d.realismEmotionIntensity,
          onEmotionIntensityChanged: (v) => s != null
              ? setStart(s.copyWith(emotionIntensity: v))
              : _edit(() => d.realismEmotionIntensity = v),
          recovery: d.recovery,
          onRecoveryChanged: (v) => _edit(() => d.recovery = v),
          sex: d.sex,
          intimateInto: d.intimateInto,
          intimateNotInto: d.intimateNotInto,
          chaosModeEnabled: d.realismChaosMode,
          onChaosModeChanged: (v) => _edit(() => d.realismChaosMode = v),
          afterglowEnabled: d.realismAfterglow,
          onAfterglowChanged: (v) => _edit(() => d.realismAfterglow = v),
          realismVerificationEnabled: d.realismVerificationEnabled,
          onRealismVerificationChanged: (v) =>
              _edit(() => d.realismVerificationEnabled = v),
          realismVerificationMaxReprocesses:
              d.realismVerificationMaxReprocesses,
          onRealismVerificationMaxReprocessesChanged: (v) =>
              _edit(() => d.realismVerificationMaxReprocesses = v),
          realismVerificationStrictness: d.realismVerificationStrictness,
          onRealismVerificationStrictnessChanged: (v) =>
              _edit(() => d.realismVerificationStrictness = v),
          needsDirectorAuthority: d.realismNeedsDirectorAuthority,
          onNeedsDirectorAuthorityChanged: (v) =>
              _edit(() => d.realismNeedsDirectorAuthority = v),
          needsFormSection: NeedsFormSection(
            enabled: member != null || d.realismNeedsSim,
            showSwitch: member == null,
            groupLine: view == null || values == null
                ? null
                : memberGroupNeedsLine(context, view, values),
            onEnabledChanged: (v) => _edit(() => d.realismNeedsSim = v),
            enjoysLowHygiene: d.realismEnjoysLowHygiene,
            onEnjoysLowHygieneChanged: (v) =>
                _edit(() => d.realismEnjoysLowHygiene = v),
            needsPace: d.needsPace,
            onNeedsPaceChanged: (v) => _edit(() => d.needsPace = v),
            needsOff: d.needsOff,
            onNeedsOffChanged: (v) => _edit(() => d.needsOff = v),
            baselineHunger: d.needsBaselineHunger,
            onBaselineHungerChanged: (v) =>
                _edit(() => d.needsBaselineHunger = v),
            baselineBladder: d.needsBaselineBladder,
            onBaselineBladderChanged: (v) =>
                _edit(() => d.needsBaselineBladder = v),
            baselineEnergy: d.needsBaselineEnergy,
            onBaselineEnergyChanged: (v) =>
                _edit(() => d.needsBaselineEnergy = v),
            baselineSocial: d.needsBaselineSocial,
            onBaselineSocialChanged: (v) =>
                _edit(() => d.needsBaselineSocial = v),
            baselineFun: d.needsBaselineFun,
            onBaselineFunChanged: (v) => _edit(() => d.needsBaselineFun = v),
            baselineHygiene: d.needsBaselineHygiene,
            onBaselineHygieneChanged: (v) =>
                _edit(() => d.needsBaselineHygiene = v),
            baselineComfort: d.needsBaselineComfort,
            onBaselineComfortChanged: (v) =>
                _edit(() => d.needsBaselineComfort = v),
          ),
        ),
      ],
    );
  }
}
