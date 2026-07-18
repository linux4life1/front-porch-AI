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

import 'dart:convert';

import 'package:front_porch_ai/models/lorebook_entry.dart';

/// Pure key-matching functions with SillyTavern-identical semantics, shared
/// by the scanner (and by tests directly). Not exported via the services
/// barrel — direct-import only, like other chat/ leaves.

/// FNV-1a 32-bit. Dart's Object.hash/String.hashCode are not stable across
/// runs, so persisted identities (timed-effect keys) and deterministic seeds
/// (inclusion-group winners) need a hand-rolled hash.
int fnv1a32(String input) {
  var hash = 0x811c9dc5;
  for (final byte in utf8.encode(input)) {
    hash ^= byte;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash;
}

/// Stable identity for a lorebook entry: hash of name + keys + content.
/// Editing any of those intentionally changes the identity (ST behavior:
/// an edited entry drops its timed-effect state).
int loreEntryHash(LorebookEntry e) =>
    fnv1a32('${e.name}\x00${e.keys.join(',')}\x00${e.content}');

final RegExp _regexKeyShape = RegExp(r'^/(.+)/([gimsuy]*)$');

/// Parse an ST-style `/pattern/flags` key. Returns null when the key is not
/// regex-shaped or the pattern fails to compile (caller falls back to
/// literal matching — same as ST).
RegExp? tryParseRegexKey(String key) {
  final m = _regexKeyShape.firstMatch(key.trim());
  if (m == null) return null;
  return _compile(m.group(1)!, m.group(2)!);
}

RegExp? _compile(String pattern, String flags) {
  try {
    return RegExp(
      pattern,
      caseSensitive: !flags.contains('i'),
      multiLine: flags.contains('m'),
      dotAll: flags.contains('s'),
      unicode: flags.contains('u'),
    );
  } catch (_) {
    return null;
  }
}

/// Match one key against text.
///
/// - `/pattern/flags` keys run as regex (their own flags win; the case and
///   whole-word options are ignored, as in ST).
/// - [forceRegex] treats the bare key as a regex pattern (V3 `use_regex`);
///   invalid patterns fall back to literal matching.
/// - `*` wildcards keep their long-standing FPAI behavior.
/// - Plaintext follows ST: whole-word mode uses `(?:^|\W)key(?:$|\W)` for
///   single words (so punctuation counts as a boundary and CJK keys work)
///   and plain substring for multi-word keys; whole-word off is substring.
bool keyMatchesText(
  String key,
  String text, {
  bool caseSensitive = false,
  bool? matchWholeWords,
  bool forceRegex = false,
}) {
  if (key.isEmpty) return false;

  final slashRegex = tryParseRegexKey(key);
  if (slashRegex != null) return slashRegex.hasMatch(text);

  if (forceRegex) {
    final bare = _compile(key, caseSensitive ? '' : 'i');
    if (bare != null) return bare.hasMatch(text);
  }

  final haystack = caseSensitive ? text : text.toLowerCase();
  final needle = caseSensitive ? key : key.toLowerCase();

  if (needle.contains('*')) {
    final escaped = RegExp.escape(needle).replaceAll(r'\*', '.*');
    return RegExp(escaped).hasMatch(haystack);
  }

  final wholeWords = matchWholeWords ?? true;
  if (!wholeWords || needle.contains(' ')) {
    return haystack.contains(needle);
  }
  return RegExp(r'(?:^|\W)' + RegExp.escape(needle) + r'(?:$|\W)')
      .hasMatch(haystack);
}

/// Evaluate the secondary-key condition. [matches] tests one key against the
/// scanned text with the entry's own options.
bool secondaryLogicSatisfied(
  LorebookEntry entry,
  bool Function(String key) matches,
) {
  if (!entry.selective || entry.secondaryKeys.isEmpty) return true;
  switch (entry.selectiveLogic) {
    case SelectiveLogic.notAll:
      return !entry.secondaryKeys.every(matches);
    case SelectiveLogic.notAny:
      return !entry.secondaryKeys.any(matches);
    case SelectiveLogic.andAll:
      return entry.secondaryKeys.every(matches);
    case SelectiveLogic.andAny:
    default:
      return entry.secondaryKeys.any(matches);
  }
}
