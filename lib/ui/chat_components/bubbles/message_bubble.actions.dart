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

/// The three action rows beneath a bot message: the first-message
/// alternate-greeting swipe chevrons, the regen/continue/swipe-message
/// row (including the Scene-Guest "host buried under guest replies"
/// regen), and the Suggest-actions button + action pills. Their
/// collection-`if` guards stay in the shell's `Column.children` — only
/// the `Consumer<ChatService>` widget behind each guard moves here.
extension _BubbleActions on _MessageBubbleState {
  Widget _greetingSwipeRow() {
    return Consumer<ChatService>(
      builder: (context, chatService, _) {
        if (!chatService.isSelectableGreeting(index)) {
          return const SizedBox.shrink();
        }
        final allGreetings = chatService.openingAllGreetings;

        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              InkWell(
                onTap: () => chatService.cycleGreeting(-1),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(
                    Icons.chevron_left,
                    size: 20,
                    color: AppColors.textSecondary(context),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '${chatService.greetingIndex + 1}/${allGreetings.length}',
                style: const TextStyle(
                  color: Colors.orangeAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 4),
              InkWell(
                onTap: () => chatService.cycleGreeting(1),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: AppColors.textSecondary(context),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Tooltip(
                message: 'Select greet',
                child: InkWell(
                  onTap: () => _openVariantPicker(
                    title: 'Select greet',
                    messageIndex: index,
                    onSelect: chatService.selectGreeting,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.view_list,
                      size: 18,
                      color: AppColors.porchAmberOf(context),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openVariantPicker({
    required String title,
    required int messageIndex,
    required Future<void> Function(int) onSelect,
  }) async {
    final chat = context.read<ChatService>();
    final chosen = await showVariantPickerDialog(
      context,
      title: title,
      variants: chat.variantsForMessage(messageIndex),
    );
    if (chosen != null && mounted) await onSelect(chosen);
  }

  Widget _messageActionRow() {
    return Consumer<ChatService>(
      builder: (context, chatService, _) {
        final isLastBotMessage =
            index == chatService.messages.length - 1 &&
            !chatService.isGenerating;
        final hasSwipes = message.swipes.length > 1;
        // This host (main character) message is buried under one
        // or more Scene Guest (Lite NPC) replies, so the normal
        // last-message regen can't reach it. Offer a regen that
        // first removes those stale guest replies. (By definition
        // this is never the last message.)
        final isRegenHostBelowGuests =
            index == chatService.regenerableHostBelowGuestsIndex &&
            !chatService.isGenerating;

        // Nothing to show if not last message, no swipes, and not
        // a host buried under guest replies.
        if (!isLastBotMessage && !hasSwipes && !isRegenHostBelowGuests) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // Regen the main character even though a Lite NPC
              // spoke after it — pops the NPC's now-stale reply,
              // regenerates this message, then lets the NPC chime
              // again only if still relevant.
              if (isRegenHostBelowGuests) ...[
                Tooltip(
                  message:
                      'Regenerate main character (removes the NPC’s reply)',
                  child: InkWell(
                    onTap: () => promptRegenCritiqueThen(
                      context,
                      (c) => chatService.regenerateMainCharacter(critique: c),
                    ),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.refresh,
                        size: 20,
                        color: AppColors.resolve(
                          context,
                          Colors.orangeAccent,
                          Colors.orange.shade800,
                        ),
                      ),
                    ),
                  ),
                ),
                if (hasSwipes) const SizedBox(width: 12),
              ],
              // Regen — last bot message only. Greets are static card
              // content; Select greet is the replacement. Continue still
              // belongs on a last greet (it extends the opening line).
              if (isLastBotMessage && index != 0) ...[
                Tooltip(
                  message: 'Regenerate',
                  child: InkWell(
                    onTap: () => promptRegenCritiqueThen(
                      context,
                      (c) => chatService.regenerateLastMessage(critique: c),
                    ),
                    borderRadius: BorderRadius.circular(12),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        Icons.refresh,
                        size: 20,
                        color: Colors.orangeAccent,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              if (isLastBotMessage) ...[
                Tooltip(
                  message: 'Continue generation',
                  child: InkWell(
                    onTap: () => chatService.continueGeneration(),
                    borderRadius: BorderRadius.circular(12),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        Icons.arrow_downward,
                        size: 20,
                        color: Colors.blue,
                      ),
                    ),
                  ),
                ),
                if (hasSwipes) const SizedBox(width: 12),
              ],
              // Swipe arrows — only when multiple swipes exist
              if (hasSwipes) ...[
                InkWell(
                  onTap: () => chatService.swipeMessage(index, -1),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Icons.chevron_left,
                      size: 20,
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '${message.swipeIndex + 1}/${message.swipes.length}',
                  style: TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 4),
                InkWell(
                  onTap: () => chatService.swipeMessage(index, 1),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Tooltip(
                  message: 'Select variant',
                  child: InkWell(
                    onTap: () => _openVariantPicker(
                      title: 'Select variant',
                      messageIndex: index,
                      onSelect: (i) => chatService.selectSwipe(index, i),
                    ),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.view_list,
                        size: 18,
                        color: AppColors.porchAmberOf(context),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _suggestActionsColumn(ResolvedThemeData theme) {
    return Consumer<ChatService>(
      builder: (context, chatService, _) {
        final isLast =
            index == chatService.messages.length - 1 &&
            !chatService.isGenerating;
        if (!isLast) return const SizedBox.shrink();

        final actions = chatService.suggestedActions;
        final isGenerating = chatService.isGeneratingActions;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // "Suggest actions" button
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: InkWell(
                onTap: isGenerating
                    ? null
                    : () => chatService.generateActions(),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 3,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isGenerating)
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: AppColors.textTertiary(context),
                          ),
                        )
                      else
                        Icon(
                          Icons.lightbulb_outline,
                          size: 13,
                          color:
                              theme.accent ?? AppColors.textTertiary(context),
                        ),
                      const SizedBox(width: 5),
                      Text(
                        isGenerating ? 'Thinking...' : 'Suggest actions',
                        style: TextStyle(
                          fontSize: 11,
                          color:
                              theme.accent ?? AppColors.textTertiary(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Action pills
            if (actions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: actions.map((action) {
                    return InkWell(
                      onTap: () => chatService.sendMessage(action),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Text(
                          action,
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                theme.accent ??
                                AppColors.textSecondary(context),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
          ],
        );
      },
    );
  }
}
