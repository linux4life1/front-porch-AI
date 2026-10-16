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

/// The Greetings step's note when the profile reads differently from the
/// one the greetings were written from (docs/design/creator-ui-spec.md,
/// "Greetings step hint"). Nothing is changed until asked. The twin of
/// `OutfitHint`; both are a [CreatorHintBox].
class ProfileHint extends StatelessWidget {
  const ProfileHint({
    super.key,
    required this.rewriting,
    required this.onRewrite,
    required this.onKeep,
  });

  /// "Rewrite the greetings from it" is going through the greetings.
  final bool rewriting;
  final VoidCallback onRewrite;
  final VoidCallback onKeep;

  @override
  Widget build(BuildContext context) => CreatorHintBox(
    key: const ValueKey('profile-hint'),
    title: 'The profile changed',
    body:
        'These greetings were written from the old Description and '
        'Personality. Nothing was changed for you.',
    action: 'Rewrite the greetings from it',
    actionRunning: 'Rewriting the greetings…',
    keep: 'Keep them',
    running: rewriting,
    onAction: onRewrite,
    onKeep: onKeep,
    actionKey: const ValueKey('profile-hint-rewrite'),
    keepKey: const ValueKey('profile-hint-keep'),
  );
}
