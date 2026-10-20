// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/utils/utils.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/ui/dialogs/group_settings/group_settings_support.dart';
import 'package:front_porch_ai/ui/dialogs/group_settings/member_baseline_seed.dart';
import 'package:front_porch_ai/ui/dialogs/group_settings/realism_needs_tab/group_realism_controller.dart';
import 'package:front_porch_ai/ui/dialogs/group_settings/realism_needs_tab/realism_slider_row.dart';

/// One member's card on the Realism tab: live readout, editable starting
/// baselines, and the per-member Director/Verifier settings.
class GroupMemberRealismCard extends StatelessWidget {
  final int index;
  final CharacterCard char;
  final ChatService cs;
  final bool isRealismActive;
  final GroupRealismNeedsController controller;

  const GroupMemberRealismCard({
    super.key,
    required this.index,
    required this.char,
    required this.cs,
    required this.isRealismActive,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final id = groupMemberStoreId(char);
    final liveState = isRealismActive
        ? cs.getRealismStateForGroupCharacter(char)
        : null;
    final emo = liveState?['emotion'] as String?;
    final bond = isRealismActive ? cs.getAffectionForGroupCharacter(char) : 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerOf(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Row(
        children: [
          // Avatar (matches Prompt tab style). No portrait (or only the flat
          // placeholder): the initial.
          RealPortrait(
            file: char.imagePath != null ? File(char.imagePath!) : null,
            portrait: (_, file) => CircleAvatar(
              radius: 16,
              backgroundColor: groupCharAccentColor(index),
              backgroundImage: FileImage(file),
            ),
            noPortrait: (_) => CircleAvatar(
              radius: 16,
              backgroundColor: groupCharAccentColor(index),
              child: Text(
                char.name.isNotEmpty ? char.name[0].toUpperCase() : '?',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: StatusColors.onFill,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  char.name,
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  isRealismActive
                      ? (emo != null
                            ? 'Emotion: $emo • Bond: $bond'
                            : 'No realism data yet (will seed on next turn)')
                      : 'Realism inactive (Director Mode or master off)',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textTertiary(context),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                // ── Editable Realism Baselines ─────────────────────
                const SizedBox(height: 8),
                // Relationship
                Row(
                  children: [
                    Icon(
                      Icons.favorite,
                      size: 14,
                      color: AppColors.relationshipAccentOf(context),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Relationship',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textPrimary(context),
                      ),
                    ),
                  ],
                ),
                Container(
                  margin: const EdgeInsets.only(top: 4, bottom: 8),
                  child: Column(
                    children: [
                      GroupRealismSliderRow(
                        label: 'Short-Term Bond',
                        value: c.editShortTermBond[id] ?? 50,
                        min: -300,
                        max: 300,
                        onChanged: (v) => c.updateEditShortTermBond(char, v),
                      ),
                      GroupRealismSliderRow(
                        label: 'Long-Term Bond',
                        value: c.editLongTermBond[id] ?? 50,
                        min: -300,
                        max: 300,
                        onChanged: (v) => c.updateEditLongTermBond(char, v),
                      ),
                      GroupRealismSliderRow(
                        label: 'Trust Level',
                        value: c.editTrustLevel[id] ?? 50,
                        min: -100,
                        max: 100,
                        onChanged: (v) => c.updateEditTrustLevel(char, v),
                      ),
                    ],
                  ),
                ),
                // Starting Emotion
                Row(
                  children: [
                    Icon(
                      Icons.mood,
                      size: 14,
                      color: AccentColors.goldOf(context),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Starting Emotion',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textPrimary(context),
                      ),
                    ),
                  ],
                ),
                Container(
                  margin: const EdgeInsets.only(top: 4, bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: c.emotionControllerFor(id),
                          decoration: InputDecoration(
                            hintText: 'emotion',
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            filled: true,
                            fillColor: AppColors.surfaceOf(context),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          style: const TextStyle(fontSize: 11),
                          onChanged: (v) => c.updateEditEmotion(char, v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue:
                              c.editEmotionIntensity[id] ?? 'moderate',
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            filled: true,
                            fillColor: AppColors.surfaceOf(context),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textPrimary(context),
                          ),
                          items: emotionIntensities
                              .map(
                                (e) =>
                                    DropdownMenuItem(value: e, child: Text(e)),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v != null) {
                              c.updateEditEmotionIntensity(char, v);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                // ── End Editable Realism Baselines ──────────────────
                // Per-member Director/Verifier settings, editable here for
                // existing groups (same perChar persistence + card ext patch
                // as group creation).
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Director/Verifier',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      height: 20,
                      width: 20,
                      child: Checkbox(
                        value: c.verificationEnabled[id] ?? false,
                        onChanged: (v) {
                          if (v != null) {
                            c.updateMemberVerificationEnabled(char, v);
                          }
                        },
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
                // Compact sliders + authority toggle for the Director settings.
                // Only shown when Director/Verifier is enabled for this member.
                if (c.verificationEnabled[id] ?? false) ...[
                  const SizedBox(height: 2),
                  _verifierSliders(context, id),
                  _authorityRow(context, id),
                ],
              ],
            ),
          ),
          TextButton(
            onPressed: () => c.resetCharacterRealism(char),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'Reset',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.porchAmberOf(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _verifierSliders(BuildContext context, String id) {
    final c = controller;
    return Row(
      children: [
        Text(
          'Max: ${c.verificationMaxReprocesses[id] ?? 1}',
          style: TextStyle(
            fontSize: 10,
            color: AppColors.textSecondary(context),
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 80,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
            ),
            child: Slider(
              value: (c.verificationMaxReprocesses[id] ?? 1).toDouble(),
              min: 1,
              max: 5,
              divisions: 4,
              onChanged: (d) {
                c.updateMemberVerificationMaxReprocesses(char, d.round());
              },
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'Strict: ${c.verificationStrictness[id] ?? 3}',
          style: TextStyle(
            fontSize: 10,
            color: AppColors.textSecondary(context),
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 80,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
            ),
            child: Slider(
              value: (c.verificationStrictness[id] ?? 3).toDouble(),
              min: 1,
              max: 5,
              divisions: 4,
              onChanged: (d) {
                c.updateMemberVerificationStrictness(char, d.round());
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _authorityRow(BuildContext context, String id) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Director authority (needs)',
          style: TextStyle(
            fontSize: 10,
            color: AppColors.textSecondary(context),
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          height: 18,
          width: 18,
          child: Checkbox(
            value: controller.needsDirectorAuthority[id] ?? false,
            onChanged: (v) {
              if (v != null) {
                controller.updateMemberNeedsDirectorAuthority(char, v);
              }
            },
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
        ),
      ],
    );
  }
}
