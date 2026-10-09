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

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';

/// The line above the composer after the user stopped a reply from the
/// Realism overlay: says no reply came, offers Try again, and stays until
/// the chat moves on or the user dismisses it. Nothing when there is none.
class StoppedReplyNotice extends StatelessWidget {
  const StoppedReplyNotice({super.key, required this.chatService});

  final ChatService chatService;

  @override
  Widget build(BuildContext context) {
    final notice = chatService.stoppedReplyNotice;
    if (notice == null) return const SizedBox.shrink();
    final accent = AppColors.porchAmberOf(context);
    return Container(
      key: const ValueKey('stopped-reply-notice'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerOf(context),
        border: Border(left: BorderSide(color: accent, width: 3)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              notice,
              style: TextStyle(
                color: AppColors.textPrimary(context),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (chatService.canRetryStoppedReply)
            TextButton(
              onPressed: chatService.isGenerating
                  ? null
                  : () => chatService.regenerateLastMessage(),
              style: TextButton.styleFrom(foregroundColor: accent),
              child: const Text('Try again'),
            ),
          IconButton(
            tooltip: 'Dismiss',
            icon: Icon(
              Icons.close,
              size: 16,
              color: AppColors.textSecondary(context),
            ),
            onPressed: chatService.dismissStoppedReplyNotice,
          ),
        ],
      ),
    );
  }
}
