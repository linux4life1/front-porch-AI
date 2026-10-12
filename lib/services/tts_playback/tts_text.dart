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

// Text and temp-file helpers shared by the TTS pipelines.

import 'dart:io';

import 'package:front_porch_ai/utils/utils.dart';

/// Sanitize text for TTS: apply narration filters, remove think tags,
/// markdown, emotes, OOC, etc.
String sanitizeTtsText(
  String text, {
  required bool replaceCurlyQuotes,
  required bool ignoreAsterisks,
  required bool narrateQuotedOnly,
}) {
  var result = text;

  // ── Replace curly quotation marks with straight ones (must run before narration filters) ──
  if (replaceCurlyQuotes) {
    result = result
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll('‘', "'")
        .replaceAll('’', "'");
  }

  // ── Narration filters (SillyTavern-style) ──
  // Step 1: If ignoreAsterisks, remove all *...* blocks (including content inside them)
  if (ignoreAsterisks) {
    // Handle multi-line action blocks: *action across\nmultiple lines*
    result = result.replaceAll(RegExp(r'\*[^*]+\*', dotAll: true), ' ');
  }
  // Step 2: If narrateQuotedOnly, extract only text within quotes (straight or curly)
  if (narrateQuotedOnly) {
    // Robust extraction for spoken dialogue in "..." or “...” (curly quotes)
    // We deliberately avoid single quotes here because they are too ambiguous with apostrophes.
    final quotePattern = RegExp(r'["“]([^"”]+)["”]', dotAll: true);
    final matches = quotePattern.allMatches(result);
    final extracted = matches
        .map((m) => m.group(1)?.trim() ?? '')
        .where((s) => s.isNotEmpty)
        .toList();

    result = extracted.isNotEmpty ? extracted.join('. ') : '';
  }

  // ── Standard cleanup ──
  // Reasoning-tag debris (paired/unclosed/orphan-close) must never be
  // spoken — Kokoro tokenizes stray tags as prose.
  result = stripThinkTags(result);
  result = result.replaceAll(RegExp(r'\(OOC:.*?\)', caseSensitive: false), '');
  result = result.replaceAll(RegExp(r'\[OOC:.*?\]', caseSensitive: false), '');
  result = result.replaceAll(RegExp(r'\*'), '');
  result = result.replaceAll(RegExp(r'#{1,6}\s'), '');
  result = result.replaceAll(RegExp(r'[_~`]'), '');
  result = result.replaceAllMapped(
    RegExp(r'\[([^\]]+)\]\([^\)]+\)'),
    (m) => m[1]!,
  );
  result = result.replaceAll(RegExp(r'!\[.*?\]\(.*?\)'), '');
  result = result.replaceAll(RegExp(r':[a-zA-Z0-9_]+:'), '');
  // Remove emojis (fpai-feature-004)
  result = result.replaceAll(
    RegExp(
      r'[\u{1F600}-\u{1F64F}\u{1F300}-\u{1F5FF}\u{1F680}-\u{1F6FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}\u{1F900}-\u{1F9FF}\u{1FA00}-\u{1FA6F}]',
      unicode: true,
    ),
    '',
  );
  result = result.replaceAll(RegExp(r'\s+'), ' ');

  return result.trim();
}

/// Split text into sentences for progress tracking.
List<String> splitTtsSentences(String text) {
  final sentences = <String>[];
  final parts = text.split(RegExp(r'(?<=[.!?])\s+'));
  for (final part in parts) {
    if (part.trim().isEmpty) continue;
    if (sentences.isNotEmpty && sentences.last.length < 20) {
      sentences.last = '${sentences.last} ${part.trim()}';
    } else {
      sentences.add(part.trim());
    }
  }
  if (sentences.isEmpty && text.trim().isNotEmpty) {
    sentences.add(text.trim());
  }
  return sentences;
}

void cleanupTtsFiles(List<File> files) {
  for (final file in files) {
    try {
      file.deleteSync();
    } catch (_) {}
  }
}
