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

part of 'message_bubble.dart';

/// The thought chip / expanded-thinking / live-timer / message-body /
/// inline-image / realism-indicator run of sibling widgets that sits
/// beneath the header row. Returned as a list because these are already
/// collection-`if` elements in the shell's `Column.children` (spread with
/// `...`), including the thought-only-hint vs. `StyledChatMessage`
/// if/else pair, which moves as ONE element (never separate the hint from
/// `StyledChatMessage`).
extension _BubbleContent on _MessageBubbleState {
  List<Widget> _thoughtAndBodyChildren(
    BuildContext context,
    ResolvedThemeData theme,
  ) {
    return [
      if (!message.isUser) const SizedBox(height: 4),
      // Collapsible Thought chip
      if (!message.isUser && message.hasThinking)
        GestureDetector(
          key: const Key('thought-toggle'),
          behavior: HitTestBehavior.opaque,
          onTap: _toggleThought,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _thoughtOpen ? Icons.expand_more : Icons.chevron_right,
                  size: 20,
                  color: AppColors.textSecondary(context),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.resolve(
                      context,
                      const Color(0xFF2A4A5A),
                      const Color(0xFFE0F2FE),
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Thought',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.tealAccent,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.lightbulb_outline,
                  size: 16,
                  color: AppColors.porchAmberOf(context),
                ),
              ],
            ),
          ),
        ),
      // Expanded thinking details
      if (!message.isUser && message.hasThinking && _thoughtOpen)
        Container(
          margin: const EdgeInsets.only(bottom: 8, left: 20),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.resolve(
              context,
              const Color(0xFF1A2A3A),
              const Color(0xFFE0F2FE),
            ),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.borderOf(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (message.thinkingDurationMs > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    'Thought for ${(message.thinkingDurationMs / 1000).toStringAsFixed(1)}s',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.tealAccent,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              if (message.thinkingContent != null)
                Text(
                  message.thinkingContent!,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary(context),
                  ),
                ),
            ],
          ),
        ),
      // Live thinking timer (extracted widget)
      if (!message.isUser &&
          message.thinkingStartTime != null &&
          message.thinkingDurationMs == 0)
        LiveThinkingTimer(
          startMs: message.thinkingStartTime!,
          generating: widget.isGenerating,
        ),
      // Thought-only reply: the whole message was reasoning,
      // so displayText is empty — say so instead of rendering
      // a bare empty bubble (web has the same hint).
      if (widget.chatService != null &&
          !message.isUser &&
          message.sender != 'System' &&
          message.displayText.isEmpty &&
          (message.thinkingContent?.isNotEmpty ?? false) &&
          !widget.chatService!.isGenerating)
        Text(
          '💭 Only thoughts this turn — Continue or '
          'Regenerate for a spoken reply.',
          style: TextStyle(
            fontSize: 12,
            fontStyle: FontStyle.italic,
            color: AppColors.textTertiary(context),
          ),
        )
      else if (!hasStorage)
        Text(
          message.displayText,
          style: TextStyle(color: AppColors.textPrimary(context)),
        )
      else
        StyledChatMessage(
          text: message.displayText,
          isUser: message.isUser,
          externalImagesAllowed: widget.externalImagesAllowed,
          onRequestImagePermission: widget.onRequestImagePermission,
          character: widget.character ?? widget.chatService?.activeCharacter,
          themePreset: theme.preset,
          themeOverrides: theme.overrides,
        ),
      // Locally generated image (from /image or the Image Studio's
      // "Send to chat") — click to zoom, right-click to save.
      if (message.activeMetadata?['image_path'] is String)
        InlineChatImage(
          path: message.activeMetadata!['image_path'] as String,
          prompt: message.activeMetadata!['image_prompt'] as String?,
        ),
      if (message.activeMetadata != null)
        _buildRealismIndicator(message.activeMetadata!),
    ];
  }
}
