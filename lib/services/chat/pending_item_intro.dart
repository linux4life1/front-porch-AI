// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'package:front_porch_ai/services/chat/pockets.dart';

/// One-shot introduction for an item the USER put into a character's kit from
/// the sidebar (maintainer feature, 2026-08-13). Two flavors, opposite
/// fictions:
///
///  * [gift] — the user handed it over in-scene. The character accepts it
///    KNOWING where it came from.
///  * not a gift — the user conjured it out-of-band (the Easter egg): the
///    character notices something they cannot account for and reacts with
///    surprise ("how did I end up with this?").
///
/// Injected once beside the inventory fragment; `included` is set when a
/// prompt actually carried it, and consumed intros are dropped at the top of
/// the NEXT user turn — not at build time — so a regenerate of the reacting
/// reply reproduces the same reaction (the regen law: identical inputs,
/// identical turn).
class PendingItemIntro {
  final String item;
  final bool gift;
  final PocketSection section;

  /// The chat the add happened in. The queue is keyed per CHARACTER, and a
  /// character can appear in many chats — without this stamp, adding an item
  /// and switching sessions before sending made the reaction fire in the
  /// WRONG chat, about an item that record never had (hostile self-review,
  /// 2026-08-13). The injection wiring filters on it; an intro from another
  /// session stays queued and fires if the user returns to that chat.
  final String? session;
  bool included = false;
  PendingItemIntro(
    this.item, {
    required this.gift,
    required this.section,
    required this.session,
  });
}
