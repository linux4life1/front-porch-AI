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

import 'package:front_porch_ai/utils/reasoning_markers.dart';

/// Tag extraction for story-pipeline replies.
///
/// Planning stages ask for simple tags instead of JSON: a small model that
/// drops a comma or a quote ruins a whole JSON reply, while a tag reply
/// degrades one field at a time. This is deliberately not an XML parser —
/// model output is never well-formed enough for one — so every reader here
/// tolerates stray prose, code fences, unescaped `&`, and a reply cut off
/// before its closing tags.
abstract final class StoryXml {
  /// Drop reasoning blocks and code fences. An unclosed `<think>` keeps
  /// whatever real tags follow it (the answer usually does), and is cut only
  /// when nothing tag-shaped comes after.
  static String clean(String raw) {
    var text = canonicalizeReasoning(raw)
        .replaceAll(
          RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(r'<reasoning>[\s\S]*?</reasoning>', caseSensitive: false),
          '',
        );
    final open = text.indexOf(RegExp(r'<think>', caseSensitive: false));
    if (open != -1) {
      final answer = RegExp(
        r'<(?!/?think\b)[a-z_]+>',
        caseSensitive: false,
      ).firstMatch(text.substring(open + 7));
      text = answer == null
          ? text.substring(0, open)
          : text.substring(open + 7 + answer.start);
    }
    return text
        .replaceAll(RegExp(r'```[a-zA-Z]*\s*'), '')
        .replaceAll('```', '')
        .trim();
  }

  /// Inner text of the first `<name>`, decoded and trimmed; '' when absent.
  /// A tag that never closes yields everything up to the next line that
  /// starts a tag, so a truncated reply still gives up its last field.
  static String tag(String text, String name) {
    final blocks = all(text, name, limit: 1);
    if (blocks.isNotEmpty) return decode(blocks.first).trim();
    final open = _open(name).firstMatch(text);
    if (open == null) return '';
    final rest = text.substring(open.end);
    final next = RegExp(r'\n\s*<').firstMatch(rest);
    return decode(next == null ? rest : rest.substring(0, next.start)).trim();
  }

  /// First non-empty value among several tag spellings.
  static String firstTag(String text, List<String> names) {
    for (final n in names) {
      final v = tag(text, n);
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  static int? intTag(String text, String name) {
    final m = RegExp(r'-?\d+').firstMatch(tag(text, name));
    return m == null ? null : int.tryParse(m.group(0)!);
  }

  /// Raw inner text of every top-level `<name>…</name>` in [text], in order.
  /// Depth-counted, so a `<scene>` that itself contains `<scene>` stays one
  /// block.
  static List<String> all(String text, String name, {int? limit}) {
    final out = <String>[];
    final marker = RegExp('</?$name(?:\\s[^>]*)?>', caseSensitive: false);
    var depth = 0;
    var start = 0;
    for (final m in marker.allMatches(text)) {
      final closing = m.group(0)!.startsWith('</');
      if (!closing) {
        if (depth == 0) start = m.end;
        depth++;
      } else if (depth > 0) {
        depth--;
        if (depth == 0) {
          out.add(text.substring(start, m.start));
          if (limit != null && out.length >= limit) break;
        }
      }
    }
    return out;
  }

  /// Decoded values of each `<child>` inside the first `<parent>`. Falls back
  /// to a comma / newline split when the model wrote a plain list instead.
  static List<String> list(String text, String parent, String child) {
    final block = all(text, parent, limit: 1);
    if (block.isEmpty) return const [];
    final items = all(
      block.first,
      child,
    ).map((e) => decode(e).trim()).where((e) => e.isNotEmpty).toList();
    if (items.isNotEmpty) return items;
    return strip(block.first)
        .split(RegExp(r'[,\n]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && e.toLowerCase() != 'none')
        .toList();
  }

  static bool has(String text, String name) => _open(name).hasMatch(text);

  /// Remove every tag, keeping the text between them.
  static String strip(String text) => decode(
    text.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '').replaceAll(_anyTag, ''),
  ).trim();

  static String decode(String text) {
    final cdata = RegExp(
      r'^\s*<!\[CDATA\[([\s\S]*?)\]\]>\s*$',
    ).firstMatch(text);
    if (cdata != null) return cdata.group(1)!;
    return text
        .replaceAll(RegExp(r'<!--[\s\S]*?-->'), '')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&#39;', "'")
        .replaceAll('&amp;', '&');
  }

  static String escape(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  static RegExp _open(String name) =>
      RegExp('<$name(?:\\s[^>]*)?>', caseSensitive: false);

  static final _anyTag = RegExp(r'</?[a-zA-Z_][\w-]*(?:\s[^>]*)?>');
}
