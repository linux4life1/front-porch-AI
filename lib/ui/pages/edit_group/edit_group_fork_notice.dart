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
import 'package:front_porch_ai/ui/theme/theme.dart';

/// Edit Group's banner for a group forked before the fix. It finds the chat
/// the group came from itself and draws nothing for any other group. "Use
/// the chat's settings" only fills the editor; Save writes it. "Leave as
/// is" hides it for this visit. Reading the host's lorebook is a separate
/// switch because it is the one change that also reaches chats already
/// running.
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
  World? Function(String id) _lookup = (_) => null;
  bool _looked = false;
  bool _dismissed = false;

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
    _lookup = worlds.worldById;
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
    if (source == null || _dismissed) return const SizedBox.shrink();
    final accent = AppColors.formAccentOf(context);
    final host = source.hostName;
    final realismGap = source.realismMissingFrom(widget.group);
    final worldGap = source.worldMissingFrom(widget.group);
    final missing = [
      if (realismGap) 'Realism${source.needsOn ? ' and Needs' : ''} off',
      if (worldGap) 'no world',
    ];
    final meet = worldGap ? groupMeetLine(source.worlds!, _lookup) : null;
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
            host == null
                ? 'This group started from a 1:1 chat.'
                : 'This group started from your chat with $host.',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.applied
                ? 'Filled in from that chat. Press Save to keep it.'
                : 'Its settings for new chats were never filled in, so a new '
                      'chat would start with ${missing.join(' and ')}. The '
                      "chats you have now aren't affected.",
            style: TextStyle(color: AppColors.textSecondary(context)),
          ),
          const SizedBox(height: 10),
          Text(
            'FILLED IN FROM THAT CHAT',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w600,
              color: AppColors.textTertiary(context),
            ),
          ),
          if (realismGap)
            _ForkRow(
              title: 'Realism on · Needs ${source.needsOn ? 'on' : 'off'}',
              subtitle: 'Neutral starting values for every member',
            ),
          if (meet != null)
            _ForkRow(title: meet, subtitle: 'The world the chat is in'),
          _ForkRow(
            title: host == null
                ? "Read the original character's lorebook"
                : "Read $host's lorebook",
            subtitle: 'Turns on Inherit. Your open chats start reading it too.',
            trailing: Switch(
              key: const ValueKey('edit-group-fork-inherit'),
              value: widget.inheritOn,
              onChanged: widget.onInheritChanged,
            ),
          ),
          if (!widget.applied) ...[
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton(
                  key: const ValueKey('edit-group-fork-leave'),
                  onPressed: () => setState(() => _dismissed = true),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary(context),
                  ),
                  child: const Text('Leave as is'),
                ),
                FilledButton(
                  key: const ValueKey('edit-group-fork-use'),
                  onPressed: () => widget.onUseSettings(source),
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: AppColors.onAccentOf(context),
                  ),
                  child: const Text("Use the chat's settings"),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// One line of what the notice would fill in.
class _ForkRow extends StatelessWidget {
  const _ForkRow({required this.title, required this.subtitle, this.trailing});

  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(color: AppColors.textPrimary(context)),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary(context),
                  ),
                ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
