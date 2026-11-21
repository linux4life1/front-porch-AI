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

/// The needs vector as it stood BEFORE this turn touched needs at all — the
/// one baseline a reprocess and a revert may rebuild from.
///
/// `realism_state['needs']['vector']` cannot serve this role, and that
/// conflation is the bug this exists to close. It is wrong twice over:
///
///  * it is captured AFTER the turn's needs impact, so rebuilding from it
///    re-applies the turn on top of itself; and
///  * both flows below then overwrite it with the post-correction vector,
///    because it doubles as the rewind target for swipe navigation and regen.
///
/// Either alone double-counts. Together they compounded on every pass, which
/// is what the report described: hygiene -6 on the message, a critique about
/// energy, and hygiene falling further each time while nobody had asked it to
/// move. `revertNeedsReprocess` rebuilt from the same field and drifted too.
///
/// The honest baseline is `needs_pre_turn_vector` — the pre-decay snapshot
/// the realism dance already stamps per speaker, and the same one
/// `needs_deltas` is measured against. Rebuilding from it and re-applying the
/// message's own deltas reproduces the current state exactly, which is what
/// makes N passes land where one does. It is copied into `needs_pre_impact`
/// on first use and never rewritten, so messages that predate the dance
/// stamp (and the legacy realism_state fallback below) become stable too
/// after one pass.
Map<String, int> needsPreImpactBaseline(
  Map<String, dynamic> meta,
  Map preState,
) {
  final stashed = _needsVectorFrom(meta['needs_pre_impact']);
  if (stashed.isNotEmpty) return stashed;
  final preTurn = _needsVectorFrom(meta['needs_pre_turn_vector']);
  if (preTurn.isNotEmpty) return preTurn;
  // Legacy messages only: no pre-turn stamp to trust. Best effort, and the
  // stash above makes even this stable from the second pass onward.
  return _needsVectorFrom((preState['needs'] as Map?)?['vector']);
}

/// Tolerant read of a persisted needs vector: these survive a JSON round trip
/// through the session store, so values arrive as `num` and keys as `dynamic`.
Map<String, int> _needsVectorFrom(Object? raw) {
  if (raw is! Map) return <String, int>{};
  return {
    for (final e in raw.entries)
      if (e.value is num) e.key.toString(): (e.value as num).toInt(),
  };
}
