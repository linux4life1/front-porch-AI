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

/// The deterministic pre-gate for the per-turn objective completion check —
/// pure string logic, its own leaf so it stays trivially testable and so
/// objective_proposal.dart (already past the 500-line target) does not grow.
library;

/// Content words too common to signal that a scene touches a quest. Only
/// words of 4+ letters ever reach the check, so shorter ones are omitted.
const Set<String> kObjectiveMentionStopwords = {
  'about',
  'after',
  'again',
  'their',
  'there',
  'these',
  'those',
  'thing',
  'things',
  'something',
  'someone',
  'somewhere',
  'being',
  'doing',
  'going',
  'gets',
  'goes',
  'have',
  'having',
  'into',
  'just',
  'like',
  'make',
  'makes',
  'making',
  'more',
  'most',
  'much',
  'must',
  'need',
  'needs',
  'other',
  'over',
  'some',
  'take',
  'takes',
  'taking',
  'than',
  'that',
  'them',
  'then',
  'they',
  'this',
  'time',
  'truly',
  'very',
  'want',
  'wants',
  'what',
  'when',
  'where',
  'which',
  'while',
  'will',
  'with',
  'without',
  'would',
  'your',
  'yours',
  'from',
  'find',
  'finds',
  'finally',
  'genuinely',
  'herself',
  'himself',
  'themselves',
  'toward',
  'towards',
};

/// Does the recent exchange even TOUCH one of the open quests?
///
/// A task can only be completed by something the exchange actually shows,
/// and the completion check reads that same exchange — so when none of a
/// quest's content words appear in it, a YES verdict is not on the table and
/// the call is a guaranteed NO paid for at full price, BEFORE generation,
/// blocking the reply. This is the promise ledger's `warrantsEval` pattern
/// applied to quests (the eval review's Tier-1 §3.1).
///
/// Matching is prefix-at-word-boundary so "laugh" reaches "laughing" and
/// "laughed" — a cheap stem. [ignore] carries the cast and user name tokens:
/// they appear in most quest texts AND most exchanges, so counting them
/// would quietly turn the gate always-on.
///
/// Forgiving in the right direction: a paraphrase the gate misses is not a
/// lost completion, only a later one — the interval check still fires every
/// `checkFrequency` messages, exactly as the UI has always promised.
bool objectivesMentionedIn(
  String recentLowerText,
  Iterable<String> questTexts, {
  Set<String> ignore = const {},
}) {
  if (recentLowerText.trim().isEmpty) return false;
  for (final text in questTexts) {
    for (final w in objectiveContentWords(text, ignore: ignore)) {
      if (RegExp('\\b${RegExp.escape(w)}').hasMatch(recentLowerText)) {
        return true;
      }
    }
  }
  return false;
}

/// The words of a goal that carry its content: four letters and up, not a
/// stopword, not a cast or user name ([ignore]). In text order, repeats kept.
/// Shared by the mention gate and the proposal gate, so "the same goal" means
/// the same thing to both.
List<String> objectiveContentWords(
  String text, {
  Set<String> ignore = const {},
}) => [
  for (final m in RegExp(r"[a-z][a-z']{3,}").allMatches(text.toLowerCase()))
    if (!kObjectiveMentionStopwords.contains(m.group(0)!) &&
        !ignore.contains(m.group(0)!))
      m.group(0)!,
];
