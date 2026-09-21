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

import 'package:front_porch_ai/services/chargen/chargen.dart';

/// Robust extractor for chargen JSON values from LLM output. Handles markdown
/// fences, literal newlines, unescaped quotes, and falls back to regex.
String? extractChargenValue(String raw, String key) {
  String cleaned = stripThinkBlocks(raw);
  cleaned = cleaned
      .replaceAll(RegExp(r'^```(?:json)?\s*', multiLine: true), '')
      .replaceAll(RegExp(r'^```\s*$', multiLine: true), '')
      .trim();

  final jsonStart = cleaned.indexOf('{');
  final jsonEnd = cleaned.lastIndexOf('}');
  if (jsonStart < 0 || jsonEnd <= jsonStart) return null;
  final jsonStr = cleaned.substring(jsonStart, jsonEnd + 1);

  // 1) Direct parse.
  try {
    final data = json.decode(jsonStr) as Map<String, dynamic>;
    final value = data[key]?.toString();
    if (value != null && value.isNotEmpty) return value;
  } catch (_) {}

  // 2) Escape literal newlines inside strings, drop trailing commas, retry.
  try {
    String fixed = jsonStr.replaceAll('\r\n', '\\n').replaceAll('\r', '\\n');
    final sb = StringBuffer();
    bool inString = false;
    bool escaped = false;
    for (int i = 0; i < fixed.length; i++) {
      final ch = fixed[i];
      if (escaped) {
        sb.write(ch);
        escaped = false;
        continue;
      }
      if (ch == '\\') {
        sb.write(ch);
        escaped = true;
        continue;
      }
      if (ch == '"') {
        inString = !inString;
        sb.write(ch);
        continue;
      }
      if (ch == '\n' && inString) {
        sb.write('\\n');
        continue;
      }
      sb.write(ch);
    }
    fixed = sb
        .toString()
        .replaceAll(RegExp(r',\s*}'), '}')
        .replaceAll(RegExp(r',\s*]'), ']');
    final data = json.decode(fixed) as Map<String, dynamic>;
    final value = data[key]?.toString();
    if (value != null && value.isNotEmpty) return value;
  } catch (_) {}

  // 3) Regex fallback — value after "key": "
  try {
    final match = RegExp(
      '"$key"\\s*:\\s*"',
      caseSensitive: false,
    ).firstMatch(jsonStr);
    if (match != null) {
      final valueStart = match.end;
      bool esc = false;
      for (int i = valueStart; i < jsonStr.length; i++) {
        final ch = jsonStr[i];
        if (esc) {
          esc = false;
          continue;
        }
        if (ch == '\\') {
          esc = true;
          continue;
        }
        if (ch == '"') {
          final value = jsonStr
              .substring(valueStart, i)
              .replaceAll('\\n', '\n')
              .replaceAll('\\t', '\t')
              .replaceAll('\\"', '"');
          return value.isNotEmpty ? value : null;
        }
      }
      final rawValue = jsonStr
          .substring(valueStart)
          .replaceAll(RegExp(r'"\s*}?\s*$'), '');
      if (rawValue.isNotEmpty) {
        return rawValue
            .replaceAll('\\n', '\n')
            .replaceAll('\\t', '\t')
            .replaceAll('\\"', '"');
      }
    }
  } catch (_) {}

  return null;
}
