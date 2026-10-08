// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/storage.dart';

import 'launch_choice_row.dart';

/// "Keep recent chats ready", in Advanced Launch Options: how many chats
/// besides the open one the app keeps ready in KoboldCpp's memory. Off by
/// default. Takes effect at once.
class KoboldKeepRecentRow extends StatelessWidget {
  const KoboldKeepRecentRow({
    super.key,
    required this.settings,
    required this.accent,
  });

  final BackendSettings settings;
  final Color accent;

  @override
  Widget build(BuildContext context) => LaunchChoiceRow(
    title: 'Keep recent chats ready',
    blurb:
        'Besides the chat you have open, keeps the ones you used last ready '
        'in system memory, so going back to one is quick. Off keeps only the '
        'open chat, and frees its memory when you leave it. Fewer are kept '
        'when memory is short.',
    choices: kKoboldKeepRecentChoices,
    chosen: settings.keepRecentChats,
    label: koboldKeepRecentLabel,
    onChoose: settings.setKeepRecentChats,
    accent: accent,
  );
}
