// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/utils/json_sanitizer.dart';

void main() {
  group('JsonSanitizer.sanitize()', () {
    test('strips ```json ... ``` fences', () {
      const input = '```json\n{"key": "value"}\n```';
      expect(JsonSanitizer.sanitize(input), '{"key": "value"}');
    });

    test('strips ``` without json label', () {
      const input = '```\n{"key": "value"}\n```';
      expect(JsonSanitizer.sanitize(input), '{"key": "value"}');
    });

    test('strips <thinking>...</thinking> tags', () {
      const input = '<thinking>Analysis...</thinking>{"key": "value"}';
      expect(JsonSanitizer.sanitize(input), '{"key": "value"}');
    });

    test('strips misspelled think tags (model hallucination)', () {
      const input = '<ink>thinking...</ink>{"key": "value"}';
      expect(JsonSanitizer.sanitize(input), '{"key": "value"}');
    });

    test('strips unclosed think tags (greedy match eats everything after)', () {
      // The regex <thinking>[\s\S]* is greedy and has no closing tag match,
      // so it consumes everything from <thinking> to the end of string.
      const input = '<thinking>Analysis is ongoing\n{"key": "value"}';
      expect(JsonSanitizer.sanitize(input), '');
    });

    test('extracts JSON object from surrounding text', () {
      const input = 'Here is your JSON: {"key": "value"} done';
      expect(JsonSanitizer.sanitize(input), '{"key": "value"}');
    });

    test('extracts JSON after "JSON:" marker', () {
      const input = 'JSON:\n{"key": "value"}';
      expect(JsonSanitizer.sanitize(input), '{"key": "value"}');
    });

    test('removes trailing commas in objects', () {
      const input = '{"key": "value",}';
      expect(JsonSanitizer.sanitize(input), '{"key": "value"}');
    });

    test('removes trailing commas in arrays', () {
      const input = '["a", "b",]';
      expect(JsonSanitizer.sanitize(input), '["a", "b"]');
    });

    test('handles multiple trailing commas', () {
      const input = '{"a": 1, "b": 2,}';
      expect(JsonSanitizer.sanitize(input), '{"a": 1, "b": 2}');
    });

    test('escapes literal newlines inside JSON strings', () {
      const input = '{"key": "line1\nline2"}';
      expect(JsonSanitizer.sanitize(input), '{"key": "line1\\nline2"}');
    });

    test('escapes literal tabs inside JSON strings', () {
      const input = '{"key": "col1\tcol2"}';
      expect(JsonSanitizer.sanitize(input), '{"key": "col1\\tcol2"}');
    });

    test('escapes literal carriage returns inside JSON strings', () {
      const input = '{"key": "line1\rline2"}';
      expect(JsonSanitizer.sanitize(input), '{"key": "line1\\rline2"}');
    });

    test('preserves newlines outside strings (trimmed at edges)', () {
      const input = '{\n"key": "value"\n}';
      // trim() removes leading/trailing whitespace but internal newlines stay
      expect(JsonSanitizer.sanitize(input), '{\n"key": "value"\n}');
    });

    test('returns empty string for empty input', () {
      expect(JsonSanitizer.sanitize(''), '');
    });

    test('returns input unchanged if no cleaning needed', () {
      const input = '{"key": "value"}';
      expect(JsonSanitizer.sanitize(input), '{"key": "value"}');
    });

    test('handles nested JSON objects', () {
      const input = '```json\n{"outer": {"inner": "value"}}\n```';
      expect(JsonSanitizer.sanitize(input), '{"outer": {"inner": "value"}}');
    });

    test('handles JSON with nested arrays', () {
      const input = '{"items": ["a", "b",]}';
      expect(JsonSanitizer.sanitize(input), '{"items": ["a", "b"]}');
    });

    test('preserves escaped quotes inside strings', () {
      const input = r'{"key": "He said \"hello\""}';
      expect(JsonSanitizer.sanitize(input), r'{"key": "He said \"hello\""}');
    });

    test('removes trailing commas in deeply nested objects', () {
      const input = '{"a": {"b": {"c": 1,},},}';
      expect(JsonSanitizer.sanitize(input), '{"a": {"b": {"c": 1}}}');
    });

    test('handles mixed trailing commas in objects and arrays', () {
      const input = '{"items": [1, 2,], "meta": {"count": 3,},}';
      expect(JsonSanitizer.sanitize(input), '{"items": [1, 2], "meta": {"count": 3}}');
    });

    test('strips thinking tags with complex content', () {
      const input = '<thinking>\nStep 1: Analyze\nStep 2: Conclude\n</thinking>{"result": true}';
      expect(JsonSanitizer.sanitize(input), '{"result": true}');
    });

    test('handles multiple JSON markers (extracts from first { to last })', () {
      // JSON extraction grabs from first '{' to last '}', including content between
      const input = 'JSON:\n{"first": true} JSON:\n{"second": false}';
      expect(JsonSanitizer.sanitize(input), '{"first": true} JSON:\n{"second": false}');
    });

    test('handles text before and after JSON with thinking tags', () {
      const input = 'Before <thinking>...</thinking>{"key": "value"} after';
      expect(JsonSanitizer.sanitize(input), '{"key": "value"}');
    });
  });

  group('JsonSanitizer.tryParse()', () {
    test('parses clean JSON', () {
      const input = '{"key": "value"}';
      expect(JsonSanitizer.tryParse(input), {'key': 'value'});
    });

    test('parses JSON with markdown fences', () {
      const input = '```json\n{"key": "value"}\n```';
      expect(JsonSanitizer.tryParse(input), {'key': 'value'});
    });

    test('parses JSON with trailing commas', () {
      const input = '{"key": "value",}';
      expect(JsonSanitizer.tryParse(input), {'key': 'value'});
    });

    test('returns null for completely invalid JSON', () {
      expect(JsonSanitizer.tryParse('not json at all'), isNull);
    });

    test('returns null for empty string', () {
      expect(JsonSanitizer.tryParse(''), isNull);
    });

    test('returns null for random text with no JSON object', () {
      expect(JsonSanitizer.tryParse('hello world'), isNull);
    });

    test('parses nested JSON objects', () {
      const input = '{"outer": {"inner": {"deep": true}}}';
      expect(JsonSanitizer.tryParse(input), {'outer': {'inner': {'deep': true}}});
    });

    test('returns null for JSON arrays (expects Map only)', () {
      // tryParse casts to Map<String, dynamic>, so arrays return null
      const input = '[1, 2, 3]';
      expect(JsonSanitizer.tryParse(input), isNull);
    });

    test('handles JSON with mixed types', () {
      const input = '{"name": "test", "count": 5, "active": true, "tags": ["a", "b"]}';
      final result = JsonSanitizer.tryParse(input);
      expect(result?['name'], 'test');
      expect(result?['count'], 5);
      expect(result?['active'], true);
      expect(result?['tags'], ['a', 'b']);
    });

    test('parses JSON after thinking tags', () {
      const input = '<thinking>Let me think...</thinking>\n{"answer": 42}';
      expect(JsonSanitizer.tryParse(input), {'answer': 42});
    });

    test('parses JSON with escaped quotes', () {
      const input = r'{"quote": "She said \"hello\""}';
      final result = JsonSanitizer.tryParse(input);
      expect(result?['quote'], 'She said "hello"');
    });

    test('parses JSON with newline escaping (sanitizer escapes, json.decode unescapes)', () {
      // The sanitizer converts real \n to literal \n in strings,
      // then json.decode interprets \n back to a real newline
      const input = '{"text": "line1\nline2"}';
      final result = JsonSanitizer.tryParse(input);
      expect(result?['text'], 'line1\nline2');
    });
  });
}
