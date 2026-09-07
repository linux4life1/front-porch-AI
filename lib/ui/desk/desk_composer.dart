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

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/caption/local_caption_service.dart';
import 'package:front_porch_ai/services/desk/desk.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';
import 'package:front_porch_ai/ui/desk/desk_slash_menu.dart';
import 'package:front_porch_ai/ui/desk/desk_stop_bar.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Bare Enter sends. Shift+Enter (or a held-down repeat) stays a newline.
KeyEventResult deskComposerKeyEvent(
  KeyEvent event, {
  required bool shiftPressed,
  required bool enabled,
  required VoidCallback onSend,
}) {
  if (!enabled) return KeyEventResult.ignored;
  if (event is! KeyDownEvent) return KeyEventResult.ignored;
  if (event.logicalKey != LogicalKeyboardKey.enter &&
      event.logicalKey != LogicalKeyboardKey.numpadEnter) {
    return KeyEventResult.ignored;
  }
  if (shiftPressed) return KeyEventResult.ignored;
  onSend();
  return KeyEventResult.handled;
}

/// Slash palette, Stop bar, and the growing prompt field.
class DeskComposer extends StatelessWidget {
  const DeskComposer({
    super.key,
    required this.controller,
    required this.session,
    required this.onSend,
    required this.onPickSlash,
    required this.onStop,
    required this.onUndo,
    required this.onRedo,
    this.canUndo = false,
    this.canRedo = false,
    this.pendingImage,
    this.visionOk,
    this.blindReason,
    this.onAttach,
    this.onRemoveImage,
    this.onDropImage,
  });

  final TextEditingController controller;
  final DeskSession session;
  final VoidCallback onSend;
  final ValueChanged<DeskSlashCommand> onPickSlash;
  final VoidCallback onStop;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final bool canUndo;
  final bool canRedo;
  final Uint8List? pendingImage;
  final bool? visionOk;
  final String? blindReason;
  final VoidCallback? onAttach;
  final VoidCallback? onRemoveImage;
  final Future<void> Function(Uint8List bytes)? onDropImage;

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.porchAmberOf(context);
    return ComposerDropZone(
      enabled: !session.running && onDropImage != null,
      onImage: onDropImage ?? (_) async {},
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              final matches = deskSlashMatches(value.text);
              if (matches.isEmpty) return const SizedBox.shrink();
              return DeskSlashMenu(
                matches: matches,
                prefix: deskSlashPrefix(value.text) ?? '',
                onPick: onPickSlash,
              );
            },
          ),
          if (session.running) DeskStopBar(onStop: onStop),
          if (pendingImage != null)
            Builder(
              builder: (context) {
                try {
                  final root = Provider.of<StorageService>(
                    context,
                    listen: false,
                  ).rootPath;
                  LocalCaptionService.instance.configure(root);
                } catch (_) {}
                return PendingImageChip(
                  bytes: pendingImage!,
                  visionOk: visionOk,
                  blindReason: blindReason,
                  onRemove: onRemoveImage ?? () {},
                );
              },
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (onAttach != null)
                  IconButton(
                    key: const Key('desk-attach-photo'),
                    tooltip: 'Attach photo',
                    onPressed: session.running ? null : onAttach,
                    icon: Icon(
                      Icons.add_photo_alternate_outlined,
                      color: amber,
                    ),
                  ),
                Expanded(
                  child: Focus(
                    onKeyEvent: (node, event) => deskComposerKeyEvent(
                      event,
                      shiftPressed: HardwareKeyboard.instance.isShiftPressed,
                      enabled: !session.running,
                      onSend: onSend,
                    ),
                    child: TextField(
                      key: const Key('desk-composer'),
                      controller: controller,
                      enabled: !session.running,
                      minLines: 1,
                      maxLines: 10,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      style: TextStyle(color: AppColors.textPrimary(context)),
                      decoration: InputDecoration(
                        hintText: 'A task for ${session.coworker.name}',
                        filled: true,
                        fillColor: AppColors.surfaceContainerOf(context),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: AppColors.borderOf(context),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  key: const Key('desk-undo'),
                  tooltip: 'Undo her last write',
                  onPressed: session.running || !canUndo ? null : onUndo,
                  icon: Icon(Icons.undo, color: amber),
                ),
                IconButton(
                  key: const Key('desk-redo'),
                  tooltip: 'Redo her last write',
                  onPressed: session.running || !canRedo ? null : onRedo,
                  icon: Icon(Icons.redo, color: amber),
                ),
                if (!session.running)
                  IconButton(
                    key: const Key('desk-send'),
                    onPressed: onSend,
                    icon: Icon(Icons.send, color: amber),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
