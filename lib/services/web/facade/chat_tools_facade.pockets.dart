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

part of 'chat_tools_facade.dart';

/// Pockets and Wardrobe: what they are wearing and carrying, plus the
/// hand-add and erase affordances the desktop PocketsRow has.
extension ChatToolsFacadePockets on ChatToolsFacade {
  // ── Toggles (chat-scoped; delegate to the same ChatService methods the
  //    desktop sidebar calls, which persist + handle group parity) ──────────
  /// Strike one pocket item by hand from the web panel — the same eraser the
  /// desktop chips have. The extraction bet's whole defense is "a wrong entry
  /// is one tap from corrected", and the PWA had zero taps (hostile review
  /// 2026-08-11). Delegates to the SAME [ChatService.removePocketItem] the
  /// desktop rows call; the section strings mirror the snapshot's JSON keys.
  /// Unknown section or missing chat is a silent no-op — a stale bundle must
  /// never turn a tap into a 500.
  Future<void> removePocketItem({
    String? participantId,
    required String section,
    required int index,
  }) async {
    final focused = _focusedParticipant(participantId);
    // Guests have no record — without this, the strike lands on the HOST's
    // kit (see _isGuestFocus). The panel is hidden for a guest focus, but
    // the endpoint must hold the same line a stale bundle could cross.
    if (_isGuestFocus(focused)) return;
    final card = focused?.card ?? _chat.activeCharacter;
    if (card == null) return;
    final target = switch (section) {
      'worn' => PocketSection.worn,
      'carrying' => PocketSection.carrying,
      'set_aside' => PocketSection.setAside,
      _ => null,
    };
    if (target == null || index < 0) return;
    await _chat.removePocketItem(
      _chat.characterIdFor(card),
      section: target,
      index: index,
    );
    _notify();
  }

  /// Add one pocket item by hand from the web panel — the other half of the
  /// eraser, delegating to the SAME [ChatService.addPocketItem] the desktop
  /// dialog calls. [correction] is additive (stale bundles omit it).
  Future<void> addPocketItem({
    String? participantId,
    required String section,
    required String name,
    bool gift = false,
    bool correction = false,
  }) async {
    final focused = _focusedParticipant(participantId);
    // Same guest guard as the eraser — an add would otherwise write the
    // HOST's record under the guest's name.
    if (_isGuestFocus(focused)) return;
    final card = focused?.card ?? _chat.activeCharacter;
    if (card == null) return;
    final target = switch (section) {
      'worn' => PocketSection.worn,
      'carrying' => PocketSection.carrying,
      'set_aside' => PocketSection.setAside,
      _ => null,
    };
    if (target == null || name.trim().isEmpty) return;
    await _chat.addPocketItem(
      _chat.characterIdFor(card),
      section: target,
      name: name,
      gift: gift,
      correction: correction,
    );
    _notify();
  }

  /// Belongings / item-memory cards (web panel — desktop Journal "Belongings"
  /// tab parity). Placement notes only (`category == item`). Owner defaults
  /// like [calendar]. Additive endpoint; old clients never call it.
  Future<Map<String, dynamic>> belongings(String? ownerId) async {
    final sessionId = _chat.currentSessionId;
    final owners = _chat.cast.where((p) => !p.isLite).toList();
    final owner =
        owners.where((p) => p.id == ownerId).firstOrNull ?? owners.firstOrNull;
    final rows = <Map<String, dynamic>>[];
    if (sessionId != null && owner != null) {
      for (final card in await _chat.journalStore.cardsFor(
        sessionId,
        owner.id,
      )) {
        if (card.category != 'item') continue;
        final (day, _) = JournalStore.stampOf(card);
        rows.add({
          'id': card.id,
          'content': card.content,
          'pinned': card.pinned,
          'storyDay': day,
          'item': JournalPhysics.itemOf(card),
        });
      }
    }
    return {'owner': owner?.id, 'ownerName': owner?.name, 'belongings': rows};
  }
}
