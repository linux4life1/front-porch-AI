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

part of '../chat_service.dart';

/// Moving a character's 1:1 chats as `.fpchat` packages: AI Enhance's
/// "bring your chats along" step, and `.porch` character files.
///
/// Deliberately a round-trip through the `.fpchat` exporter/importer
/// (maintainer direction, 2026-08-13) rather than a hand-rolled row copier:
/// the codec already carries messages, swipes, realism stamps, journal
/// cards, growth rings, objectives and images, the importer seeds live
/// realism so the copies cannot bleed into each other, and its background
/// RAG backfill re-embeds the copied history — a second implementation of
/// any of that would be exactly the parallel path the project bans.
extension ChatServiceEnhanceChats on ChatService {
  /// Every 1:1 chat of [card] as an `.fpchat` package, newest first.
  ///
  /// The exporter reads the open chat, so this opens each one in turn.
  /// Throws [ChatImportBusy] when a turn is live: switching chats must never
  /// happen under a reply that is still streaming or settling.
  Future<List<Uint8List>> exportChatPackagesOf(CharacterCard card) async {
    if (_isTurnBusy) throw ChatImportBusy();
    final sessions = await getSessionsForId(card.stableGroupId);
    if (sessions.isEmpty) return const [];
    // Kept in memory: each package is bounded by the codec's own unpacked
    // ceiling, and a typical character has a handful of chats.
    final packages = <Uint8List>[];
    await setActiveCharacter(card);
    for (final s in sessions) {
      await loadSession(s['id'] as String);
      final bytes = await exportToFpchat();
      if (bytes != null) packages.add(bytes);
    }
    return packages;
  }

  /// Restores [packages] (newest first, as [exportChatPackagesOf] lists
  /// them) onto [card] as new chats, oldest first, so the newest is the one
  /// left open. The packages name the exporting card, so the mismatch
  /// callback answers "continue": [card] IS that character, and the point is
  /// keeping the stamps. Returns how many came back with their full state.
  Future<int> importChatPackagesOnto(
    CharacterCard card,
    List<Uint8List> packages, {
    void Function(int done, int total)? onProgress,
  }) async {
    if (packages.isEmpty) return 0;
    final hadChats = (await getSessionsForId(card.stableGroupId)).isNotEmpty;
    await setActiveCharacter(card);
    // A card with no chats opens on a greeting chat it saves on the spot.
    // Here that is only a side effect of opening the card to restore into
    // it, so it goes once the restored chats are in; otherwise it stays as an
    // extra "New Conversation" beside them.
    final opening = hadChats ? null : _currentSessionId;
    var restored = 0;
    for (final bytes in packages.reversed) {
      final result = await importChatPackage(
        bytes,
        onCharacterMismatch: (_, _) async => true,
      );
      if (result.fullRestore) restored++;
      onProgress?.call(restored, packages.length);
    }
    if (opening != null && opening != _currentSessionId) {
      await deleteSession(opening, startReplacement: false);
    }
    return restored;
  }

  /// Copies every chat of [from] onto [to]; returns how many were copied.
  ///
  /// Two phases with ONE active-card flip each way: export every session
  /// under [from], then import each package under [to]. The packages name
  /// the BASE character, so the importer's mismatch callback answers
  /// "continue" — the enhanced copy IS that character, and the whole point
  /// is keeping the stamps. Imports run oldest-first so the newest chat is
  /// the one left OPEN under [to] when the copy finishes — the user lands
  /// in the enhanced character exactly where they left the original.
  ///
  /// Throws [ChatImportBusy] when a turn is live (same contract as
  /// [importChatPackage]); the caller owns surfacing that.
  Future<int> copyChatsForEnhance({
    required CharacterCard from,
    required CharacterCard to,
    void Function(int done, int total)? onProgress,
  }) async {
    // Guard BEFORE the export phase, not just inside importChatPackage:
    // phase 1 flips the active character/session, which must never happen
    // under a reply that is still streaming or settling.
    if (_isTurnBusy) throw ChatImportBusy();
    // Same character on both sides would re-import every chat onto its own
    // owner — instant duplication. Unreachable from the wizard (the target
    // is always a fresh duplicate); this guards the web endpoint's
    // arbitrary ids.
    if (from.dbId != null && from.dbId == to.dbId) {
      throw ArgumentError('copyChatsForEnhance needs two different characters');
    }
    // Phase 1 — export under the base card; phase 2 — import under the
    // enhanced card, oldest first (see doc).
    final packages = await exportChatPackagesOf(from);
    return importChatPackagesOnto(to, packages, onProgress: onProgress);
  }
}
