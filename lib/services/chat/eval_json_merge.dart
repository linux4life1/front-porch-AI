// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Overlay a Director rewrite onto the original eval JSON. Omitted keys
// keep their original values (explicit 0 still wins). A rewrite that is
// not a JSON object is ignored. Tool-call envelopes use `arguments`.

import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Overlay [rewrite] onto [original] so a partial Director rewrite cannot
/// drop fields the downstream parse still needs.
String mergeEvalJson(String original, String rewrite) {
  final orig = parseEvalJsonObject(original);
  final next = parseEvalJsonObject(rewrite);
  if (orig == null) {
    return rewrite.trim().isEmpty ? original : rewrite;
  }
  if (next == null || next.isEmpty) return original;
  // Space after colon matches the Director's own `_correctedJson` /
  // replaceAll rewrites (`"fixation_topic": "none"`). Compact jsonEncode
  // would fail those contains() guards.
  return jsonEncode({...orig, ...next}).replaceAll('":', '": ');
}

/// First JSON object in [raw], or null. Flattens a tool-call envelope so
/// `arguments` become the fields we overlay.
Map<String, dynamic>? parseEvalJsonObject(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final decoded = _decodeMap(text) ?? _decodeMap(_sliceObject(text));
  if (decoded == null) return null;
  return _fieldsOf(decoded);
}

Map<String, dynamic>? _decodeMap(String? text) {
  if (text == null || text.isEmpty) return null;
  try {
    final decoded = jsonDecode(text);
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } catch (_) {}
  return null;
}

String? _sliceObject(String text) {
  final start = text.indexOf('{');
  final end = text.lastIndexOf('}');
  if (start < 0 || end <= start) return null;
  return text.substring(start, end + 1);
}

Map<String, dynamic> _fieldsOf(Map<String, dynamic> m) {
  final args = m['arguments'];
  if (args is Map && (m.containsKey('name') || m.containsKey('function'))) {
    return Map<String, dynamic>.from(args);
  }
  return m;
}

/// Fish one int out of a flat JSON-ish eval reply, or null when the key is
/// absent or not a bare number. Strict about the quoted key on purpose: the
/// evals emit `"hunger_delta"`, and a looser match would let a rule probe the
/// wrong field and silently score 0 (that shipped once — see
/// needs_verifier_hunger_delta_test).
///
/// Top-level so a caller can reach it without building an LlmEvalEngine;
/// [LlmEvalEngine.extractJsonInt] forwards here.
int? evalJsonInt(String text, String key) {
  final m = RegExp(
    '"${RegExp.escape(key)}"'
    r'\s*:\s*(-?\d+)',
  ).firstMatch(text);
  return m != null ? int.tryParse(m.group(1)!) : null;
}

/// Bool twin of [evalJsonInt].
bool? evalJsonBool(String text, String key) {
  final m = RegExp(
    '"${RegExp.escape(key)}"'
    r'\s*:\s*(true|false)',
  ).firstMatch(text);
  return m != null ? (m.group(1) == 'true') : null;
}

/// `"key": "<JSON string>"`, escape-aware: an escaped quote (`\"`) inside
/// the value does not end it. Group 1 is the still-escaped body. A
/// `[^"]*` body stopped at the first `\"`, so a reason that quoted someone
/// came back as a lone backslash.
RegExp evalJsonStringPattern(String key) => RegExp(
  '"${RegExp.escape(key)}"'
  r'\s*:\s*"((?:[^"\\]|\\.)*)"',
  dotAll: true,
);

/// String twin of [evalJsonInt]: the decoded value of a quoted field, or
/// null when the key is absent or not a string. Not trimmed; callers keep
/// their own trim / "none" handling. Both transports reach the parsers as
/// JSON text (tool-call arguments are re-encoded), so one decode serves both.
String? evalJsonString(String text, String key) {
  final m = evalJsonStringPattern(key).firstMatch(text);
  if (m == null) return null;
  return decodeEvalJsonStringBody(m.group(1)!);
}

/// Decode the body of a JSON string literal. Models sometimes break JSON
/// inside the string (a raw newline, `\'`); those fall back to a minimal
/// unescape instead of losing the field.
String decodeEvalJsonStringBody(String body) {
  if (!body.contains(r'\')) return body;
  try {
    final decoded = jsonDecode('"$body"');
    if (decoded is String) return decoded;
  } on FormatException catch (e) {
    debugPrint('[Eval:Json] string field not valid JSON, lenient unescape: $e');
  }
  return body.replaceAllMapped(RegExp(r'\\(.)', dotAll: true), (m) {
    final c = m.group(1)!;
    return switch (c) {
      'n' => '\n',
      't' => '\t',
      'r' => '\r',
      '"' || r'\' || '/' => c,
      _ => m.group(0)!,
    };
  });
}
