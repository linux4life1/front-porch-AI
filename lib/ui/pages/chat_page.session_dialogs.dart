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
//
// ChatPage session dialogs: group settings, import/export, clear-chat
// confirmation. Manage Chats lives in chat_history_dialog.dart (shared with
// Home). Each takes the chat page's context.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/utils.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/ui/dialogs/dialogs.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';

/// Group Settings, from the sidebar button.
void showGroupSettings(BuildContext context, ChatService chatService) {
  final groupRepo = Provider.of<GroupChatRepository>(context, listen: false);
  showDialog(
    context: context,
    // Outside tap used to discard General the same way X/Close did.
    barrierDismissible: false,
    builder: (dialogContext) =>
        GroupSettingsDialog(chatService: chatService, groupRepo: groupRepo),
  );
}

/// Import Chat: pick a .fpchat / SillyTavern file and load it into the open
/// chat, asking first when it was exported for a different character.
Future<void> importChatPackageFile(BuildContext context) async {
  try {
    final result = await GuardedPicker.pickFiles(
      context,
      category: PickerPrefs.catImport,
      type: FileType.custom,
      allowedExtensions: ['fpchat', 'json', 'jsonl'],
    );

    if (result == null || result.files.isEmpty) return;

    // path is null on web blob: / Android content:// — read bytes, don't skip.
    final bytes = await result.files.single.readAsBytes();

    if (!context.mounted) return;

    final chatService = Provider.of<ChatService>(context, listen: false);
    final outcome = await chatService.importChatPackage(
      bytes,
      onCharacterMismatch: (packageName, activeName) async {
        if (!context.mounted) return false;
        final choice = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.surfaceOf(ctx),
            title: const Text('Different character'),
            content: Text(
              'This chat was exported for "$packageName", but the open '
              'card is "$activeName".\n\n'
              'Restore full Front Porch state anyway, or import dialogue only?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Dialogue only'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.formAccentOf(context),
                  foregroundColor: AppColors.onAccentOf(context),
                ),
                child: const Text('Full restore'),
              ),
            ],
          ),
        );
        return choice ?? false;
      },
    );

    if (!context.mounted) return;

    final msg = outcome.fullRestore
        ? (outcome.warning != null
              ? 'Chat imported (with note: ${outcome.warning})'
              : 'Chat imported with full Front Porch state')
        : (outcome.warning != null
              ? 'Chat imported as dialogue only (${outcome.warning})'
              : 'Chat imported (dialogue only)');

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.formAccentOf(context),
      ),
    );
  } catch (e) {
    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceOf(context),
        title: const Text('Import Failed'),
        content: Text('Error importing chat: $e'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

/// Export Chat as a full Front Porch package or a SillyTavern transcript.
Future<void> exportChatFile(BuildContext context) async {
  try {
    final chatService = Provider.of<ChatService>(context, listen: false);
    if (chatService.messages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('No chat to export'),
          backgroundColor: AppColors.formAccentOf(context),
        ),
      );
      return;
    }

    final mode = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceOf(ctx),
        title: const Text('Export Chat'),
        content: const Text(
          'Full Front Porch keeps Realism, Needs, swipes, journal, Growth, '
          'and objectives so you can reimport and fork mid-history.\n\n'
          'Transcript is SillyTavern JSONL (dialogue only) for other apps.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'transcript'),
            child: const Text('Transcript (JSONL)'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, 'fpchat'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.formAccentOf(context),
              foregroundColor: AppColors.onAccentOf(context),
            ),
            child: const Text('Full Front Porch'),
          ),
        ],
      ),
    );
    if (mode == null || !context.mounted) return;

    final characterName =
        chatService.activeCharacter?.name ??
        chatService.activeGroup?.name ??
        'chat';
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;

    if (mode == 'fpchat') {
      final bytes = await chatService.exportToFpchat();
      if (bytes == null) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('No chat to export'),
            backgroundColor: AppColors.formAccentOf(context),
          ),
        );
        return;
      }
      final fileName = '${characterName}_$timestamp.fpchat';
      final outPath = await GuardedPicker.saveFile(
        context,
        category: PickerPrefs.catExport,
        bytes: bytes,
        dialogTitle: 'Export Full Front Porch Chat',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['fpchat'],
      );
      if (outPath == null) return;
    } else {
      final jsonl = chatService.exportToSillyTavern();
      if (jsonl == null) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('No chat to export'),
            backgroundColor: AppColors.formAccentOf(context),
          ),
        );
        return;
      }
      final fileName = '${characterName}_$timestamp.jsonl';
      final outPath = await GuardedPicker.saveFile(
        context,
        category: PickerPrefs.catExport,
        bytes: Uint8List.fromList(utf8.encode(jsonl)),
        dialogTitle: 'Export SillyTavern JSONL',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['jsonl', 'json'],
      );
      if (outPath == null) return;
    }

    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          mode == 'fpchat'
              ? 'Full Front Porch chat exported'
              : 'Transcript exported',
        ),
        backgroundColor: AppColors.formAccentOf(context),
      ),
    );
  } catch (e) {
    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceOf(context),
        title: const Text('Export Failed'),
        content: Text('Error exporting chat: $e'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

/// New Chat, after a confirm (the current chat stays in Manage Chats).
void showNewChatConfirmation(BuildContext context) {
  final chatService = Provider.of<ChatService>(context, listen: false);
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppColors.surfaceOf(context),
      title: const Text('New Chat'),
      content: const Text(
        'Start a fresh conversation. Your current one is saved in Manage Chats.',
      ),
      actions: [
        warmDialogCancel(context),
        warmDialogConfirm(
          context,
          label: 'New Chat',
          onPressed: () {
            chatService.startNewChat();
            Navigator.of(context).pop();
          },
        ),
      ],
    ),
  );
}

/// Manage Chats for the open character or group.
void showManageChats(BuildContext context) {
  final chatService = Provider.of<ChatService>(context, listen: false);
  showChatHistoryDialog(
    context: context,
    chatService: chatService,
    onNewChat: chatService.startNewChat,
  );
}
