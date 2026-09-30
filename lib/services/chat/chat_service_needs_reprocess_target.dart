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

/// Who a Reprocess Needs pass would run as, and which needs are on.
///
/// Public getters only — FakeChatService implements those, and probing
/// library-private fields from an extension would throw mid-build on a
/// golden double (same contract as [_lastRagReceiptImpl]).
extension ChatServiceNeedsReprocessTarget on ChatService {
  /// Speaker + enabled keys for a reprocess of [index], or null when the
  /// entry must stay hidden: not reprocessable, Needs off, every need off,
  /// or a group speaker that cannot be resolved to a roster card.
  ({String speaker, List<String> enabled, CharacterCard? card})?
  reprocessNeedsTargetFor(int index) {
    if (index < 0 || index >= messages.length) return null;
    if (isGenerating) return null;
    final msg = messages[index];
    if (msg.isUser || msg.sender == 'System') return null;
    final meta = msg.activeMetadata;
    if (meta == null || !meta.containsKey('realism_state')) return null;
    final preState = meta['realism_state'];
    if (preState is! Map || preState['needs'] == null) return null;
    if (!needsSimEnabled) return null;

    final isGroupNonObs = activeGroup != null && !observerMode;
    CharacterCard? card;
    if (isGroupNonObs) {
      card = resolveGroupSpeakerForMessage(
        groupCharacters,
        msg,
        logOnMiss: false,
      );
      if (card == null) return null;
    } else {
      card = activeCharacter;
    }
    final enabled = enabledNeedKeys(card);
    if (enabled.isEmpty) return null;
    return (
      speaker: card?.name ?? 'the character',
      enabled: enabled,
      card: card,
    );
  }
}
