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
      if (g != null && !greetingFirstMesEmpty(g.firstMessage)) {
        return g.allGreetings;
      }
      if (messages.isEmpty) return const [];
      final cid = messages.first.characterId;
      if (cid == null || cid.isEmpty) return const [];
      for (final c in groupCharacters) {
        if (_getCharacterIdFromCard(c) == cid || c.stableGroupId == cid) {
          return c.allGreetings;
        }
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

/// Per-token probabilities a KoboldCpp reply sent, kept per turn.
final _turnLogprobs = Expando<List<Object?>>('turnLogprobs');

/// Token alternatives (KoboldCpp only, see token_alternatives.dart): capture
/// a reply's word odds, keep the unsure places on its swipe, and rewrite the
/// last reply from one of them as a new swipe.
extension ChatServiceTokenAlts on ChatService {
  /// A rewrite from a word: the reply starts with [_GenTurn.continuePrefix],
  /// which KoboldCpp continues as a trailing assistant message.
  bool _isSeeded(_GenTurn t) =>
      t.mode == GenerationMode.normal && t.continuePrefix.isNotEmpty;

  /// Hands the pending rewrite seed to the turn being planned.
  void _applyRegenSeed(_GenTurn t) {
    final seed = _regenSeed;
    _regenSeed = null;
    if (seed != null && t.mode == GenerationMode.normal) {
      t.continuePrefix = seed;
    }
  }

  List<Map<String, Object>>? _seededMessages(_GenTurn t, String prompt) =>
      _isSeeded(t)
      ? [
          {'role': 'user', 'content': prompt},
          {'role': 'assistant', 'content': t.continuePrefix},
        ]
      : null;

  /// Asks for word odds on a normal reply from KoboldCpp, and nowhere else.
  void Function(List<Object?>)? _logprobsSink(_GenTurn t) {
    if (!_mouthIsLocal || t.mode != GenerationMode.normal || _callMode) {
      return null;
    }
    return (tokens) => (_turnLogprobs[t] ??= []).addAll(tokens);
  }

  /// Keeps the unsure places of the finished reply on its swipe.
  void _stampTokenAlts(_GenTurn t) {
    final tokens = _turnLogprobs[t];
    if (tokens == null || tokens.isEmpty) return;
    final found = buildTokenAlternatives(
      tokens,
      tokenAltsBody(t.streamTarget.text),
      from: _isSeeded(t) ? t.continuePrefix.length : 0,
    );
    if (found.isEmpty) return;
    t.streamTarget.activeMetadata ??= {};
    t.streamTarget.activeMetadata![kTokenAltsKey] = [
      for (final a in found) a.toJson(),
    ];
  }

  /// The places in reply [index] where the model weighed other words.
  List<TokenAlternative> tokenAlternativesAt(int index) {
    if (index < 0 || index >= _messages.length) return const [];
    final m = _messages[index];
    return m.isUser ? const [] : tokenAlternativesOf(m);
  }

  /// Why reply [index] cannot be rewritten from a word now; null when it can.
  String? tokenAltsPickRefusal(int index) {
    if (isGenerating || isSettlingTurn) return 'Wait for the reply to finish.';
    if (index != _messages.length - 1) {
      return 'Only the last reply can be rewritten from a word.';
    }
    if (!_mouthIsLocal) return 'Rewriting from a word needs KoboldCpp.';
    return null;
  }

  /// Rewrites the last reply from [at], writing [pick] there: a new swipe
  /// that keeps the reply's words up to that point. It runs as Regenerate
  /// does (the turn is rewound and post-gen scores the whole new reply).
  Future<bool> rewriteFromAlternative(
    int index,
    TokenAlternative at,
    String pick,
  ) async {
    if (tokenAltsPickRefusal(index) != null) return false;
    final msg = _messages[index];
    final body = tokenAltsBody(msg.text);
    if (!body.startsWith(at.token, at.offset)) return false;
    final carried = [
      for (final a in tokenAlternativesOf(msg))
        if (a.offset < at.offset) a,
    ];
    final before = msg.swipes.length;
    _regenSeed = tokenAltsSeed(body, at, pick);
    try {
      await regenerateLastMessage();
    } finally {
      _regenSeed = null;
    }
    if (_messages.isEmpty || !identical(_messages.last, msg)) return false;
    if (msg.swipes.length <= before) return false;
    // The words before the pick are unchanged, so their places still hold.
    final now = tokenAltsBody(msg.text);
    final kept = [
      for (final a in carried)
        if (now.startsWith(a.token, a.offset)) a.toJson(),
    ];
    if (kept.isNotEmpty) {
      final fresh = msg.activeMetadata?[kTokenAltsKey];
      msg.activeMetadata ??= {};
      msg.activeMetadata![kTokenAltsKey] = [
        ...kept,
        if (fresh is List) ...fresh,
      ];
      await _saveChat();
      notifyListeners();
    }
    return true;
  }

  /// Reply [index]'s places for the web: each with the words before it, and
  /// whether a word can be picked now.
  Map<String, dynamic> tokenAlternativesJson(int index) {
    final places = tokenAlternativesAt(index);
    final body = places.isEmpty ? '' : tokenAltsBody(_messages[index].text);
    final refusal = tokenAltsPickRefusal(index);
    return {
      'canPick': refusal == null,
      'refusal': ?refusal,
      'places': [
        for (final a in places)
          {
            'token': a.token,
            'p': a.p,
            'leadIn': tokenAltsLeadIn(body, a),
            'alts': [
              for (final w in a.alts) {'token': w.token, 'p': w.p},
            ],
          },
      ],
    };
  }

  /// The place a web pick names, or why it cannot be picked.
  ({TokenAlternative? at, String? refusal}) tokenAltPick(
    int index,
    int place,
    String word,
  ) {
    final refusal = tokenAltsPickRefusal(index);
    if (refusal != null) return (at: null, refusal: refusal);
    final places = tokenAlternativesAt(index);
    if (place < 0 || place >= places.length) {
      return (at: null, refusal: 'That word is no longer on offer.');
    }
    final at = places[place];
    if (!at.alts.any((a) => a.token == word)) {
      return (at: null, refusal: 'That word is no longer on offer.');
    }
    return (at: at, refusal: null);
  }
}
