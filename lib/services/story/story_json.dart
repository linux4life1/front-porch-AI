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
import 'package:flutter/foundation.dart';
import 'package:front_porch_ai/utils/reasoning_markers.dart';

/// JSON extraction and repair for LLM story-pipeline responses.
///
/// Strips reasoning-model `<think>`/`<reasoning>` blocks, pulls JSON out of
/// markdown code fences or stray prose around it, and best-effort-repairs
/// truncated JSON by closing unmatched brackets/braces. Extracted verbatim
/// from `story_pipeline_service.dart` (Cluster B of the god-file split) —
/// pure and static, zero pipeline state.
abstract final class StoryJson {
  /// Strip `<think>...</think>` blocks from reasoning-model output.
  ///
  /// NOT a duplicate of `utils/think_tags.dart`'s `stripThinkTags`, and must
  /// not be replaced by it: this one is JSON-anchored. On an UNCLOSED tag the
  /// shared helper deletes from `<think>` to the end of the string, which is
  /// right for prose a user reads — and fatal here, because the JSON the
  /// pipeline came for usually sits after the abandoned thought. This version
  /// keeps everything from the first `{` when there is one, and only falls
  /// back to the shared helper's rule when there is no JSON to anchor on.
  static String stripThinkTags(String text) {
    // Handle both complete and unclosed think tags
    // Complete: <think>...</think> (including multiple blocks)
    var result = canonicalizeReasoning(
      text,
    ).replaceAll(RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false), '');
    // Also handle <reasoning>...</reasoning> blocks (some models use this)
    result = result.replaceAll(
      RegExp(r'<reasoning>[\s\S]*?</reasoning>', caseSensitive: false),
      '',
    );
    // Unclosed (model still reasoning): <think>... without closing tag
    final openTagIdx = result.indexOf(RegExp(r'<think>', caseSensitive: false));
    if (openTagIdx != -1) {
      // Find the JSON start after the think block
      final jsonStart = result.indexOf('{', openTagIdx);
      if (jsonStart != -1) {
        // Only keep from the first { onward
        result = result.substring(jsonStart);
      } else {
        // No JSON to anchor on — the prose and timeline calls. Everything from
        // the open tag to the end IS the truncated reasoning, so it has to go:
        // otherwise raw chain-of-thought is stored as a beat's finished prose
        // (reader/ePub/audiobook) or as the canon timeline injected into every
        // later stage prompt. Matches utils/think_tags.dart's `<think>.*$` rule.
        result = result.substring(0, openTagIdx);
      }
    }
    return result.trim();
  }

  /// Extract JSON from LLM output — handles think tags, code blocks, raw JSON, etc.
  static String cleanJson(String text) {
    if (text.isEmpty) return '';

    // Step 1: Strip <think>...</think> reasoning blocks
    var cleaned = stripThinkTags(text);
    debugPrint(
      '[StoryPipeline] After stripping think tags: ${cleaned.length} chars (was ${text.length})',
    );

    // Step 2: Try to extract from code block
    final codeBlockMatch = RegExp(
      r'```(?:json)?\s*([\s\S]*?)\s*```',
    ).firstMatch(cleaned);
    if (codeBlockMatch != null) return codeBlockMatch.group(1)!.trim();

    // Step 3: Strip any text before the first { (e.g. "Here is the JSON:")
    final start = cleaned.indexOf('{');
    final end = cleaned.lastIndexOf('}');
    if (start != -1 && end != -1 && end > start) {
      return cleaned.substring(start, end + 1);
    }

    return cleaned.trim();
  }

  /// Attempt to repair truncated JSON by closing open brackets/braces.
  static String _repairTruncatedJson(String json) {
    var openBraces = 0;
    var openBrackets = 0;
    var inString = false;
    var escaped = false;

    for (int i = 0; i < json.length; i++) {
      final c = json[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (c == '\\') {
        escaped = true;
        continue;
      }
      if (c == '"') {
        inString = !inString;
        continue;
      }
      if (inString) continue;
      if (c == '{') openBraces++;
      if (c == '}') openBraces--;
      if (c == '[') openBrackets++;
      if (c == ']') openBrackets--;
    }

    // If we're inside a string, close it
    var repaired = json;
    if (inString) repaired += '"';

    // Close open brackets and braces
    for (int i = 0; i < openBrackets; i++) {
      repaired += ']';
    }
    for (int i = 0; i < openBraces; i++) {
      repaired += '}';
    }

    return repaired;
  }

  /// Parse JSON with fallback for malformed/truncated responses.
  static Map<String, dynamic>? parseJson(String raw) {
    final cleaned = cleanJson(raw);
    if (cleaned.isEmpty) return null;

    // Try direct parse first
    try {
      return jsonDecode(cleaned) as Map<String, dynamic>;
    } catch (_) {}

    // Try repairing truncated JSON
    try {
      final repaired = _repairTruncatedJson(cleaned);
      debugPrint('[StoryPipeline] Attempting repaired JSON parse...');
      return jsonDecode(repaired) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[StoryPipeline] JSON parse error: $e');
      debugPrint(
        '[StoryPipeline] Cleaned text (first 500): ${cleaned.length > 500 ? cleaned.substring(0, 500) : cleaned}',
      );
      return null;
    }
  }
}
