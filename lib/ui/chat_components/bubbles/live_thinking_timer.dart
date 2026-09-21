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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Live "Thinking Ns..." while a think block is open. Chat drives
/// [generating] from [ChatService.isGenerating]; Waifu Coder passes it.
class LiveThinkingTimer extends StatefulWidget {
  const LiveThinkingTimer({super.key, required this.startMs, this.generating});

  /// [ChatMessage.thinkingStartTime] — epoch millis the think block opened.
  final int startMs;
  final bool? generating;

  @override
  State<LiveThinkingTimer> createState() => _LiveThinkingTimerState();
}

class _LiveThinkingTimerState extends State<LiveThinkingTimer> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  bool _live(BuildContext context) {
    if (widget.generating != null) return widget.generating!;
    try {
      return Provider.of<ChatService>(context).isGenerating;
    } on ProviderNotFoundException {
      return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_live(context)) return const SizedBox.shrink();
    final elapsed = DateTime.now().millisecondsSinceEpoch - widget.startMs;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: Colors.tealAccent, // theme-keep: live-think status
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'Thinking ${(elapsed / 1000).toStringAsFixed(0)}s...',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textTertiary(context),
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}
