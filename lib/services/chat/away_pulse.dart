// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Group Away recovery: quiet glance pulse + at most one spoken return.
// At work is clock-driven and never enters this path. 1:1 never skips.

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/presence_derive.dart';
import 'package:front_porch_ai/services/chat/scene_guest_director.dart';

/// Quiet pulse cadence: every user send, and every N present-speaker turns.
const int kAwayPulseEveryPresentTurns = 3;

/// Session-scoped Away-return flags. Reset on chat / group / session swap.
class AwayPulseState {
  int presentSpeakerTurns = 0;
  String? pendingReturnSpeakId;
  bool consumingReturnSpeak = false;
  bool returnSpeakUsedThisUserSend = false;
  bool pendingReturnForcedByAt = false;
  String lastUserText = '';

  void reset() {
    presentSpeakerTurns = 0;
    pendingReturnSpeakId = null;
    consumingReturnSpeak = false;
    returnSpeakUsedThisUserSend = false;
    pendingReturnForcedByAt = false;
    lastUserText = '';
  }

  void beginUserSend(String userText) {
    lastUserText = userText;
    returnSpeakUsedThisUserSend = false;
    pendingReturnSpeakId = null;
    consumingReturnSpeak = false;
    pendingReturnForcedByAt = false;
  }

  void finishTurn() {
    pendingReturnSpeakId = null;
    consumingReturnSpeak = false;
    pendingReturnForcedByAt = false;
  }
}

/// Pure Away-return planner. ChatService runs the evals; this leaf
/// decides who to pulse, who may speak a return, and when the skip
/// banner is still allowed.
abstract final class AwayPulse {
  static const everyPresentTurns = kAwayPulseEveryPresentTurns;

  static bool cadenceDue(int presentSpeakerTurns) =>
      presentSpeakerTurns > 0 && presentSpeakerTurns % everyPresentTurns == 0;

  static bool shouldPulse({
    required bool fromUserSend,
    required int presentSpeakerTurns,
  }) => fromUserSend || cadenceDue(presentSpeakerTurns);

  /// Live skip-banner gate. An `@` return must not latch suppression
  /// after [pendingReturnSpeakId] is consumed — the sigil only blocks
  /// the banner while that return is still waiting.
  static bool shouldWriteSkipBanner({
    required bool speakerSkips,
    required bool hasUnconsumedReturn,
  }) => speakerSkips && !hasUnconsumedReturn;

  /// Quiet-flip returns get a short come-back beat. Forced `@` of an
  /// Away member does not — after they speak, the glance eval decides
  /// With you vs Away (refusal is allowed).
  static bool shouldInjectReturnSpeakHint({required bool forcedByAtMention}) =>
      !forcedByAtMention;

  /// `@` of an Away member wins; else the oldest Away who flipped true.
  /// [flippedTrueOldestFirst] is already oldest-away first. Null when
  /// the one-per-send cap is spent or nobody qualifies.
  static String? pickReturnSpeak({
    required String? addressedAwayId,
    required List<String> flippedTrueOldestFirst,
    required bool alreadyUsedThisSend,
  }) {
    if (alreadyUsedThisSend) return null;
    if (addressedAwayId != null) return addressedAwayId;
    if (flippedTrueOldestFirst.isEmpty) return null;
    return flippedTrueOldestFirst.first;
  }

  /// Never-spoken (−1) sorts first — they have been Away the longest.
  static List<String> orderOldestAway(
    Iterable<({String id, int lastSpokeIndex})> flipped,
  ) {
    final list = flipped.toList()
      ..sort((a, b) => a.lastSpokeIndex.compareTo(b.lastSpokeIndex));
    return [for (final e in list) e.id];
  }

  /// Hard address only: `@Name` of an Away member. Vocative / bare
  /// name (`Ana,` / `Ana?`) does not force a spoken return.
  static CharacterCard? addressedAwayMember({
    required List<CharacterCard> roster,
    required String userText,
    required PresenceWhere Function(CharacterCard card) presenceOf,
  }) {
    final hit = SceneGuestDirector.atMentionedCard(roster, userText);
    if (hit == null) return null;
    return presenceOf(hit) == PresenceWhere.away ? hit : null;
  }

  /// Away members only. Mid-sentence names and vocatives go first
  /// (quiet priority, not a force). At work / With you stay out.
  static List<CharacterCard> quietPulseTargets({
    required List<CharacterCard> roster,
    required String userText,
    required PresenceWhere Function(CharacterCard card) presenceOf,
  }) {
    final away = [
      for (final card in roster)
        if (presenceOf(card) == PresenceWhere.away) card,
    ];
    if (away.length <= 1) return away;
    final mentioned = <CharacterCard>[];
    final rest = <CharacterCard>[];
    for (final card in away) {
      if (SceneGuestDirector.isMidSentenceMention(card.name, userText) ||
          SceneGuestDirector.isVocativeAddress(card.name, userText)) {
        mentioned.add(card);
      } else {
        rest.add(card);
      }
    }
    return [...mentioned, ...rest];
  }

  static String returnSpeakHint(String charName) =>
      '[$charName was away and is rejoining the scene now. Write a short '
      'in-scene beat of coming back — one or two sentences. Stay in '
      'character. Do not recap the whole conversation.]';
}
