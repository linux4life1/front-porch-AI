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
// Sidebar shell for ChatPage: the resize handle, the right-sidebar frame and
// its section order, the participant roster, and the Director controls.
// Extracted verbatim from chat_page.dart (god-file campaign, Tranche A) —
// part of the same library, so every private member is still in scope.
// The portrait and Main Settings blocks live in chat_page.sidebar_widgets.dart.

part of 'chat_page.dart';

extension _ChatPageSidebar on _ChatPageState {
  /// This page's key for [m]'s bubble, minted on first build (see the
  /// `_bubbleKeys` field doc — page-owned so two live chat routes can never
  /// collide on one GlobalKey).
  GlobalKey _bubbleKeyFor(ChatMessage m) =>
      _bubbleKeys.putIfAbsent(m, GlobalKey.new);

  /// Journal receipts tap-to-jump: seek the chat to the message at
  /// [position] (the stored absolute index), then flash the bubble so the
  /// eye finds it. The seek itself lives in message_jump.dart. Lives in the
  /// sidebar part because the sidebar's receipts are what call it.
  Future<void> _jumpToMessage(int position) async {
    final messages = Provider.of<ChatService>(context, listen: false).messages;
    if (position < 0 || position >= messages.length) return;
    final target = messages[position];
    await jumpToMessage(
      controller: _scrollController,
      messages: messages,
      target: target,
      // This page's own keys. Null for a not-yet-built bubble — the seek
      // treats that as "keep paging"; the itemBuilder mints the key the
      // moment the bubble materializes.
      keyOf: (m) => _bubbleKeys[m],
    );
    if (!mounted) return;
    rebuildState(() => _jumpFlashMessage = target);
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (mounted && identical(_jumpFlashMessage, target)) {
        rebuildState(() => _jumpFlashMessage = null);
      }
    });
  }

  /// Wraps a sidebar widget with a draggable resize handle on its left edge.
  Widget _buildResizableSidebar({required Widget child}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Drag handle
        MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          child: GestureDetector(
            onHorizontalDragUpdate: (details) {
              rebuildState(() {
                double newWidth = _sidebarWidth - details.delta.dx;
                if (newWidth < SidebarTokens.minWidth) {
                  _sidebarWidth = 0; // Snap to closed
                } else {
                  _sidebarWidth = newWidth.clamp(
                    SidebarTokens.minWidth,
                    SidebarTokens.maxWidth,
                  );
                }
              });
            },
            child: Container(
              width: 6,
              color: Colors.transparent,
              child: Center(
                child: Container(
                  width: 3,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.resolve(
                      context,
                      Colors.white24,
                      Colors.black12,
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_sidebarWidth > 0) SizedBox(width: _sidebarWidth, child: child),
      ],
    );
  }

  Widget _buildRightSidebar(ChatService chatService) {
    final focused = _focusedParticipant(chatService);
    if (focused == null) return const SizedBox.shrink();
    final character = focused.card;
    final isGroup = chatService.isGroupMode;
    final cast = chatService.cast;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        border: Border(
          left: BorderSide(
            color: AppColors.borderOf(context).withValues(alpha: 0.35),
          ),
        ),
      ),
      child: Column(
        children: [
          _buildSidebarPortrait(character, isGroup),
          _buildSidebarMainSettings(chatService, character, isGroup),

          // ── Group Settings (group only; sits directly under Main Settings,
          //    above the cast roster, so the whole-group controls are found
          //    before per-character ones) ──
          if (isGroup)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: AppColors.borderOf(context).withValues(alpha: 0.35),
                  ),
                ),
              ),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _showGroupSettingsDialog(chatService),
                  icon: const Icon(Icons.settings, size: 16),
                  label: const Text('Group Settings'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary(context),
                    side: BorderSide(
                      color: AppColors.borderOf(context).withValues(alpha: 0.4),
                    ),
                  ),
                ),
              ),
            ),

          // ── Participant roster (only when more than one speaker) ──
          if (cast.length > 1)
            _buildParticipantRoster(chatService, cast, focused),

          // ── Director controls (group turn-taking) ──
          if (isGroup) _buildDirectorControls(chatService),

          Expanded(
            child: SidebarBody(
              chatService: chatService,
              focused: focused,
              onSpinRequested: () => _showChanceTimeOverlay(context),
              onJumpToMessage: _jumpToMessage,
              resolveCharImage: _resolveCharImage,
              draft: _controller,
              onOpenEditFromEnv: () {
                unawaited(
                  _openEditCharacterDialog(
                    character,
                    ensureRelationshipVisible: true,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Horizontal roster of all cast participants. Tapping one focuses its
  /// per-character sidebar sections. Shown only when more than one speaker is
  /// present (1:1 + guests, or a group).
  Widget _buildParticipantRoster(
    ChatService chatService,
    List<ChatParticipant> cast,
    ChatParticipant focused,
  ) {
    return Container(
      height: 66,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AppColors.borderOf(context).withValues(alpha: 0.35),
          ),
        ),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: cast.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final p = cast[i];
          final isFocused = p.id == focused.id;
          final color = _ChatPageState._groupCharacterColor(i);
          final img = p.card.imagePath != null
              ? _resolveCharImage(p.card.imagePath!)
              : null;
          return InkWell(
            onTap: () => rebuildState(() => _focusedParticipantId = p.id),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isFocused ? color : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: color,
                    backgroundImage: img != null ? FileImage(img) : null,
                    child: img == null
                        ? Text(
                            p.name.isNotEmpty ? p.name[0] : '?',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 2),
                SizedBox(
                  width: 48,
                  child: Text(
                    p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 9,
                      color: isFocused
                          ? AppColors.textPrimary(context)
                          : AppColors.textTertiary(context),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Group turn-taking controls (Group Settings + Director Mode + response
  /// delay). Shown when the chat has scheduled speakers (a group).
  Widget _buildDirectorControls(ChatService chatService) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AppColors.borderOf(context).withValues(alpha: 0.35),
          ),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                Icons.movie_creation,
                size: 16,
                color: AppColors.iconSecondary(context),
              ),
              const SizedBox(width: 8),
              Text(
                'Director Mode',
                style: TextStyle(
                  color: AppColors.textSecondary(context),
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              Switch(
                value: chatService.observerMode,
                activeTrackColor: Colors.amberAccent,
                onChanged: chatService.isGenerating
                    ? null
                    : (val) => chatService.setObserverMode(val),
              ),
            ],
          ),
          if (chatService.observerMode) ...[
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 4),
              child: Text(
                'Characters chat autonomously. Use the input box to direct the scene.',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.amberAccent.withValues(alpha: 0.7),
                ),
              ),
            ),
            Consumer<StorageService>(
              builder: (context, storage, _) {
                chatService.directorDelaySec = storage.directorDelay;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Response Delay',
                          style: TextStyle(color: Colors.white54, fontSize: 11),
                        ),
                        const Spacer(),
                        Text(
                          '${(_dragDirectorDelay ?? storage.directorDelay).toStringAsFixed(1)}s',
                          style: const TextStyle(
                            color: Colors.amberAccent,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6,
                        ),
                      ),
                      child: Slider(
                        value: _dragDirectorDelay ?? storage.directorDelay,
                        min: 0.5,
                        max: 60.0,
                        divisions: 119,
                        activeColor: Colors.amberAccent,
                        inactiveColor: Colors.white12,
                        onChanged: (val) =>
                            rebuildState(() => _dragDirectorDelay = val),
                        onChangeEnd: (val) {
                          _dragDirectorDelay = null;
                          storage.setDirectorDelay(val);
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}
