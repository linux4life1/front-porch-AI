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

/// Shared greet / regenerated-swipe picker: list payload + commit-once select.
/// Chevron cycling reuses [selectGreeting] so emotion rules stay in one place.
extension ChatServiceVariants on ChatService {
  /// The card whose greets the opening picker cycles. Public so the bubble
  /// (and FakeChatService) can count them without `_activeCharacter` — groups
  /// have a null active character even when the opener is a member greet.
  List<String> get openingAllGreetings {
    if (isGroupMode) {
      final g = activeGroup;
      if (g != null && !greetingFirstMesEmpty(g.firstMessage))
        return g.allGreetings;
      if (messages.isEmpty) return const [];
      final cid = messages.first.characterId;
      if (cid == null || cid.isEmpty) return const [];
      for (final c in groupCharacters) {
        if (c.stableGroupId == cid) return c.allGreetings;
      }
      return const [];
    }
    return activeCharacter?.allGreetings ?? const [];
  }

  /// True when this bubble is the opening greet with more than one card greet
  /// and no stored regen swipes (those are variants, not greets).
  bool isSelectableGreeting(int messageIndex) {
    // Public accessors so FakeChatService (other library) can answer this
    // from a bubble build. `_messages` / `_activeCharacter` are library-
    // private and resolve as noSuchMethod on the fake.
    if (messageIndex < 0 || messageIndex >= messages.length) return false;
    final msg = messages[messageIndex];
    return usesGreetingPicker(
      messageIndex: messageIndex,
      isUser: msg.isUser,
      greetCount: openingAllGreetings.length,
      swipeCount: msg.swipes.length,
      userHasReplied: messages.any((m) => m.isUser),
    );
  }

  /// Picker rows for [messageIndex]. Card greets are macro-resolved so the
  /// preview reads like the opening bubble, not `{{char}}` + HTML comments.
  List<VariantOption> variantsForMessage(int messageIndex) {
    if (messageIndex < 0 || messageIndex >= messages.length) {
      return const [];
    }
    if (isSelectableGreeting(messageIndex)) {
      return buildVariantOptions(
        _resolvedOpeningGreetings(),
        greetingIndex,
        kind: VariantKind.greet,
      );
    }
    final msg = messages[messageIndex];
    return buildVariantOptions(
      msg.swipes,
      msg.swipeIndex,
      kind: VariantKind.regen,
    );
  }

  Map<String, dynamic> variantPickerPayload(int messageIndex) {
    if (messageIndex < 0 || messageIndex >= messages.length) {
      return {
        'kind': 'regen',
        'title': 'Select variant',
        'currentIndex': 0,
        'variants': const [],
      };
    }
    final greet = isSelectableGreeting(messageIndex);
    final options = variantsForMessage(messageIndex);
    final current = options.where((v) => v.isCurrent);
    return {
      'kind': greet ? 'greet' : 'regen',
      'title': greet ? 'Select greet' : 'Select variant',
      'currentIndex': current.isEmpty ? 0 : current.first.index,
      'variants': [for (final v in options) v.toJson()],
    };
  }

  /// Commit one greet. Opening-only chats re-apply that greet's authored
  /// Realism/Needs seed (or read-the-room when the alt has none). Swiping
  /// back to index 0 restores the card/group base — it does not keep the
  /// previous alt's live mood. Re-selecting the same index is a no-op.
  List<String> _resolvedOpeningGreetings() {
    if (_activeGroup != null &&
        !greetingFirstMesEmpty(_activeGroup!.firstMessage)) {
      return [
        for (final g in _activeGroup!.allGreetings)
          _macroResolver.resolve(
            g,
            MacroContext(userName: _userPersonaService.persona.name),
            section: 'greeting',
          ),
      ];
    }
    final character = _greetingOwnerCard() ?? _activeCharacter;
    if (character == null) return const [];
    return [
      for (final g in character.allGreetings)
        _buildFirstMessage(character, greetingText: g),
    ];
  }

  Future<void> selectGreeting(int index) async {
    if (_messages.isEmpty) return;
    final allGreetings = openingAllGreetings;
    if (allGreetings.length <= 1) return;
    if (index < 0 || index >= allGreetings.length) return;
    if (index == _greetingIndex) return;

    await _invalidateGreetingEval();
    testPostGreetingEvalEntered = false;

    _greetingIndex = index;
    final resolved = _resolvedOpeningGreetings();
    if (index >= resolved.length) return;
    final old = _messages[0];
    final groupCustom =
        _activeGroup != null &&
        !greetingFirstMesEmpty(_activeGroup!.firstMessage);
    _messages[0] = ChatMessage(
      text: resolved[index],
      sender: groupCustom ? _activeGroup!.name : (old.sender),
      isUser: false,
      characterId: groupCustom ? null : old.characterId,
    );
    _stampGreetingIndex(index);

    if (_isOpeningGreetingChat) {
      if (groupCustom) {
        await _applyGroupCustomGreetingSeed(index);
      } else {
        final owner = _greetingOwnerCard() ?? _activeCharacter;
        if (owner != null) {
          await _applyGreetingOpeningSeed(card: owner, index: index);
        }
      }
    }

    await _saveChat();
    notifyListeners();
  }

  /// Jump to an already-stored swipe. Never generates a new one (the
  /// chevron-past-the-end path in [swipeMessage] still does). Restores
  /// that swipe's snapshot when this message is the tip — no reading-the-room.
  Future<void> selectSwipe(int messageIndex, int swipeIndex) async {
    if (messageIndex < 0 || messageIndex >= _messages.length) return;
    final msg = _messages[messageIndex];
    if (msg.isUser || msg.sender == 'System') return;
    await _commitSwipeIndex(messageIndex, swipeIndex);
  }

  Future<void> selectVariant(int messageIndex, int variantIndex) async {
    if (isSelectableGreeting(messageIndex)) {
      await selectGreeting(variantIndex);
    } else {
      await selectSwipe(messageIndex, variantIndex);
    }
  }
}
