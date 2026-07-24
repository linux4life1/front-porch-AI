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

import 'package:front_porch_ai/models/character_card.dart';

/// Pure, deterministic post-generation normalization helpers for AI-generated
/// character cards.
///
/// Extracted from `character_gen_service.dart` (the god file was at its 500-line
/// cap) so the regression-critical logic can be unit/golden-tested directly.
/// Anchors the fix in commit 8a0844f: models were baking the literal character
/// name into card fields instead of the portable `{{char}}` macro, and
/// think-only greetings were being silently dropped.

/// Replace literal occurrences of the character's [name] (the whole name and
/// each significant 3+char part of it) with the portable `{{char}}` macro in a
/// single text [field].
///
/// Whole name is tried first so multi-word names are caught intact, then each
/// part. Matching is whole-word (`\b`) and case-insensitive, so a substring like
/// "Ann" inside "Anna" or "announce" is never clobbered. An empty/whitespace
/// name is a no-op.
String applyCharMacro(String field, String name) {
  final full = name.trim();
  if (full.isEmpty) return field;

  // Whole name first (so multi-word names are caught intact), then each part of
  // 3+ chars (shorter parts are too collision-prone to safely replace).
  final targets = <String>[full];
  for (final part in full.split(RegExp(r'\s+'))) {
    if (part.length >= 3 && !targets.contains(part)) targets.add(part);
  }

  var out = field;
  for (final t in targets) {
    out = out.replaceAll(
      RegExp('\\b${RegExp.escape(t)}\\b', caseSensitive: false),
      '{{char}}',
    );
  }
  return out;
}

/// Apply [applyCharMacro] to every generated text field of [card] in place, so
/// the saved card travels well and reads consistently to the chat model.
void applyCharMacroToCard(CharacterCard card, String name) {
  if (name.trim().isEmpty) return;
  card.description = applyCharMacro(card.description, name);
  card.personality = applyCharMacro(card.personality, name);
  card.scenario = applyCharMacro(card.scenario, name);
  card.firstMessage = applyCharMacro(card.firstMessage, name);
  card.mesExample = applyCharMacro(card.mesExample, name);
  card.alternateGreetings =
      card.alternateGreetings.map((g) => applyCharMacro(g, name)).toList();
}

/// Strip `<think>`…`</think>` reasoning blocks (fuzzy — models misspell the tag
/// at high temperature) so callers can tell whether a stream actually produced
/// content or only "thought". Handles both completed blocks and an unterminated
/// `<think>` prefix that runs to the end of the stream.
String stripThinkBlocks(String raw) {
  const open = r'<(?:think|thinking|thnk|thik|tink|thin|hink|ink)>';
  const close = r'</(?:think|thinking|thnk|thik|tink|thin|hink|ink)>';
  return raw
      .replaceAll(RegExp('$open[\\s\\S]*?$close', caseSensitive: false), '')
      .replaceAll(RegExp('$open[\\s\\S]*\$', caseSensitive: false), '')
      .trim();
}

/// A SINGLE-brace `{roll…}` / `{pick…}` / `{random…}` / `{dice…}` that is NOT
/// already double-braced (negative look-around) and contains no nested braces.
final RegExp _singleBraceDynamicMacro = RegExp(
  r'(?<!\{)\{(roll|pick|random|dice)\b([^{}]*)\}(?!\})',
  caseSensitive: false,
);

/// Repair the one macro mistake weak local models reliably make in generated
/// content — emitting a dynamic macro with SINGLE braces (`{pick:a,b,c}`)
/// instead of the double braces the runtime resolver needs (`{{pick:a,b,c}}`),
/// so the "living detail" actually rotates instead of rendering as literal text.
/// Only these four macro names are touched, and only when not already doubled,
/// so genuine single braces in prose (and correct `{{…}}` macros) are left as-is.
/// Used for both generated lorebook entries and generated greetings.
String fixDynamicMacroBraces(String content) => content.replaceAllMapped(
      _singleBraceDynamicMacro,
      (m) => '{{${m[1]!.toLowerCase()}${m[2]}}}',
    );
