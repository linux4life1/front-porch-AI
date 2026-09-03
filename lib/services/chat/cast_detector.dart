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
import 'dart:developer';

import 'package:front_porch_ai/services/chat/pass_support.dart';
import 'package:front_porch_ai/services/chat/realism_tools.dart';

/// A side character the primary (host) narrated into the scene who looks like a
/// recurring, named participant the user might want to promote to a Scene Guest.
class DetectedCharacter {
  const DetectedCharacter({required this.name, required this.descriptor});

  /// The proper name the host gave them (e.g. "Mara", "Old Bartender Greaves").
  final String name;

  /// A one-line descriptor used as the mint concept (e.g. "the host's sister").
  final String descriptor;
}

/// Periodically scans the recent PRIMARY narration of a 1:1 chat for a newly
/// introduced, recurring, NAMED side character and surfaces it as a candidate
/// Scene Guest (Lite NPC).
///
/// Pure leaf, modelled exactly on [SceneGuestDirector]: it never imports
/// `ChatService` (or any heavy service); everything it needs is injected as a
/// small callback, so it stays unit-testable with plain closures. It does ZERO
/// Realism / Needs work — it only reads text and proposes a name. Accepting the
/// proposal routes back through the existing parity-safe mint+enter flow.
///
/// One token-cheap LLM eval per scan (reusing the injected [fireLLMEval] +
/// [stripThinkBlocks] surface — no new LLM-firing path). It asks for any
/// newly-introduced, named character who appears to be a RECURRING participant
/// (not a one-off passing mention, not the host, not the user), returning strict
/// JSON `{"name": ..., "descriptor": ...}` or `{"name": null}`. It defaults to
/// "no detection" on empty / parse failure (the KoboldCPP empty-eval gotcha —
/// see CLAUDE.md), then filters the candidate against the host name, the user
/// name, the current Scene Guests, and the already-offered/ignored set.
class CastDetector {
  CastDetector({
    required List<String> Function() getRecentPrimaryTexts,
    required Future<String?> Function(String prompt) fireLLMEval,
    required String Function(String text) stripThinkBlocks,
    required String Function() getHostName,
    required String Function() getUserName,
    required List<String> Function() getSceneGuestNames,
    required Set<String> Function() getOfferedOrIgnoredNames,
    Object? fireToolEval,
    ToolTransportProbe? probe,
    String Function()? getBackendIdentity,
  }) : _getRecentPrimaryTexts = getRecentPrimaryTexts,
       _fireLLMEval = fireLLMEval,
       _stripThinkBlocks = stripThinkBlocks,
       _getHostName = getHostName,
       _getUserName = getUserName,
       _getSceneGuestNames = getSceneGuestNames,
       _getOfferedOrIgnoredNames = getOfferedOrIgnoredNames,
       _fireToolEval = fireToolEval,
       _probe = probe,
       _getBackendIdentity = getBackendIdentity;

  final List<String> Function() _getRecentPrimaryTexts;
  final Future<String?> Function(String prompt) _fireLLMEval;
  final String Function(String text) _stripThinkBlocks;
  final String Function() _getHostName;
  final String Function() _getUserName;
  final List<String> Function() _getSceneGuestNames;
  final Set<String> Function() _getOfferedOrIgnoredNames;

  // Tools transport (nullable — tests and tool-less hosts stay on the text
  // path; the god wires the shared probe/door the other evals use).
  final Object? _fireToolEval;
  final ToolTransportProbe? _probe;
  final String Function()? _getBackendIdentity;

  /// Run one detection pass. Returns a fresh, filtered [DetectedCharacter] or
  /// `null` when there is nothing worth surfacing (no narration, empty/garbled
  /// eval, no candidate, or the candidate fails a filter).
  Future<DetectedCharacter?> detect() async {
    final texts = _getRecentPrimaryTexts()
        .where((t) => t.trim().isNotEmpty)
        .toList();
    if (texts.isEmpty) return null;

    final raw = _fireToolEval != null && _probe != null
        ? await fireStructuredEval(
            probe: _probe,
            backendIdentity: _getBackendIdentity?.call() ?? '',
            debugLabel: kCastDetectTool,
            tools: kCastDetectEvalTools,
            buildPrompt: ({required toolsMode}) =>
                _buildPrompt(texts, toolsMode: toolsMode),
            callToText: (resp) =>
                realismToolCallToJson(kCastDetectTool, resp.calls),
            fireToolEval: _fireToolEval,
            toolChoice: kCastDetectTool,
            fireTextEval: (p, {onChunk}) => _fireLLMEval(p),
          )
        : await _fireLLMEval(_buildPrompt(texts, toolsMode: false));
    if (raw == null) return null; // empty / cancelled / backend down
    final text = _stripThinkBlocks(raw).trim();
    if (text.isEmpty) return null;

    final candidate = _parse(text);
    if (candidate == null) return null;
    return _accept(candidate) ? candidate : null;
  }

  /// Tiny extraction prompt — the recent primary narration + strict JSON (or
  /// the tool ask; the body is byte-identical between transports).
  String _buildPrompt(List<String> texts, {required bool toolsMode}) {
    final host = _getHostName();
    final user = _getUserName();
    final narration = texts.map((t) => '- ${_oneLine(t)}').join('\n');
    return 'In a roleplay, "$host" is the main character and "$user" is the user. '
        'Read $host\'s recent narration below and find any OTHER named character '
        '$host has introduced who seems to be a RECURRING participant in the '
        'scene (e.g. a sibling, friend, rival, or regular like a bartender) — '
        'NOT a one-off passing mention, NOT $host, NOT $user.\n\n'
        'Recent narration:\n$narration\n\n'
        '${toolsMode ? 'Report by calling the $kCastDetectTool tool: pass their name and a short '
                  'descriptor when there is exactly one such recurring named character, or call it '
                  'with no name when there is none. Use ONLY the tool — no plain-text reply.' : 'If there is exactly one such recurring named character, respond with '
                  'ONLY this JSON: {"name": "<their name>", "descriptor": "<a short '
                  'phrase describing who they are>"}\n'
                  'If there is no such character (or only passing mentions), respond with '
                  'ONLY: {"name": null}'}';
  }

  /// Parse the strict JSON reply into a candidate (pre-filter). Tolerant of
  /// surrounding prose / code fences; defaults to null on any failure.
  DetectedCharacter? _parse(String text) {
    var jsonStr = text;
    if (jsonStr.contains('```')) {
      final fence = RegExp(
        r'```(?:json)?\s*\n?(.*?)\n?```',
        dotAll: true,
      ).firstMatch(jsonStr);
      if (fence != null) jsonStr = fence.group(1)!.trim();
    }
    // Extract the FIRST balanced {...} object. A greedy `\{.*\}` would span from
    // the first '{' to the LAST '}', so any trailing prose containing a brace
    // (common — models append explanation despite "ONLY this JSON") yields
    // invalid JSON and silently kills detection.
    final objStr = _firstJsonObject(jsonStr);
    if (objStr == null) return null;

    Map<String, dynamic> obj;
    try {
      obj = jsonDecode(objStr) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }

    final rawName = obj['name'];
    if (rawName is! String) return null; // null or non-string → no detection
    final name = rawName.trim();
    final descriptor = (obj['descriptor'] is String)
        ? (obj['descriptor'] as String).trim()
        : '';
    return DetectedCharacter(name: name, descriptor: descriptor);
  }

  /// Return the first balanced `{...}` object in [s] (brace-counting, string &
  /// escape aware), or null if there is none. Used instead of a greedy regex so
  /// trailing prose after the object can't break JSON decoding.
  String? _firstJsonObject(String s) {
    final start = s.indexOf('{');
    if (start < 0) return null;
    var depth = 0;
    var inString = false;
    var escape = false;
    for (var i = start; i < s.length; i++) {
      final c = s[i];
      if (escape) {
        escape = false;
        continue;
      }
      if (c == '\\') {
        escape = true;
        continue;
      }
      if (c == '"') {
        inString = !inString;
        continue;
      }
      if (inString) continue;
      if (c == '{') {
        depth++;
      } else if (c == '}') {
        depth--;
        if (depth == 0) return s.substring(start, i + 1);
      }
    }
    return null;
  }

  /// Final filter: require a plausible proper name and reject the host, the
  /// user, an existing Scene Guest, or anything already offered/ignored.
  bool _accept(DetectedCharacter c) {
    final name = c.name.trim();
    // Plausible proper name: non-empty and contains at least one letter.
    if (name.isEmpty || !RegExp(r'[A-Za-z]').hasMatch(name)) return false;

    final lower = name.toLowerCase();
    final host = _getHostName().trim().toLowerCase();
    final user = _getUserName().trim().toLowerCase();

    // Reject if it equals/contains the host or user name (either direction).
    if (_collides(lower, host) || _collides(lower, user)) {
      log('[CastDetector] Rejected "$name" (host/user collision).');
      return false;
    }

    // Reject names already present as Scene Guests.
    for (final g in _getSceneGuestNames()) {
      if (_collides(lower, g.trim().toLowerCase())) {
        log('[CastDetector] Rejected "$name" (already a scene guest).');
        return false;
      }
    }

    // Reject anything already offered or explicitly ignored this session.
    if (_getOfferedOrIgnoredNames().contains(lower)) {
      log('[CastDetector] Rejected "$name" (already offered/ignored).');
      return false;
    }
    return true;
  }

  /// Name collision, token-aware. True when the two names are equal OR share a
  /// significant (≥3-char, non-title) whole-word token — so "Mara" collides with
  /// "Mara Vance" / "Dr. Mara Vance", but a raw-substring overlap does NOT
  /// (the old `contains` logic wrongly suppressed "Fred"/"Ned" when the host was
  /// "Ed", or "Samuel" when the host was "Sam").
  bool _collides(String a, String b) {
    final na = a.trim().toLowerCase();
    final nb = b.trim().toLowerCase();
    if (na.isEmpty || nb.isEmpty) return false;
    if (na == nb) return true;
    final ta = _significantTokens(na);
    final tb = _significantTokens(nb);
    if (ta.isEmpty || tb.isEmpty) return false; // short names: exact-only
    return ta.any(tb.contains);
  }

  /// Lower-cased name tokens worth matching on: ≥3 chars and not a title/article.
  Set<String> _significantTokens(String lowerName) => lowerName
      .split(RegExp(r'[^a-z0-9]+'))
      .where((t) => t.length >= 3 && !_nameStopwords.contains(t))
      .toSet();

  static const Set<String> _nameStopwords = {
    'the',
    'and',
    'her',
    'his',
    'old',
    'young',
    'big',
    'mrs',
    'miss',
    'dr',
    'doctor',
    'professor',
    'prof',
    'sir',
    'lady',
    'lord',
    'madam',
    'madame',
    'master',
    'mistress',
    'captain',
    'major',
    'colonel',
    'general',
    'sergeant',
    'officer',
    'detective',
    'king',
    'queen',
    'prince',
    'princess',
    'duke',
    'duchess',
    'count',
    'countess',
    'baron',
    'father',
    'mother',
    'brother',
    'sister',
    'uncle',
    'aunt',
    'saint',
  };

  String _oneLine(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();
}
