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

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';

/// A compact, live WYSIWYG micro-chat preview displaying a two-turn exchange
/// using the current chat bubble colors, text colors, typeface, and text scale.
class ChatCapsulePreview extends StatelessWidget {
  const ChatCapsulePreview({
    super.key,
    this.onTapUserBubble,
    this.onTapAiBubble,
  });

  final VoidCallback? onTapUserBubble;
  final VoidCallback? onTapAiBubble;

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final uiSettings = storage.uiSettings;
    final corners = AppCorners.of(context);

    final userBg = uiSettings.globalUserBubbleColor;
    final userFg = uiSettings.globalUserTextColor;
    final aiBg = uiSettings.globalAiBubbleColor;
    final aiFg = uiSettings.globalAiTextColor;
    final dialogue = uiSettings.globalDialogueColor;
    final action = uiSettings.globalActionColor;

    final fontFamily = uiSettings.globalChatFontFamily.isNotEmpty
        ? uiSettings.globalChatFontFamily
        : null;

    final baseSize = (12.5 * uiSettings.textScale).clamp(11.0, 16.0);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerOf(context),
        borderRadius: corners.circular(12),
        border: Border.all(
          color: AppColors.borderOf(context),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'LIVE PREVIEW',
                style: TextStyle(
                  color: AppColors.textTertiary(context),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              Text(
                uiSettings.globalChatFontFamily.isEmpty
                    ? 'Default Font'
                    : uiSettings.globalChatFontFamily,
                style: TextStyle(
                  color: AppColors.textTertiary(context),
                  fontSize: 10,
                  fontFamily: fontFamily,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // AI Character message
          Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Material(
                color: aiBg,
                shape: RoundedRectangleBorder(
                  borderRadius: corners.circular(10),
                  side: BorderSide(
                    color: AppColors.borderOf(context).withValues(alpha: 0.4),
                    width: 0.8,
                  ),
                ),
                child: InkWell(
                  onTap: onTapAiBubble,
                  borderRadius: corners.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: RichText(
                      text: TextSpan(
                        style: TextStyle(
                          color: aiFg,
                          fontFamily: fontFamily,
                          fontSize: baseSize,
                          height: 1.35,
                        ),
                        children: [
                          TextSpan(
                            text: '"I found the notes," ',
                            style: TextStyle(
                              color: dialogue,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          TextSpan(
                            text: '*she smiles*, ',
                            style: TextStyle(
                              color: action,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                          const TextSpan(text: 'right where you left them.'),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // User message
          Align(
            alignment: Alignment.centerRight,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Material(
                color: userBg,
                shape: RoundedRectangleBorder(
                  borderRadius: corners.circular(10),
                  side: BorderSide(
                    color: AppColors.borderOf(context).withValues(alpha: 0.4),
                    width: 0.8,
                  ),
                ),
                child: InkWell(
                  onTap: onTapUserBubble,
                  borderRadius: corners.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Text(
                      'Perfect. Let\'s get to work.',
                      style: TextStyle(
                        color: userFg,
                        fontFamily: fontFamily,
                        fontSize: baseSize,
                        height: 1.35,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
