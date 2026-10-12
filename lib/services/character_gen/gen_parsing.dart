// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chargen/chargen.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// Clean raw greeting output — remove quotes, labels, fix truncation.
String cleanGeneratedGreeting(String raw) {
  String cleaned = raw.trim();

  // Remove wrapping quotes if present
  if (cleaned.startsWith('"') && cleaned.endsWith('"')) {
    cleaned = cleaned.substring(1, cleaned.length - 1);
  }

  // Remove common leading labels
  cleaned = cleaned
      .replaceAll(
        RegExp(
          r'^(First message|Opening message|Greeting):?\s*',
          caseSensitive: false,
        ),
        '',
      )
      .trim();

  // Normalize any single-brace {pick}/{roll} the model emitted so the
  // "living detail" macro resolves at display instead of rendering literally.
  return fixDynamicMacroBraces(cleaned);
}

// ═════════════════════════════════════════════════════════════
//  Content Stripping
// ═════════════════════════════════════════════════════════════

/// Strip thinking tags, markdown wrappers, and other LLM artifacts.
String stripGenContent(String raw) {
  return JsonSanitizer.sanitize(raw);
}

// ═════════════════════════════════════════════════════════════
//  JSON Parsing (with multiple fallback strategies)
// ═════════════════════════════════════════════════════════════

/// Parse the cleaned JSON into a [CharacterCard].
/// Tries three strategies: direct decode → newline fix → regex extraction.
CharacterCard? parseGeneratedCardJson(String jsonStr, String fallbackName) {
  // Strategy 1: Direct JSON parse
  try {
    final data = json.decode(jsonStr) as Map<String, dynamic>;
    debugPrint('CharacterGen: Direct JSON parse succeeded');
    return _buildCard(data, fallbackName);
  } catch (e) {
    debugPrint('CharacterGen: Direct parse failed: $e');
  }

  // Strategy 2: Fix newlines inside strings
  try {
    String fixed = JsonSanitizer.escapeControlCharsInStrings(jsonStr);
    fixed = fixed
        .replaceAll(RegExp(r',\s*}'), '}')
        .replaceAll(RegExp(r',\s*]'), ']');
    final data = json.decode(fixed) as Map<String, dynamic>;
    debugPrint('CharacterGen: Newline-fixed parse succeeded');
    return _buildCard(data, fallbackName);
  } catch (e) {
    debugPrint('CharacterGen: Newline-fixed parse failed: $e');
  }

  // Strategy 3: Regex-based extraction (handles unescaped quotes in prose)
  try {
    final data = regexExtractCardFields(jsonStr);
    if (data.isNotEmpty) {
      debugPrint(
        'CharacterGen: Regex extraction succeeded (${data.length} keys)',
      );
      return _buildCard(data, fallbackName);
    }
  } catch (e) {
    debugPrint('CharacterGen: Regex extraction failed: $e');
  }

  debugPrint('CharacterGen: All parse strategies failed');
  return null;
}

/// Regex-based key extraction for malformed JSON.
///
/// Since we know the expected keys, we find each key and extract
/// the value text between keys. This handles unescaped quotes,
/// literal newlines, and other LLM mangling.
Map<String, dynamic> regexExtractCardFields(String raw) {
  final result = <String, dynamic>{};
  final knownKeys = [
    'description',
    'personality',
    'scenario',
    'first_message',
    'alternate_greetings',
    'example_dialogue',
    'system_prompt',
    'tags',
    'image_prompt',
    'lorebook',
  ];

  for (int i = 0; i < knownKeys.length; i++) {
    final key = knownKeys[i];
    // Find "key": or "key" :
    final keyPattern = RegExp('"$key"\\s*:\\s*');
    final keyMatch = keyPattern.firstMatch(raw);
    if (keyMatch == null) continue;

    final valueStart = keyMatch.end;

    // Determine if value is a string, array, or other
    final firstChar = raw.substring(valueStart).trimLeft();
    if (firstChar.startsWith('[')) {
      // Array value — find matching ]
      final arrStart = raw.indexOf('[', valueStart);
      final arrEnd = _findMatchingBracket(raw, arrStart, '[', ']');
      if (arrEnd > arrStart) {
        final arrStr = raw.substring(arrStart, arrEnd + 1);
        try {
          // Fix newlines and attempt parse
          final fixed = JsonSanitizer.escapeControlCharsInStrings(
            arrStr,
          ).replaceAll(RegExp(r',\s*]'), ']');
          result[key] = json.decode(fixed);
        } catch (_) {
          // Fall back to splitting on simple patterns
          result[key] = _extractArrayStrings(arrStr);
        }
      }
    } else if (firstChar.startsWith('"')) {
      // String value — find end by looking for next known key or end of object
      final strStart = raw.indexOf('"', valueStart);
      String? value = _extractStringValue(raw, strStart, knownKeys, i);
      if (value != null) {
        result[key] = value;
      }
    }
  }

  return result;
}

/// Extract a string value starting at [start] (the opening quote).
/// Looks for the next known key as the boundary.
String? _extractStringValue(
  String raw,
  int start,
  List<String> keys,
  int currentIdx,
) {
  if (start < 0 || start >= raw.length) return null;

  // Look past the opening quote
  final contentStart = start + 1;

  // Find the end by looking for the nearest following key, or the closing
  // brace. EVERY other key is considered and the earliest match in the TEXT
  // wins: stopping at the first hit in `keys` order assumed the model emits
  // fields in canonical order, so a reply that put scenario before
  // personality made description run all the way to "personality" — the
  // whole scenario field, quotes and commas included, ended up inside the
  // description. Nothing downstream re-checks it (the length guards are
  // floors), so the bloated value shipped on the card.
  int? nextBoundary;
  for (int j = 0; j < keys.length; j++) {
    if (j == currentIdx) continue;
    final nextKeyPattern = RegExp('"${keys[j]}"\\s*:');
    final nextMatch = nextKeyPattern.firstMatch(raw.substring(contentStart));
    if (nextMatch == null) continue;
    final at = contentStart + nextMatch.start;
    if (nextBoundary == null || at < nextBoundary) nextBoundary = at;
  }

  // If no next key found, look for final }
  nextBoundary ??= raw.lastIndexOf('}');
  if (nextBoundary <= contentStart) return null;

  // Extract and clean the value
  var value = raw.substring(contentStart, nextBoundary);

  // Strip trailing: comma, quote, whitespace
  value = value.replaceAll(RegExp(r'[\s,]*"?\s*,?\s*$'), '');
  // Strip trailing quote
  if (value.endsWith('"')) value = value.substring(0, value.length - 1);

  // Unescape JSON escapes
  value = value
      .replaceAll('\\n', '\n')
      .replaceAll('\\t', '\t')
      .replaceAll('\\"', '"')
      .replaceAll('\\\\', '\\');

  return value.trim();
}

/// Extract string items from a JSON array that may have malformed quotes.
List<String> _extractArrayStrings(String arrStr) {
  final results = <String>[];
  // Remove brackets
  var inner = arrStr.trim();
  if (inner.startsWith('[')) inner = inner.substring(1);
  if (inner.endsWith(']')) inner = inner.substring(0, inner.length - 1);

  // Split on ", " pattern (quotes followed by comma)
  final parts = inner.split(RegExp(r'"\s*,\s*"'));
  for (var part in parts) {
    part = part.trim();
    if (part.startsWith('"')) part = part.substring(1);
    if (part.endsWith('"')) part = part.substring(0, part.length - 1);
    if (part.isNotEmpty) results.add(part);
  }
  return results;
}

/// Find matching closing bracket, accounting for nesting.
int _findMatchingBracket(String s, int start, String open, String close) {
  int depth = 0;
  bool inStr = false;
  for (int i = start; i < s.length; i++) {
    final ch = s[i];
    if (ch == '"' && (i == 0 || s[i - 1] != '\\')) {
      inStr = !inStr;
    } else if (!inStr) {
      if (ch == open) depth++;
      if (ch == close) {
        depth--;
        if (depth == 0) return i;
      }
    }
  }
  return -1;
}

/// Build a [CharacterCard] from parsed JSON data, including lorebook.
CharacterCard _buildCard(Map<String, dynamic> data, String fallbackName) {
  final card = CharacterCard(
    name: fallbackName,
    description: _getString(data, 'description'),
    personality: _getString(data, 'personality'),
    scenario: _getString(data, 'scenario'),
    firstMessage: _getString(data, 'first_message'),
    mesExample: _getString(data, 'example_dialogue'),
    systemPrompt: _getString(data, 'system_prompt'),
    alternateGreetings: _getStringList(data, 'alternate_greetings'),
    tags: _getStringList(data, 'tags'),
  );

  // Parse lorebook entries if the base card volunteered any (the base prompt
  // doesn't request them, so this is a rare path — the dedicated generator in
  // character_gen_steps2 is the normal one). Route through the SAME mechanics
  // assigner so inline entries get consistent construction + category tiering.
  final lorebookData = data['lorebook'];
  if (lorebookData is List && lorebookData.isNotEmpty) {
    final generated = <GeneratedLoreEntry>[];
    for (final entry in lorebookData) {
      if (entry is Map<String, dynamic>) {
        generated.add(
          GeneratedLoreEntry(
            name: entry['name']?.toString() ?? '',
            key: entry['key']?.toString() ?? '',
            content: entry['content']?.toString() ?? '',
            category: entry['category']?.toString() ?? '',
            secondary: entry['secondary']?.toString() ?? '',
          ),
        );
      }
    }
    final lorebook = buildSmartLorebook(generated);
    if (lorebook != null) {
      card.lorebook = lorebook;
      debugPrint(
        'CharacterGen: Parsed ${lorebook.entries.length} lorebook entries',
      );
    }
  }

  return card;
}

/// Safely extract a String from a JSON map.
String _getString(Map<String, dynamic> data, String key) {
  final val = data[key];
  if (val is String) return val;
  if (val != null) return val.toString();
  return '';
}

/// Safely extract a `List<String>` from a JSON map.
/// Strips whitespace and newlines from each element.
List<String> _getStringList(Map<String, dynamic> data, String key) {
  final val = data[key];
  if (val is List) {
    return val
        .map((e) => e.toString().replaceAll(RegExp(r'[\n\r]+'), ' ').trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }
  return [];
}
