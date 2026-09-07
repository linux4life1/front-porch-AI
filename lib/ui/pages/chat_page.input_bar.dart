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
// action buttons (chat_page.input_actions.dart). Extracted verbatim from
// _buildInputArea (god-file campaign, Tranche A).

part of 'chat_page.dart';

extension _ChatPageInputBar on _ChatPageState {
  /// The whole visible input bar — verbatim the old "── Input bar ──" Column.
  Widget _buildInputBar(BuildContext context, ChatService chatService) {
    return ComposerDropZone(
      enabled: !chatService.isGenerating && !chatService.observerMode,
      onImage: _acceptImageBytes,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Resize handle — drag up/down to adjust input height
          MouseRegion(
            cursor: SystemMouseCursors.resizeRow,
            child: GestureDetector(
              onVerticalDragStart: (_) => _dragAccumulator = 0,
              onVerticalDragUpdate: (details) =>
                  _handleInputResize(details.delta.dy),
              onVerticalDragEnd: (_) => _dragAccumulator = 0,
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
                      color: AppColors.resolve(
                        context,
                        Colors.white38,
                        Colors.black38,
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Pending photo attachment preview (remove ✕ + blind-model note:
          // offline-captioner fallback when installed, warning otherwise)
          if (_pendingImageBytes != null)
            Builder(
              builder: (context) {
                LocalCaptionService.instance.configure(
                  Provider.of<StorageService>(context, listen: false).rootPath,
                );
                return PendingImageChip(
                  bytes: _pendingImageBytes!,
                  visionOk: _pendingImageVisionOk,
                  blindReason: _pendingImageBlindReason,
                  onRemove: () => rebuildState(() {
                    _pendingImageBytes = null;
                    _pendingImageVisionOk = null;
                    _pendingImageBlindReason = null;
                  }),
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
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.tealAccent,
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
                          backgroundColor: AppColors.resolve(
                            context,
                            Colors.white24,
                            Colors.black12,
                          ),
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
                _buildChatManagementMenu(context, chatService),
                ..._buildInputActionButtons(context, chatService),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
