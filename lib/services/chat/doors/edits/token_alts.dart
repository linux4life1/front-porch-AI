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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/doors/edits/edit_deps.dart';
import 'package:front_porch_ai/services/chat/doors/edits/regen_controller.dart';

/// Token alternatives (KoboldCpp only, see token_alternatives.dart): capture
/// a reply's word odds, keep the unsure places on its swipe, and rewrite the
/// last reply from one of them as a new swipe.
///
/// The generation hands each turn in as an opaque key: the word odds are
/// kept per turn, and the rewrite's seed waits here for the next normal
/// reply.
class TokenAlts {
  TokenAlts(this._d, this._regen);

  final EditDeps _d;
  final RegenController _regen;

  /// Per-token probabilities a KoboldCpp reply sent, kept per turn.
  final _turnLogprobs = Expando<List<Object?>>('turnLogprobs');

  /// A rewrite from a word waiting for its turn: the next normal reply
  /// starts with this text.
  String? _regenSeed;

  ChatSessionState get _session => _d.session;

  /// A rewrite from a word: a normal reply that starts with [continuePrefix],
  /// which KoboldCpp continues as a trailing assistant message.
  static bool isSeeded(GenerationMode mode, String continuePrefix) =>
      mode == GenerationMode.normal && continuePrefix.isNotEmpty;

  /// The pending rewrite seed, handed to the turn being planned. Taking it
  /// clears it, whatever the turn's mode.
  String? takeSeed() {
    final seed = _regenSeed;
    _regenSeed = null;
    return seed;
  }

  /// Collects the word odds a reply streams for [turn].
  void Function(List<Object?>) sinkFor(Object turn) =>
      (tokens) => (_turnLogprobs[turn] ??= []).addAll(tokens);

  /// Keeps the unsure places of [turn]'s finished reply on its swipe.
  /// [from] skips a rewrite's seeded prefix.
  void stamp(Object turn, ChatMessage target, {required int from}) {
    final tokens = _turnLogprobs[turn];
    if (tokens == null || tokens.isEmpty) return;
    final found = buildTokenAlternatives(
      tokens,
      tokenAltsBody(target.text),
      from: from,
    );
    if (found.isEmpty) return;
    target.activeMetadata ??= {};
    target.activeMetadata![kTokenAltsKey] = [for (final a in found) a.toJson()];
  }

  /// The places in reply [index] where the model weighed other words.
  List<TokenAlternative> tokenAlternativesAt(int index) {
    if (index < 0 || index >= _session.messages.length) return const [];
    final m = _session.messages[index];
    return m.isUser ? const [] : tokenAlternativesOf(m);
  }

  /// Why reply [index] cannot be rewritten from a word now; null when it can.
  String? tokenAltsPickRefusal(int index) {
    if (_d.view.isGenerating() || _d.view.isSettlingTurn()) {
      return 'Wait for the reply to finish.';
    }
    if (index != _session.messages.length - 1) {
      return 'Only the last reply can be rewritten from a word.';
    }
    if (!_d.services.lanes.mouthIsLocal) {
      return 'Rewriting from a word needs KoboldCpp.';
    }
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
    final msg = _session.messages[index];
    final body = tokenAltsBody(msg.text);
    if (!body.startsWith(at.token, at.offset)) return false;
    final carried = [
      for (final a in tokenAlternativesOf(msg))
        if (a.offset < at.offset) a,
    ];
    final before = msg.swipes.length;
    _regenSeed = tokenAltsSeed(body, at, pick);
    try {
      await _regen.regenerateLastMessage();
    } finally {
      _regenSeed = null;
    }
    if (_session.messages.isEmpty || !identical(_session.messages.last, msg)) {
      return false;
    }
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
      await _d.saveChat();
      _d.notify();
    }
    return true;
  }

  /// Reply [index]'s places for the web: each with the words before it, and
  /// whether a word can be picked now.
  Map<String, dynamic> tokenAlternativesJson(int index) {
    final places = tokenAlternativesAt(index);
    final body = places.isEmpty
        ? ''
        : tokenAltsBody(_session.messages[index].text);
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
