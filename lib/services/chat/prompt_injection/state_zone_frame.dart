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

/// The one frame that introduces the STATE ZONE
/// (docs/design/prompt-state-injection.md §6.1) — the recap, the Journal, the
/// objective, the world, and the character-state block, all of which ride the
/// USER turn after the transcript.
///
/// **Why the attribution is words and not a message role.** Every one of those
/// blocks is written by the app, so the obvious fix for "the model thinks the
/// human typed this" was to move them into the system message, where the app's
/// voice is structural. That was tried on 2026-08-08 and REVERTED the same day:
/// the state zone cannot hold a stable prefix, and everything ahead of the
/// transcript must, or a local prefix cache breaks at the first differing byte
/// and re-processes everything after it — which is the whole transcript
/// (measured: 508 vs 5,020 of 5.5k tokens re-prefilled per warm turn, 9.3x the
/// wall clock per reply — full numbers on kStateZoneSectionIds, in
/// chat_service_generation_plan.dart).
///
/// The measurement that settled it was taken on the maintainer's own 200-card
/// diary, replayed against one real chat's 42 recorded emotion values: of 41
/// turn transitions the journal block held its bytes 24 times and changed them
/// 17 — 41% of replies — because the Journal's mood-congruent ordering re-sorts
/// the hot set whenever the emotion FAMILY changes and the 600-token budget
/// then renders a different card set. Across all of that library's real chats
/// it is 543 of 873 transitions. That ordering is a deliberate feature and
/// stays; so the zone stays behind the transcript and pays for attribution in
/// words. This text costs ~121 tokens of prefill a turn on top of a zone that
/// is re-read anyway — keep it tight, and never let it grow into the per-block
/// repetition §1 calls the disease.
///
/// **Why a frame is needed at all.** The recap, the objective step, the world
/// and the character state all assert things in bare present tense, and the
/// first two can legitimately lag the transcript — the recap is rewritten only
/// every `journalInterval` user messages, and objective steps complete in a
/// fire-and-forget background check. Nothing in the prompt ever said which wins
/// when they disagree, so a real model (Kimi 2.6, 2026-08-08) derived the rule
/// itself, out loud, at the cost of its entire reasoning budget — and landed on
/// "the user included a stale recap block by mistake", because from inside the
/// user turn a contradiction it could not resolve looks like a human error.
///
/// **One frame, one register.** The register audit (§1) named repetition and
/// mixed registers as the disease, so the ruling is stated ONCE for the whole
/// zone rather than per block. It splits by KIND rather than by block so it
/// cannot contradict the Journal's own "the feelings here are the truer guide"
/// line: the transcript owns EVENTS (it is the record of what happened), the
/// notes own FEELINGS and inner state (which the transcript never records).
///
/// The scope sentence names the KINDS of note the zone carries, so it never
/// lands on the author-directive blocks (post-history instructions, the
/// Author's Note, the @AN lorebook buckets) that render between the zone's two
/// runs — those genuinely ARE the user's, and attributing them to the app
/// would be a new lie in place of the old one.
///
/// The newest beat renders AFTER the zone (`latest_turn`), so the transcript
/// is named as above-and-after rather than "above": the zone sits inside it.
///
/// Pronoun policy (§3): pronoun-free except the ungendered "they" — one text
/// serves every character, no gender field.
String buildStateZoneFrame({
  required String userName,
  required String characterName,
}) {
  final who = userName.trim().isEmpty ? 'the user' : userName.trim();
  final name = characterName.trim().isEmpty
      ? 'the character'
      : characterName.trim();
  // Leading \n (same convention as the recap and the journal): this block opens
  // the zone and the transcript carries no trailing newline, so without it the
  // frame is glued to the transcript's last line — a misreading of who wrote
  // it, the precise one it exists to prevent.
  return '\n[Story state — these notes are written by the app from its own '
      'records of this chat: what has happened, how $name feels and how they '
      'are right now, what they are working toward, and where they are. $who '
      'did not type them and nothing here needs a reply. The conversation '
      '(above, and its newest message after these notes) is the record of '
      'what actually happened, so where these notes '
      'disagree with it about events the conversation is right and the notes '
      'are simply behind; on feelings and inner state, which the conversation '
      'does not record, the notes are the truer guide.]\n';
}
