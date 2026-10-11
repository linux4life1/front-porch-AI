import 'dart:convert';

import 'package:front_porch_ai/utils/think_tags.dart';

/// A utility for sanitizing and recovering broken JSON outputs from LLMs.
class JsonSanitizer {
  /// Cleans markdown boundaries, trailing commas, and inline unescaped newlines.
  static String sanitize(String input) {
    if (input.isEmpty) return input;

    // 1. Strip thought blocks and markdown fences.
    var cleaned = stripThinkBlocks(input)
        .replaceAll(RegExp(r'^```json\s*', multiLine: true), '')
        .replaceAll(RegExp(r'^```\s*$', multiLine: true), '');

    final jsonMarker = RegExp(r'JSON:\s*').firstMatch(cleaned);
    if (jsonMarker != null) {
      cleaned = cleaned.substring(jsonMarker.end).trim();
    }

    // Attempt to extract the JSON object bounding box
    final jsonStart = cleaned.indexOf('{');
    final jsonEnd = cleaned.lastIndexOf('}');
    if (jsonStart >= 0 && jsonEnd > jsonStart) {
      cleaned = cleaned.substring(jsonStart, jsonEnd + 1);
    }

    // 2. Remove trailing commas for objects and arrays
    cleaned = cleaned.replaceAll(RegExp(r',\s*}'), '}');
    cleaned = cleaned.replaceAll(RegExp(r',\s*]'), ']');

    // 3. Fix literal newlines and tabs inside string values
    return escapeControlCharsInStrings(cleaned).trim();
  }

  /// Escapes literal newlines, carriage returns and tabs that sit inside JSON
  /// string values, which models emit and `json.decode` rejects. Tracks
  /// backslash escapes so a value ending in `\\` still closes its string.
  static String escapeControlCharsInStrings(String input) {
    final buf = StringBuffer();
    var inString = false;
    var escaped = false;
    for (var i = 0; i < input.length; i++) {
      final ch = input[i];
      if (escaped) {
        escaped = false;
      } else if (ch == '\\' && inString) {
        escaped = true;
      } else if (ch == '"') {
        inString = !inString;
      } else if (inString) {
        switch (ch) {
          case '\n':
            buf.write('\\n');
            continue;
          case '\r':
            buf.write('\\r');
            continue;
          case '\t':
            buf.write('\\t');
            continue;
        }
      }
      buf.write(ch);
    }
    return buf.toString();
  }

  /// Whether [text] (already think-stripped) opens with `{` and that object
  /// has closed, so a stream can stop early. Doubled `{{` / `}}` outside
  /// strings are template macros like `{{char}}`, not structure.
  static bool hasCompleteObject(String text) {
    if (!text.startsWith('{')) return false;
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (ch == '\\') {
          escaped = true;
        } else if (ch == '"') {
          inString = false;
        }
        continue;
      }
      if (ch == '"') {
        inString = true;
      } else if (ch == '{' || ch == '}') {
        if (i + 1 < text.length && text[i + 1] == ch) {
          i++;
          continue;
        }
        depth += ch == '{' ? 1 : -1;
        if (depth == 0) return true;
      }
    }
    return false;
  }

  /// Attempts to parse JSON, returning null if it utterly fails.
  /// Automatically runs the sanitizer before parsing.
  static Map<String, dynamic>? tryParse(String input) {
    try {
      final cleaned = sanitize(input);
      return json.decode(cleaned) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
