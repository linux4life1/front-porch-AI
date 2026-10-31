// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/utils/utils.dart';
import 'package:front_porch_ai/ui/pages/chat_page.sidebar_widgets.dart'
    show showEditCharacterDialog;
import 'package:front_porch_ai/ui/widgets/group_member_summary_row.dart';
import 'package:front_porch_ai/ui/widgets/realism_form_section/realism_form_section.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/ui/dialogs/group_settings/group_settings_support.dart';
import 'package:front_porch_ai/ui/dialogs/group_settings/realism_needs_tab/group_realism_controller.dart';

/// One member on the Realism tab: a live readout, a summary of where they
/// start in new chats of the group, and an Edit that opens their editor
/// (their start, Verification, Needs and Afterglow are there). This chat's
/// own controls for them stay here: their Afterglow switch with its
/// Recovery block, and Reset.
class GroupMemberRealismCard extends StatelessWidget {
  final int index;
  final CharacterCard char;
  final ChatService cs;
  final bool isRealismActive;
  final GroupRealismNeedsController controller;

  /// The holding Group Settings dialog's tab switch, for the editor's links.
  final void Function(int tab)? onShowTab;

  const GroupMemberRealismCard({
    super.key,
    required this.index,
    required this.char,
    required this.cs,
    required this.isRealismActive,
    required this.controller,
    this.onShowTab,
  });

  Widget _afterglowRow(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        'Afterglow',
        style: TextStyle(fontSize: 11, color: AppColors.textSecondary(context)),
      ),
      const SizedBox(width: 6),
      SizedBox(
        height: 24,
        child: FittedBox(
          child: Switch(
            value: char.frontPorchExtensions?.afterglowEnabled ?? true,
            activeThumbColor: AppColors.lustAccentOf(context),
            onChanged: (v) => controller.updateMemberAfterglow(char, v),
          ),
        ),
      ),
    ],
  );

  Widget _avatar() => RealPortrait(
    file: char.imagePath != null ? File(char.imagePath!) : null,
    portrait: (_, file) => CircleAvatar(
      radius: 16,
      backgroundColor: groupCharAccentColor(index),
      backgroundImage: portraitAvatarImage(file),
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
  );

  @override
  Widget build(BuildContext context) {
    final liveState = isRealismActive
        ? cs.getRealismStateForGroupCharacter(char)
        : null;
    final emo = liveState?['emotion'] as String?;
    final bond = isRealismActive ? cs.getAffectionForGroupCharacter(char) : 0;
    final group = cs.activeGroup;
    final afterglowShown =
        afterglowEnabledOf(context) && cs.afterglowChatSwitch;
    final ownAfterglow = char.frontPorchExtensions?.afterglowEnabled ?? true;

    return GroupMemberSummaryRow(
      key: ValueKey('member-summary-${groupMemberStoreId(char)}'),
      leading: _avatar(),
      name: char.name,
      detail: groupMemberSummaryDetail(
        start: group == null
            ? null
            : groupMemberStartIn(
                group.defaultMemberRealismState,
                groupMemberStoreId(char),
                card: char.frontPorchExtensions,
                legacyIds: [char.stableGroupId],
              ),
        afterglow: afterglowShown ? ownAfterglow : null,
        lite: char.isLite,
      ),
      onEdit: () =>
          showEditCharacterDialog(context, char, groupSettingsTab: onShowTab),
      below: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
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
              ),
              TextButton(
                onPressed: () => controller.resetCharacterRealism(char),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
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
          // This member's own Afterglow switch in this chat, while Porch Life
          // allows Afterglow and the group chat's switch is on (the phone
          // shows the same switch).
          if (afterglowShown) ...[
            _afterglowRow(context),
            // Their Recovery block while their own switch is on, as the card
            // editor shows it under the card's switch.
            if (ownAfterglow)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: RecoveryBlock(
                  recovery:
                      char.frontPorchExtensions?.recovery ??
                      RecoveryProfile.auto,
                  sex: char.frontPorchExtensions?.sex ?? '',
                  intimateInto:
                      char.frontPorchExtensions?.intimateInto ?? const [],
                  intimateNotInto:
                      char.frontPorchExtensions?.intimateNotInto ?? const [],
                  onChanged: (r) => controller.updateMemberRecovery(char, r),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
