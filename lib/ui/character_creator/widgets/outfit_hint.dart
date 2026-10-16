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

import 'package:front_porch_ai/ui/character_creator/widgets/creator_hint_box.dart';

/// The Realism step's note after the first message was rewritten on the
/// Greetings step (#370): the outfit still follows the old one, and nothing
/// was changed. Offers a re-read or to keep it. Drawn from the approved
/// "Realism step: the hint after a new first message" sketch. The twin of
/// `ProfileHint`; both are a [CreatorHintBox].
class OutfitHint extends StatelessWidget {
  const OutfitHint({
    super.key,
    required this.reading,
    required this.onReread,
    required this.onKeep,
    this.error,
  });

  /// The re-read is running.
  final bool reading;
  final VoidCallback onReread;
  final VoidCallback onKeep;
  final String? error;

  @override
  Widget build(BuildContext context) => CreatorHintBox(
    key: const ValueKey('outfit-hint'),
    title: 'The first message changed',
    body:
        'The outfit below was set from the old first message. Nothing '
        'was changed for you.',
    action: 'Re-read the outfit from it',
    actionRunning: 'Reading the outfit…',
    keep: 'Keep this outfit',
    running: reading,
    onAction: onReread,
    onKeep: onKeep,
    actionKey: const ValueKey('outfit-reread'),
    keepKey: const ValueKey('outfit-keep'),
    error: error,
    errorKey: const ValueKey('outfit-hint-error'),
  );
}
