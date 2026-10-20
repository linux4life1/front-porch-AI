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
// The ChatPage input bar: resize handle, photo-attachment preview, captioner
// status, persona switcher, and the seams to the chat-management menu and the
// action buttons (chat_page.input_actions.dart). Also the remembered height
// of the message box.

import 'dart:async';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';
import 'package:front_porch_ai/ui/dialogs/dialogs.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/services/caption/local_caption_service.dart';
import 'package:front_porch_ai/ui/pages/chat_page.input_actions.dart';

/// The message box's minimum height in lines (1–8), dragged on the bar's
/// handle and remembered across launches. [update] is the page's setState.
class ComposerHeight {
  ComposerHeight({required this.update});

  final void Function(VoidCallback fn) update;

  int minLines = 1;
  double _dragAccumulator = 0;

  /// Restore the remembered height.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    update(() {
      minLines = prefs.getInt('input_min_lines') ?? 1;
    });
  }

  Future<void> _save(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('input_min_lines', value);
  }

  /// A drag on the handle starts or ends.
  void resetDrag() => _dragAccumulator = 0;

  /// The handle moved [deltaPixels] (up is negative = taller).
  void drag(double deltaPixels) {
    _dragAccumulator -= deltaPixels;
    final pixelsPerLine = 8.0;
    final deltaLines = (_dragAccumulator / pixelsPerLine).floor();
    if (deltaLines != 0) {
      _dragAccumulator -= deltaLines * pixelsPerLine;
      final newLines = minLines + deltaLines;
      if (newLines >= 1 && newLines <= 8) {
        update(() => minLines = newLines);
        _save(newLines);
      }
    }
  }
}

/// The whole visible input bar — the old "── Input bar ──" Column.
class ChatInputBar extends StatelessWidget {
  const ChatInputBar({
    super.key,
    required this.chatService,
    required this.pendingImageBytes,
    required this.pendingImageVisionOk,
    required this.pendingImageBlindReason,
    required this.onRemoveImage,
    required this.onImage,
    required this.onResizeReset,
    required this.onResize,
    required this.menu,
    required this.actions,
  });

  final ChatService chatService;
  final Uint8List? pendingImageBytes;
  final bool? pendingImageVisionOk;
  final String? pendingImageBlindReason;
  final VoidCallback onRemoveImage;

  /// A photo dropped on the composer.
  final Future<void> Function(Uint8List bytes) onImage;
  final VoidCallback onResizeReset;
  final ValueChanged<double> onResize;

  /// The chat-management menu, left of the action buttons.
  final Widget menu;
  final ChatInputActionStrip actions;

  @override
  Widget build(BuildContext context) {
    return ComposerDropZone(
      enabled: !chatService.isGenerating && !chatService.observerMode,
      onImage: onImage,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Resize handle — drag up/down to adjust input height
          MouseRegion(
            cursor: SystemMouseCursors.resizeRow,
            child: GestureDetector(
              onVerticalDragStart: (_) => onResizeReset(),
              onVerticalDragUpdate: (details) => onResize(details.delta.dy),
              onVerticalDragEnd: (_) => onResizeReset(),
              behavior: HitTestBehavior.opaque,
              child: Container(
                height: 16,
                margin: const EdgeInsets.symmetric(horizontal: 20),
                color: Colors.transparent,
                child: Center(
                  child: Container(
                    height: 3,
                    width: 50,
                    decoration: BoxDecoration(
                      color: InkColors.handleOf(context),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Pending photo attachment preview (remove ✕ + blind-model note:
          // offline-captioner fallback when installed, warning otherwise)
          if (pendingImageBytes != null)
            Builder(
              builder: (context) {
                LocalCaptionService.instance.configure(
                  Provider.of<StorageService>(context, listen: false).rootPath,
                );
                return PendingImageChip(
                  bytes: pendingImageBytes!,
                  visionOk: pendingImageVisionOk,
                  blindReason: pendingImageBlindReason,
                  onRemove: onRemoveImage,
                );
              },
            ),
          // Offline captioner at work — sending is quiet for a few seconds
          // while the photo is described, so say what's happening.
          AnimatedBuilder(
            animation: LocalCaptionService.instance,
            builder: (context, _) {
              if (!LocalCaptionService.instance.isCaptioning) {
                return const SizedBox.shrink();
              }
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                color: AppColors.surfaceContainerOf(context),
                child: Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: StatusColors.infoOf(context),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Reading the photo so the character knows what it '
                        'shows…',
                        style: TextStyle(
                          color: AppColors.textSecondary(context),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerOf(context),
              border: Border(
                top: BorderSide(
                  color: AppColors.borderOf(context).withValues(alpha: 0.35),
                ),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,

              children: [
                // Persona Switcher
                Consumer<UserPersonaService>(
                  builder: (context, personaService, _) {
                    final persona = personaService.persona;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0, bottom: 6),
                      child: GestureDetector(
                        onTap: () => showDialog(
                          context: context,
                          builder: (_) => const UserPersonaDialog(),
                        ),
                        child: CircleAvatar(
                          radius: 16,
                          backgroundColor: InkColors.gripOf(context),
                          backgroundImage: persona.avatarPath != null
                              ? FileImage(File(persona.avatarPath!))
                              : null,
                          child: persona.avatarPath == null
                              ? Icon(
                                  Icons.person,
                                  size: 18,
                                  color: AppColors.iconSecondary(context),
                                )
                              : null,
                        ),
                      ),
                    );
                  },
                ),
                menu,
                ...actions.build(context),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
