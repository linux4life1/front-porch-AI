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

import 'package:provider/provider.dart';

import 'package:front_porch_ai/database/database.dart' hide AvatarImage, World;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/world_store/world_store.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// What the 1:1 chat a group was made from had switched on, so Edit Group
/// can offer to fill in settings that groups forked before the fix were
/// saved without.
class ForkedGroupSource {
  const ForkedGroupSource({
    required this.realismOn,
    required this.needsOn,
    required this.worlds,
  });

  final bool realismOn;
  final bool needsOn;

  /// Where that chat is; null when it has no worlds.
  final GroupWorldChoice? worlds;

  /// Whether [group]'s settings for new chats are missing something the
  /// chat had: realism, its world, or the host's lorebook.
  bool differsFrom(GroupChat group) =>
      (realismOn &&
          parseGroupRealismSeeds(group.defaultMemberRealismState).isEmpty) ||
      (worlds != null &&
          group.worldIds.isEmpty &&
          (group.loreWorldIds?.isEmpty ?? true)) ||
      !group.inheritCharacterLorebooks;
}

/// The first chat of [group] when the group was made from a 1:1 (its
/// parent session has no group), read as a [ForkedGroupSource]. Null for a
/// group made any other way.
Future<ForkedGroupSource?> findForkedGroupSource(
  AppDatabase db,
  GroupChat group, {
  required World? Function(String id) lookup,
}) async {
  final sessions = await db.getSessionsForGroup(group.id);
  if (sessions.isEmpty) return null;
  final first = sessions.last; // newest first
  final parentId = first.parentSession;
  if (parentId == null) return null;
  final parent = await db.getSessionById(parentId);
  if (parent == null || parent.groupId != null) return null;
  final slots = await db.getChatWorldAttachments(first.id);
  return ForkedGroupSource(
    realismOn: first.realismEnabled,
    needsOn: first.needsSimEnabled,
    worlds: groupWorldChoiceFromChat(
      primaryId: slots.primaryId,
      loreIds: slots.loreIds,
      lookup: lookup,
    ),
  );
}

/// Edit Group's banner for a group forked before the fix. It finds the chat
/// the group came from itself and draws nothing for any other group. "Use
/// the chat's settings" only fills the editor; Save writes it. Reading the
/// host's lorebook is a separate switch because it is the one change that
/// also reaches chats already running.
class EditGroupForkNotice extends StatefulWidget {
  const EditGroupForkNotice({
    super.key,
    required this.group,
    required this.applied,
    required this.onUseSettings,
    required this.inheritOn,
    required this.onInheritChanged,
  });

  final GroupChat group;
  final bool applied;
  final ValueChanged<ForkedGroupSource> onUseSettings;
  final bool inheritOn;
  final ValueChanged<bool> onInheritChanged;

  @override
  State<EditGroupForkNotice> createState() => _EditGroupForkNoticeState();
}

class _EditGroupForkNoticeState extends State<EditGroupForkNotice> {
  ForkedGroupSource? _source;
  bool _looked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_looked) return;
    _looked = true;
    final AppDatabase db;
    try {
      db = liveDatabase(context);
    } catch (e) {
      // No database to read the source chat from; the notice stays hidden.
      debugPrint('[EditGroup] fork notice has no database: $e');
      return;
    }
    final worlds = Provider.of<WorldRepository>(context, listen: false);
    () async {
      try {
        final s = await findForkedGroupSource(
          db,
          widget.group,
          lookup: worlds.worldById,
        );
        if (mounted && s != null && s.differsFrom(widget.group)) {
          setState(() => _source = s);
        }
      } catch (e) {
        debugPrint('[EditGroup] could not read the chat this came from: $e');
      }
    }();
  }

  @override
  Widget build(BuildContext context) {
    final source = _source;
    if (source == null) return const SizedBox.shrink();
    final accent = AppColors.formAccentOf(context);
    final missing = [
      if (source.realismOn) 'Realism${source.needsOn ? ' and Needs' : ''} off',
      if (source.worlds != null) 'no world',
    ];
    return Container(
      key: const ValueKey('edit-group-fork-notice'),
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'This group started from a 1:1 chat.',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.applied
                ? 'Filled in from that chat. Press Save to keep it.'
                : missing.isEmpty
                ? "The chats you have now aren't affected."
                : 'Its settings for new chats were never filled in, so a new '
                      'chat would start with ${missing.join(' and ')}. The '
                      "chats you have now aren't affected.",
            style: TextStyle(color: AppColors.textSecondary(context)),
          ),
          if (missing.isNotEmpty && !widget.applied) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                key: const ValueKey('edit-group-fork-use'),
                onPressed: () => widget.onUseSettings(source),
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: AppColors.onAccentOf(context),
                ),
                child: const Text("Use the chat's settings"),
              ),
            ),
          ],
          SwitchListTile(
            key: const ValueKey('edit-group-fork-inherit'),
            contentPadding: EdgeInsets.zero,
            title: const Text("Read the original character's lorebook"),
            subtitle: const Text(
              'Turns on Inherit. Your open chats start reading it too.',
            ),
            value: widget.inheritOn,
            onChanged: widget.onInheritChanged,
          ),
        ],
      ),
    );
  }
}
