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
import 'package:front_porch_ai/ui/pages/chat_page.input.dart'
    show showNoMicDialog;
import 'package:front_porch_ai/ui/theme/theme.dart';

/// The composer's voice-call button. Voice call is 1:1 only: in a group it
/// stays in its place, greyed, with a tooltip that says so, so the bar holds
/// the same controls in the same spots in a group as in a 1:1.
class ChatCallButton extends StatelessWidget {
  const ChatCallButton({
    super.key,
    required this.chatService,
    required this.onStartCall,
  });

  final ChatService chatService;
  final VoidCallback onStartCall;

  @override
  Widget build(BuildContext context) {
    return Consumer2<SttService, StorageService>(
      builder: (context, sttService, storage, _) {
        if (!storage.sttSettings.sttEnabled) return const SizedBox.shrink();
        final inGroup = chatService.isGroupMode;
        return Tooltip(
          message: inGroup ? '1:1 only' : 'Start voice call',
          child: IconButton(
            icon: Icon(
              Icons.call,
              color: inGroup
                  ? AppColors.textTertiary(context)
                  : AppColors.porchAmberOf(context),
            ),
            onPressed: inGroup || chatService.isGenerating || sttService.isBusy
                ? null
                : () async {
                    final micOk = await sttService.checkMicAvailable();
                    if (!micOk && context.mounted) {
                      showNoMicDialog(context);
                      return;
                    }
                    onStartCall();
                  },
          ),
        );
      },
    );
  }
}
