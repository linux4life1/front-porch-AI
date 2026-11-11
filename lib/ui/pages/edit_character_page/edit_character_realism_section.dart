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
import 'package:front_porch_ai/ui/pages/edit_character_page/edit_character_draft.dart';
import 'package:front_porch_ai/ui/pages/edit_character_page/edit_character_form_kit.dart';
import 'package:front_porch_ai/ui/pages/edit_character_page/group_member_mode.dart';
import 'package:front_porch_ai/ui/widgets/needs_form_section.dart';
import 'package:front_porch_ai/ui/widgets/realism_form_section/realism_form_section.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// The character editor's Realism section (engine toggles + seeds). Every
/// edit marks [EditCharacterDraft.realismSettingsModified] so Save writes the
/// extensions even while the engine is off.
class EditCharacterRealismSection extends StatelessWidget {
  final EditCharacterDraft draft;
  final VoidCallback onChanged;

  /// Set when this is a group member's editor: Time & Day and Chaos Mode are
  /// the group's, so they show greyed out; everything else is the 1:1 form.
  final GroupMemberMode? member;

  /// The member's name as the editor has it now.
  final String? memberName;

  /// A lite member: Realism, Needs and Afterglow start at promotion.
  final bool lite;

  const EditCharacterRealismSection({
    super.key,
    required this.draft,
    required this.onChanged,
    this.member,
    this.memberName,
    this.lite = false,
  });

  void _edit(VoidCallback fn) {
    fn();
    draft.realismSettingsModified = true;
    onChanged();
  }

  /// Why the member's Realism, Needs and Afterglow are hidden, or null.
  String? _hiddenNote(String who) {
    if (lite) {
      return "$who's Realism, Needs and Afterglow start when they are "
          'promoted to a full member of this group.';
    }
    if (member?.realismAllowed == false) {
      return 'Realism, Needs and Afterglow are hidden: the Realism Engine is '
          "off in Porch Life. $who's settings are kept.";
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => _build(context);

  Widget _build(BuildContext context) {
    final d = draft;
    final mode = member;
    final name = memberName;
    final hidden = mode == null || name == null ? null : _hiddenNote(name);
    final scene = mode?.scene;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Playful disclaimer note
        EditCharacterFormKit(context).disclaimer(
          'These settings only affect new conversations with this character — '
          "your existing chats won't be changed. No cheating with the relationship values!",
        ),
        const SizedBox(height: 16),
        if (hidden != null) MemberEditorNote(hidden),

        // Full editable Realism Engine form
        RealismFormSection(
          enabled: hidden == null && d.realismEnabled,
          showMasterEnabledToggle: hidden == null,
          timeDayLockedTooltip: mode == null ? null : kTimeDayLockedTooltip,
          chaosLockedTooltip: mode == null ? null : kChaosLockedTooltip,
          verificationLockedTooltip: mode == null
              ? null
              : kVerificationLockedTooltip,
          onEnabledChanged: (v) => _edit(() => d.realismEnabled = v),
          // A member shows the group's own scene, read-only.
          timeOfDay: scene?.timeOfDay ?? d.realismTimeOfDay,
          onTimeOfDayChanged: (v) => _edit(() => d.realismTimeOfDay = v),
          dayCount: scene?.dayCount ?? d.realismDayCount,
          onDayCountChanged: (v) => _edit(() => d.realismDayCount = v),
          storyStartDate: scene != null
              ? scene.storyStartDate
              : d.realismStoryStartDate,
          onStoryStartDateChanged: (v) =>
              _edit(() => d.realismStoryStartDate = v),
          storyStartTime: scene != null
              ? scene.storyStartTime
              : d.realismStoryStartTime,
          onStoryStartTimeChanged: (v) =>
              _edit(() => d.realismStoryStartTime = v),
          shortTermBond: d.realismShortTermBond,
          onShortTermBondChanged: (v) =>
              _edit(() => d.realismShortTermBond = v),
          longTermBond: d.realismLongTermBond,
          onLongTermBondChanged: (v) => _edit(() => d.realismLongTermBond = v),
          trustLevel: d.realismTrustLevel,
          onTrustLevelChanged: (v) => _edit(() => d.realismTrustLevel = v),
          emotion: d.realismEmotion,
          onEmotionChanged: (v) => _edit(() => d.realismEmotion = v),
          emotionIntensity: d.realismEmotionIntensity,
          onEmotionIntensityChanged: (v) =>
              _edit(() => d.realismEmotionIntensity = v),
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
            enabled: d.realismNeedsSim,
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
