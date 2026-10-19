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

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// The one Manage Chats list — folder-icon menu and Home right-click both
/// open this. Do not clone a second list. [onNewChat] runs after the dialog
/// closes; Start New Chat is always offered, even with zero or one chat.
Future<void> showChatHistoryDialog({
  required BuildContext context,
  required ChatService chatService,
  Future<List<Map<String, dynamic>>> Function()? loadSessions,
  bool startReplacement = true,
  bool closeOnDeleteCurrent = true,
  Future<void> Function(String sessionId)? onOpen,
  required Future<void> Function() onNewChat,
}) async {
  final load = loadSessions ?? chatService.getSessions;
  final sessions = await load();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => ChatHistoryDialog(
      initialSessions: sessions,
      loadSessions: load,
      currentSessionId: chatService.currentSessionId,
      onOpen: onOpen ?? (id) => chatService.loadSession(id),
      onDelete: (id) =>
          chatService.deleteSession(id, startReplacement: startReplacement),
      onSaveMeta: (id, name, desc) async {
        await chatService.renameSession(id, name);
        await chatService.updateSessionDescription(id, desc);
      },
      closeOnDeleteCurrent: closeOnDeleteCurrent,
      onNewChat: onNewChat,
    ),
  );
}

/// Extracted Manage Chats AlertDialog (look, title, trash, empty copy).
class ChatHistoryDialog extends StatefulWidget {
  const ChatHistoryDialog({
    super.key,
    required this.initialSessions,
    required this.loadSessions,
    this.currentSessionId,
    required this.onOpen,
    required this.onDelete,
    required this.onSaveMeta,
    this.closeOnDeleteCurrent = false,
    required this.onNewChat,
  });

  final List<Map<String, dynamic>> initialSessions;
  final Future<List<Map<String, dynamic>>> Function() loadSessions;
  final String? currentSessionId;
  final Future<void> Function(String sessionId) onOpen;
  final Future<void> Function(String sessionId) onDelete;
  final Future<void> Function(String id, String name, String description)
  onSaveMeta;
  final bool closeOnDeleteCurrent;
  final Future<void> Function() onNewChat;

  @override
  State<ChatHistoryDialog> createState() => _ChatHistoryDialogState();
}

class _ChatHistoryDialogState extends State<ChatHistoryDialog> {
  late List<Map<String, dynamic>> _sessions = widget.initialSessions;

  Future<void> _reload() async {
    final next = await widget.loadSessions();
    if (mounted) setState(() => _sessions = next);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceOf(context),
      title: const Text('Manage Chats'),
      content: SizedBox(
        width: 420,
        height: 350,
        child: Column(
          children: [
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  // The dialog is gone; a failure can only be logged.
                  unawaited(
                    widget.onNewChat().catchError((Object e, StackTrace st) {
                      debugPrint(
                        '[Manage Chats] Start New Chat failed: $e\n$st',
                      );
                    }),
                  );
                },
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Start New Chat'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.porchTerracottaOf(context),
                  side: BorderSide(color: AppColors.porchTerracottaOf(context)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _sessions.isEmpty
                  ? const Center(child: Text('No previous chats found.'))
                  : ListView.builder(
                      itemCount: _sessions.length,
                      itemBuilder: (context, index) => _row(_sessions[index]),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _row(Map<String, dynamic> s) {
    final date = s['date'] as DateTime;
    final dateStr =
        '${date.year}-${date.month}-${date.day} ${date.hour}:${date.minute.toString().padLeft(2, "0")}';
    final isCurrent = s['id'] == widget.currentSessionId;
    final isBranch = s['parent_session'] != null;
    final description = s['session_description'] as String?;

    return ListTile(
      leading: isBranch
          ? Icon(
              Icons.call_split,
              size: 18,
              color: AppColors.formAccentOf(context),
            )
          : null,
      title: Text(s['preview'], style: const TextStyle(fontSize: 14)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            dateStr,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textTertiary(context),
            ),
          ),
          if (description != null && description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                description,
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textTertiary(context),
                  fontStyle: FontStyle.italic,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (isBranch)
            Text(
              '↳ Branched at message #${(s['fork_index'] ?? 0) + 1}',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.formAccentOf(context),
              ),
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(
              Icons.edit,
              size: 16,
              color: AppColors.iconSecondary(context),
            ),
            tooltip: 'Edit name & description',
            onPressed: () => _showEditSessionDialog(s),
          ),
          IconButton(
            icon: const Icon(
              Icons.delete_outline,
              size: 16,
              color: Colors.redAccent,
            ),
            tooltip: 'Delete chat',
            onPressed: () => _confirmDelete(s, isCurrent: isCurrent),
          ),
          if (isCurrent)
            const Padding(
              padding: EdgeInsets.only(left: 4.0),
              child: Icon(Icons.check, size: 16, color: Colors.greenAccent),
            ),
        ],
      ),
      onTap: () {
        Navigator.of(context).pop();
        widget.onOpen(s['id'] as String);
      },
    );
  }

  Future<void> _confirmDelete(
    Map<String, dynamic> s, {
    required bool isCurrent,
  }) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceOf(context),
        title: const Text('Delete Chat?'),
        content: Text(
          'This will permanently delete this chat and all its messages.\n\n"${s['preview']}"',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await widget.onDelete(s['id'] as String);
    if (isCurrent && widget.closeOnDeleteCurrent) {
      if (mounted) Navigator.of(context).pop();
    } else {
      await _reload();
    }
  }

  void _showEditSessionDialog(Map<String, dynamic> session) {
    final nameController = TextEditingController(
      text: session['session_name'] ?? '',
    );
    final descController = TextEditingController(
      text: session['session_description'] ?? '',
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceOf(context),
        title: const Text('Edit Chat Session'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppTextField(
                controller: nameController,
                style: TextStyle(color: AppColors.textPrimary(ctx)),
                decoration: InputDecoration(
                  labelText: 'Session Name',
                  labelStyle: TextStyle(color: AppColors.textSecondary(ctx)),
                  hintText: 'e.g. "Adventure in the forest"',
                  hintStyle: TextStyle(color: AppColors.textTertiary(ctx)),
                  filled: true,
                  fillColor: AppColors.surfaceContainerOf(ctx),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              AppTextField(
                controller: descController,
                style: TextStyle(color: AppColors.textPrimary(ctx)),
                maxLines: 3,
                minLines: 2,
                decoration: InputDecoration(
                  labelText: 'Description',
                  labelStyle: TextStyle(color: AppColors.textSecondary(ctx)),
                  hintText: 'Optional — appears under the timestamp',
                  hintStyle: TextStyle(color: AppColors.textTertiary(ctx)),
                  filled: true,
                  fillColor: AppColors.surfaceContainerOf(ctx),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary(ctx)),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              await widget.onSaveMeta(
                session['id'] as String,
                nameController.text.trim(),
                descController.text.trim(),
              );
              if (ctx.mounted) Navigator.of(ctx).pop();
              await _reload();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.formAccentOf(context),
              foregroundColor: AppColors.onAccentOf(context),
            ),
            child: Text(
              'Save',
              style: TextStyle(color: AppColors.onAccentOf(context)),
            ),
          ),
        ],
      ),
    );
  }
}
