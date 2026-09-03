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

/// The "Where we are" recap block — the plot spine of the state zone
/// (docs/design/prompt-state-injection.md §6/§6.1). The last past-channel
/// without its own builder; the Journal, RAG and the world all had one, and
/// the wording below is the reason it finally needed one (a pure function is
/// testable, an interpolation buried in prompt assembly is not).
///
/// **The head SCOPES the recap to the past. It does not warn that the recap is
/// stale.** That distinction is the whole point of this file, and it was paid
/// for twice.
///
/// The problem is real: the Journal pass that rewrites the recap waits for
/// `journalInterval` user messages (default 10), so this block can assert a
/// moment ten exchanges old. Under the old head — "The story so far" — it
/// asserted it in bare present tense, as a claim about NOW that competed with
/// the transcript. A user's model (Kimi 2.6, 2026-08-08) hit exactly that and
/// wrote "the user included a stale recap block by mistake" in its visible
/// thinking, spending its whole reasoning budget deciding which of our own
/// answers to believe.
///
/// The first fix ANNOTATED the conflict instead of removing it: the head grew
/// " — the conversation has moved on since it was written" whenever the pass
/// cursor said the recap was behind. It did not work, and the measurement is
/// unambiguous. In the A/B against Kimi 2.6 (32 historically-confusing turns,
/// 96 runs per arm) the wording fixes moved attribution by 9% at p=0.86 —
/// nothing. Mining the 461 conflict sentences in the FIXED arm for which of
/// our own fields the model names when it says something contradicts put the
/// recap second (19 mentions), and the modal sentence was our own annotation
/// quoted back at us: "But the notes say the conversation has moved on since
/// the recap was written." We had handed the model a warning to reconcile and
/// it dutifully reconciled it.
///
/// So the clause is gone and the head does the work instead. "Earlier in this
/// story" makes the block a record of the PAST; the transcript is the present.
/// There is then nothing to reconcile — not because we told the model which
/// source wins, but because the two are no longer claims about the same
/// moment. Rules that fall out of that and must hold for any future rewording:
///
///  * **No clause that invites a comparison.** Anything of the form "this may
///    be out of date / the conversation has moved on / check this against the
///    messages above" re-creates the conflict this head exists to dissolve.
///    Precedence, for the cases where a comparison happens anyway, is stated
///    ONCE for the whole zone by [buildStateZoneFrame] — a second copy here is
///    the per-block repetition the register audit named as the disease.
///  * **No boundary claim.** The head deliberately does not say the recap
///    covers only what is no longer visible above. It usually does, but on a
///    short chat the recapped messages are still in the transcript, and a
///    boundary we cannot guarantee is just a new contradiction in a nicer
///    coat.
///  * **No counter, timestamp or turn number.** An earlier version
///    interpolated the live lag ("it lags the conversation by 12 messages"),
///    which changes by two on EVERY turn. That was measured while the block
///    briefly sat in the leading system message, where it re-prefilled the
///    entire conversation on every reply, and the number is what did it. The
///    block is back after the transcript now (kStateZoneSectionIds, in
///    chat_service_generation_plan.dart) so a moving byte is cheap here — but
///    it bought nothing even at that price. These bytes now change only when
///    the recap itself is rewritten, which is the floor.
///  * **Keep the anti-echo guard.** "not new prose — do not continue or
///    restate it" is load-bearing for this block's post-transcript seat: it is
///    the last prose the model reads before it starts writing, and without the
///    guard the nearest continuation target is the recap.
/// The recap only retells what the prompt cannot already show.
///
/// `dropped == 0` used to mean "the whole chat is in the window". On a
/// tail-open the in-memory list is the last 24 rows, so they can all fit
/// while [basePosition] still hides the rest of the story. Suppress only
/// when both are zero.
bool recapIsRedundant({required int dropped, required int basePosition}) =>
    dropped == 0 && basePosition == 0;

String buildRecapBlock({required String recap}) {
  if (recap.isEmpty) return '';
  // Leading \n: this block's own separator, so it sits one blank line clear of
  // the state-zone frame above it (the transcript and the retrieved-memories
  // block before that carry no trailing blank line of their own).
  return '\n[Earlier in this story (a recap for memory; not new prose — do '
      'not continue or restate it): $recap]\n';
}
