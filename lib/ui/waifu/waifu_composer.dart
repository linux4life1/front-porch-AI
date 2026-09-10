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
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';
import 'package:front_porch_ai/ui/waifu/waifu_slash_menu.dart';
import 'package:front_porch_ai/ui/waifu/waifu_stop_bar.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Bare Enter sends. Shift+Enter (or a held-down repeat) stays a newline.
KeyEventResult waifuComposerKeyEvent(
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
class WaifuComposer extends StatelessWidget {
  const WaifuComposer({
    super.key,
    required this.controller,
    required this.session,
    required this.onSend,
    required this.onPickSlash,
    required this.onStop,
    this.onQueueChanged,
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
  final WaifuSession session;
  final VoidCallback onSend;
  final ValueChanged<WaifuSlashCommand> onPickSlash;
  final VoidCallback onStop;
  final VoidCallback? onQueueChanged;
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
      enabled: onDropImage != null,
      onImage: onDropImage ?? (_) async {},
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              final matches = waifuSlashMatches(value.text);
              if (matches.isEmpty) return const SizedBox.shrink();
              return WaifuSlashMenu(
                matches: matches,
                prefix: waifuSlashPrefix(value.text) ?? '',
                onPick: onPickSlash,
              );
            },
          ),
          if (session.running) WaifuStopBar(onStop: onStop),
          if (session.queued.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Wrap(
                key: const Key('waifu-queued'),
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (var i = 0; i < session.queued.length; i++)
                    InputChip(
                      key: Key('waifu-queued-$i'),
                      label: Text(
                        session.queued[i].text,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onDeleted: onQueueChanged == null
                          ? null
                          : () {
                              session.queued.removeAt(i);
                              onQueueChanged!();
                            },
                      backgroundColor: AppColors.surfaceContainerOf(context),
                      side: BorderSide(color: AppColors.borderOf(context)),
                      labelStyle: TextStyle(
                        color: AppColors.textPrimary(context),
                        fontSize: 12,
                      ),
                      deleteIconColor: AppColors.iconSecondary(context),
                    ),
                ],
              ),
            ),
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
                    key: const Key('waifu-attach-photo'),
                    tooltip: 'Attach photo',
                    onPressed: onAttach,
                    icon: Icon(
                      Icons.add_photo_alternate_outlined,
                      color: amber,
                    ),
                  ),
                Expanded(
                  child: Focus(
                    onKeyEvent: (node, event) => waifuComposerKeyEvent(
                      event,
                      shiftPressed: HardwareKeyboard.instance.isShiftPressed,
                      enabled: true,
                      onSend: onSend,
                    ),
                    child: TextField(
                      key: const Key('waifu-composer'),
                      controller: controller,
                      enabled: true,
                      minLines: 1,
                      maxLines: 10,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      style: TextStyle(color: AppColors.textPrimary(context)),
                      decoration: InputDecoration(
                        hintText: session.running
                            ? 'Queue a follow-up for ${session.coworker.name}'
                            : 'A task for ${session.coworker.name}',
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
                  key: const Key('waifu-undo'),
                  tooltip: 'Undo her last write',
                  onPressed: session.running || !canUndo ? null : onUndo,
                  icon: Icon(Icons.undo, color: amber),
                ),
                IconButton(
                  key: const Key('waifu-redo'),
                  tooltip: 'Redo her last write',
                  onPressed: session.running || !canRedo ? null : onRedo,
                  icon: Icon(Icons.redo, color: amber),
                ),
                IconButton(
                  key: const Key('waifu-send'),
                  tooltip: session.running ? 'Queue follow-up' : 'Send',
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
