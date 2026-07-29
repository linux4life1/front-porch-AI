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

import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/models/world.dart';

/// One lorebook entry plus the book it came from — the book carries the
/// V2 book-level overrides (scanDepth / tokenBudget / recursiveScanning)
/// the engine needs when evaluating the entry.
class LoreEntryRef {
  final LorebookEntry entry;
  final Lorebook book;

  /// Where the entry lives ("group", "world:name", "char:name") — used
  /// for debug/overflow reporting, never for logic.
  final String sourceLabel;

  const LoreEntryRef({
    required this.entry,
    required this.book,
    required this.sourceLabel,
  });
}

/// The ONE enumerator of every lorebook entry in play for the current
/// context. Replaces the five near-identical collection loops that used to
/// live in generation, impersonation, the sidebar getter, the pre-AI
/// snapshot, and the scanner.
///
/// Enumeration order (stable): chat book → group book → group worlds → per-character
/// inline book + attached worlds (members only when [inherit] is true or
/// there is no group). No filtering happens here — callers apply their own
/// active/enabled predicates so the scanner (which needs ALL enabled
/// entries) and the injector (which needs active ones) share one source.
///
/// [groupLorebook] must be the LIVE cached instance owned by ChatService —
/// never a fresh parse — or trigger state written by the scanner would be
/// lost between scan and injection (the pre-Phase-2 group lorebook bug).
List<LoreEntryRef> collectLoreEntryRefs({
  required List<CharacterCard> characters,
  Lorebook? chatLorebook,
  Lorebook? groupLorebook,
  /// Per-chat attached worlds (UUID preferred; name still accepted).
  List<String> chatWorldIds = const [],
  /// @Deprecated Prefer [chatWorldIds]. Group template names/ids used as
  /// fallback when the chat has no chat_worlds rows yet.
  List<String> groupWorldNames = const [],
  /// Resolve by UUID or display name.
  required World? Function(String idOrName) resolveWorld,
  bool inherit = true,
}) {
  final refs = <LoreEntryRef>[];
  final seenWorldIds = <String>{};

  // Chat-scoped book scans and enumerates FIRST (ST order: chat book first).
  if (chatLorebook != null) {
    for (final e in chatLorebook.entries) {
      refs.add(LoreEntryRef(entry: e, book: chatLorebook, sourceLabel: 'chat'));
    }
  }

  if (groupLorebook != null) {
    for (final e in groupLorebook.entries) {
      refs.add(LoreEntryRef(entry: e, book: groupLorebook, sourceLabel: 'group'));
    }
  }

  void addWorld(String ref) {
    final world = resolveWorld(ref);
    if (world == null) return;
    final key = world.id.isNotEmpty ? world.id : world.name;
    if (!seenWorldIds.add(key)) return;
    for (final e in world.lorebook.entries) {
      refs.add(LoreEntryRef(
        entry: e,
        book: world.lorebook,
        sourceLabel: 'world:${world.name}',
      ));
    }
  }

  // Chat attachments first (Living Worlds); fall back to group template list.
  final worldRefs =
      chatWorldIds.isNotEmpty ? chatWorldIds : groupWorldNames;
  for (final ref in worldRefs) {
    addWorld(ref);
  }

  if (inherit) {
    for (final ch in characters) {
      final book = ch.lorebook;
      if (book != null) {
        for (final e in book.entries) {
          refs.add(LoreEntryRef(entry: e, book: book, sourceLabel: 'char:${ch.name}'));
        }
      }
      for (final worldName in ch.worldNames) {
        addWorld(worldName);
      }
    }
  }

  return refs;
}
