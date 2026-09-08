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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/eval_json_merge.dart';
import 'package:front_porch_ai/services/chat/tool_eval_spec.dart';
import 'package:front_porch_ai/services/services.dart'
    show LlmToolCall, LlmToolResponse, OneShotMode, isToolTransportFailure;

/// Shared support for the two background maintenance passes (the Journal and
/// Growth Rings) — extracted from JournalMaintenance so the growth pass
/// reuses the identical owner loop and tools-probe memory instead of forking
/// them (docs/design/growth-rings.md §4.2/§4.3 consolidation).

/// Distinct pass owners appearing in [window]. 1:1 = the active character;
/// group = every group member who spoke (order of first appearance), falling
/// back to the active character for user-only windows. Ids that don't
/// resolve to a member (the director, departed speakers) are skipped.
///
/// [guests] (1:1 Scene Guests) are appended when they authored a message in
/// the window — the growth pass grows guests too (parity with the old
/// per-guest evolution); the Journal passes const [] (guests never journal).
List<CharacterCard> resolvePassOwners({
  required List<ChatMessage> window,
  required GroupChat? group,
  required List<CharacterCard> members,
  required CharacterCard? active,
  required String Function(CharacterCard) idOf,
  List<CharacterCard> guests = const [],
}) {
  if (group == null) {
    final owners = <CharacterCard>[?active];
    final activeId = active == null ? null : idOf(active);
    for (final guest in guests) {
      final gid = idOf(guest);
      if (gid.isEmpty || gid == activeId) continue;
      final spoke = window.any((m) => !m.isUser && m.characterId == gid);
      if (spoke) owners.add(guest);
    }
    return owners;
  }
  final owners = <CharacterCard>[];
  final seen = <String>{};
  for (final m in window) {
    if (m.isUser || m.characterId == '__director__') continue;
    final id = m.characterId;
    if (id == null || id.isEmpty || seen.contains(id)) continue;
    for (final c in members) {
      if (idOf(c) == id) {
        owners.add(c);
        seen.add(id);
        break;
      }
    }
  }
  if (owners.isEmpty) {
    if (active != null && members.contains(active)) return [active];
  }
  return owners;
}

/// A backend identity's native tool-calling verdict, as observed this run.
enum ToolCallSupport { untested, supported, unsupported }

/// Stable identity for eval transport capability state.
///
/// The endpoint component keeps two OpenAI-compatible providers with the same
/// model slug (for example Nano-GPT and OpenRouter) from sharing tool-probe,
/// tool-choice-style, or automatic one-shot state.
String evalBackendIdentityFor({
  required String backendName,
  required String remoteApiUrl,
  required String remoteModelName,
  required String? modelPath,
}) => '$backendName|${remoteApiUrl.trim()}|$remoteModelName|${modelPath ?? ''}';

/// Resolve the effective one-shot decision for a turn — pure, so the whole
/// policy is testable as a truth table (eval review Tier-1 §3.4).
///
/// [OneShotMode.auto] means: fuse on a REMOTE backend that has PROVEN native
/// tool calls (the probe verdict this run) — exactly the class of model the
/// combined prompt is easy for — and stay multi-call everywhere else,
/// including every local backend, where small models struggle with the fused
/// length (the reason the old bool defaulted off). An untested verdict
/// resolves multi-call: the first eval of the run probes, and Auto converges
/// from the next turn (usually sooner — ToolSupportTester pings on backend
/// change). The explicit modes always win in both directions.
///
/// [callMode] (2026-08-14, voice call overhaul, safe lane): on a live voice
/// call latency IS the product, so Off is upgraded to Auto's rule — the
/// fused single call — exactly where fusing is proven safe (remote + tools
/// verdict). The one-shot parity law guarantees 1:1 equivalent outputs, so
/// the only observable difference in a call is speed. On stays On, Auto
/// stays Auto, and local backends still never fuse (small models struggle
/// with the fused prompt length, call or no call).
bool resolveOneShotMode({
  required OneShotMode mode,
  required bool isLocal,
  required ToolCallSupport toolSupport,
  bool callMode = false,
  bool preferTextEvals = false,
}) {
  final toolsInUse =
      !preferTextEvals && toolSupport == ToolCallSupport.supported;
  return switch (mode) {
    OneShotMode.on => true,
    OneShotMode.off => callMode && !isLocal && toolsInUse,
    OneShotMode.auto => !isLocal && toolsInUse,
  };
}

/// Per-run memory of which backend identities can (or can't) speak the
/// OpenAI tools protocol — shared by every tool-negotiating consumer (the
/// Journal, Growth, and all structured evals) so a backend answers the probe
/// at most once per run no matter who asks first.
///
/// A ChangeNotifier so the chat sidebar's tool-calling pill repaints live as
/// verdicts land (from background passes or the manual test). Identity keys
/// carry the backend name + model, so switching models resets the verdict to
/// [ToolCallSupport.untested] by construction.
class ToolTransportProbe extends ChangeNotifier {
  /// true = tools confirmed working, false = XML/text-only.
  final Map<String, bool> _verdicts = {};
  final Set<String> _skipThisSend = {};
  final Map<String, int> _consecutiveInconclusive = {};
  final Set<String> _pausedUntilPing = {};
  bool _inUserSend = false;

  bool isXmlOnly(String backendIdentity) => _verdicts[backendIdentity] == false;

  bool isPausedUntilPing(String backendIdentity) =>
      _pausedUntilPing.contains(backendIdentity);

  bool isSkippedThisSend(String backendIdentity) =>
      _skipThisSend.contains(backendIdentity);

  void markXmlOnly(String backendIdentity) {
    if (_verdicts[backendIdentity] == false) return;
    _verdicts[backendIdentity] = false;
    notifyListeners();
  }

  /// Prefer-text override + skip/pause/xml-only. Journal/Growth and
  /// [fireStructuredEval] consult this before attempting tools.
  bool shouldFireTools(String id, {required bool preferTextEvals}) {
    if (preferTextEvals) return false;
    return shouldPostAfterIdle(id);
  }

  /// FIFO re-check / ping door. Skip, pause, xml-only — **not** prefer-text.
  /// `_fireToolEval` is also ToolSupportTester's ping. Passing live
  /// preferTextEvals here would make a pill tap with Native tool calling
  /// off never POST `report_ping`.
  ///
  /// Skip is honored only while a [beginUserSend] is open, so existing
  /// unit tests that fire two evals on one probe (no send) still re-probe,
  /// and the ping door is never silenced by leftover skip.
  bool shouldPostAfterIdle(String id) {
    if (isXmlOnly(id)) return false;
    if (_pausedUntilPing.contains(id)) return false;
    if (_inUserSend && _skipThisSend.contains(id)) return false;
    return true;
  }

  void beginUserSend() {
    _inUserSend = true;
    _skipThisSend.clear();
  }

  /// Count consecutive empty SENDS, then clear skip so regen retries tools.
  void endUserSend(String id) {
    if (_skipThisSend.contains(id)) {
      final n = (_consecutiveInconclusive[id] ?? 0) + 1;
      _consecutiveInconclusive[id] = n;
      if (n >= 2) {
        _pausedUntilPing.add(id);
        notifyListeners();
      }
    } else {
      _consecutiveInconclusive[id] = 0;
    }
    _skipThisSend.clear();
    _inUserSend = false;
  }

  /// Intra-send skip only. Do NOT increment consecutive here — three
  /// empty judges in one send must not pause.
  void noteInconclusive(String id) {
    final wasEmpty = _skipThisSend.isEmpty;
    _skipThisSend.add(id);
    if (wasEmpty) notifyListeners();
  }

  /// A tools-mode request on [backendIdentity] came back with real tool
  /// calls — the transport is confirmed working. Clears skip/consecutive
  /// **before** the already-supported early return. Pause is only [reset].
  void markSupported(String backendIdentity) {
    _consecutiveInconclusive[backendIdentity] = 0;
    _skipThisSend.remove(backendIdentity);
    if (_verdicts[backendIdentity] == true) return;
    _verdicts[backendIdentity] = true;
    notifyListeners();
  }

  /// Forget the verdict (manual retest / model reloaded under the same key).
  /// `|` not `||`: a supported identity's pill tap must still drop pause.
  void reset(String backendIdentity) {
    // `|` not `||`: a supported identity's pill tap must still drop pause.
    final droppedVerdict = _verdicts.remove(backendIdentity) != null;
    final droppedSkip = _skipThisSend.remove(backendIdentity);
    final droppedPause = _pausedUntilPing.remove(backendIdentity);
    final droppedConsecutive =
        _consecutiveInconclusive.remove(backendIdentity) != null;
    if (droppedVerdict | droppedSkip | droppedPause | droppedConsecutive) {
      notifyListeners();
    }
  }

  ToolCallSupport supportFor(String backendIdentity) =>
      switch (_verdicts[backendIdentity]) {
        true => ToolCallSupport.supported,
        false => ToolCallSupport.unsupported,
        null => ToolCallSupport.untested,
      };
}

/// The ONE tools-vs-text negotiation for structured evals whose downstream
/// consumes TEXT (realism evals, needs impact, scene time, expression
/// reclassify, cast detection — everything except the Journal/Growth passes,
/// which consume the call list directly).
///
/// Flow: unless [probe] already marked the backend text-only, fire the
/// tools-mode prompt; a matching call is converted by [callToText] into the
/// canonical text the downstream parser expects. A tool-less reply is
/// salvaged only when its text is valid JSON containing the selected tool's
/// required fields. Prose or partial JSON falls through to [fireTextEval].
/// Call-less replies, transport failures, cancellations ([isCancelled]), and
/// EMPTY answers (the shape a server-side abort produces as a clean 200) stay
/// inconclusive here; provider metadata and ToolSupportTester own the durable
/// capability verdict.
bool _matchesEvalSchema(
  Object? value,
  Map<dynamic, dynamic> schema, {
  String? field,
}) {
  if (value == null) return false;
  final allowed = schema['enum'];
  if (allowed is List && !allowed.contains(value)) return false;

  switch (schema['type']) {
    case 'object':
      if (value is! Map) return false;
      final properties = schema['properties'];
      if (properties is! Map) return false;
      final required = schema['required'];
      if (required is List &&
          required.any((key) => !value.containsKey(key.toString()))) {
        return false;
      }
      var recognized = value.isEmpty;
      for (final entry in value.entries) {
        final child = properties[entry.key];
        if (child is! Map) continue;
        recognized = true;
        if (!_matchesEvalSchema(
          entry.value,
          child,
          field: entry.key.toString(),
        )) {
          return false;
        }
      }
      return recognized;
    case 'array':
      if (value is! List) return false;
      final items = schema['items'];
      return items is Map &&
          value.every((item) => _matchesEvalSchema(item, items));
    case 'integer':
      return value is num || int.tryParse(value.toString().trim()) != null;
    case 'boolean':
      return value is bool ||
          const {
            'true',
            'false',
          }.contains(value.toString().trim().toLowerCase());
    case 'string':
      return value is String && (value.isNotEmpty || field == 'today_sentence');
    default:
      return false;
  }
}

String? _usableEvalJsonText(
  String text, {
  required List<Map<String, dynamic>> tools,
  required String? toolChoice,
  required String? Function(LlmToolResponse resp) callToText,
}) {
  final decoded = parseEvalJsonObject(text);
  if (decoded == null) return null;

  String? selectedName;
  Map<dynamic, dynamic>? parameters;
  for (final tool in tools) {
    final function = tool['function'];
    if (function is! Map) continue;
    final name = function['name']?.toString() ?? '';
    if (name == toolChoice ||
        ((toolChoice == null || toolChoice.isEmpty) && tools.length == 1)) {
      selectedName = name;
      final rawParameters = function['parameters'];
      if (rawParameters is Map) parameters = rawParameters;
      break;
    }
  }
  if (selectedName == null || parameters == null) return null;
  if (!_matchesEvalSchema(decoded, parameters)) return null;
  final requiredRaw = parameters['required'];
  final required = requiredRaw is List
      ? requiredRaw.map((field) => field.toString())
      : const <String>[];
  if (required.isEmpty && decoded.isEmpty) return text.trim();

  final normalized = callToText(
    LlmToolResponse(
      calls: [
        LlmToolCall(
          name: selectedName,
          arguments: Map<String, dynamic>.from(decoded),
        ),
      ],
      text: '',
    ),
  );
  if (normalized == null) return null;
  final dynamic normalizedJson;
  try {
    normalizedJson = jsonDecode(normalized);
  } catch (_) {
    return null;
  }
  if (normalizedJson is! Map) return null;
  if (!required.every(normalizedJson.containsKey)) {
    return null;
  }
  if (required.isEmpty &&
      decoded.isNotEmpty &&
      !normalizedJson.values.any(
        (value) => value != null && (value is! String || value.isNotEmpty),
      )) {
    return null;
  }
  return normalized;
}

Future<String?> fireStructuredEval({
  required ToolTransportProbe probe,
  required String backendIdentity,
  required String debugLabel,
  required List<Map<String, dynamic>> tools,
  required String Function({required bool toolsMode}) buildPrompt,
  required String? Function(LlmToolResponse resp) callToText,
  required Object fireToolEval,
  required Future<String?> Function(
    String prompt, {
    void Function(String)? onChunk,
  })
  fireTextEval,
  bool Function()? isCancelled,
  void Function(String)? onChunk,
  String? toolChoice,
  int maxLength = kScalarToolMaxTokens,
  double repeatPenalty = kScalarToolRepeatPenalty,
  bool Function()? getPreferTextEvals,
}) async {
  final preferText = getPreferTextEvals?.call() ?? false;
  if (probe.shouldFireTools(backendIdentity, preferTextEvals: preferText)) {
    var inconclusive = false;
    try {
      onChunk?.call('⏳ $debugLabel…\n');
      final resp = await invokeToolEval(
        fireToolEval,
        ToolEvalSpec(
          prompt: buildPrompt(toolsMode: true),
          tools: tools,
          toolChoice: toolChoice,
          maxLength: maxLength,
          repeatPenalty: repeatPenalty,
          onChunk: onChunk,
        ),
      );
      if (isCancelled?.call() ?? false) return null;
      if (resp != null) {
        final text = callToText(resp);
        if (text != null) {
          probe.markSupported(backendIdentity);
          // The overlay/raw-eval trace shows the synthesized text (the tools
          // lane doesn't stream tokens).
          onChunk?.call('$text\n');
          return text;
        }
        final salvaged =
            _usableEvalJsonText(
              resp.text,
              tools: tools,
              toolChoice: toolChoice,
              callToText: callToText,
            ) ??
            _usableEvalJsonText(
              resp.reasoning,
              tools: tools,
              toolChoice: toolChoice,
              callToText: callToText,
            );
        if (salvaged != null) {
          onChunk?.call('$salvaged\n');
          return salvaged;
        }
        if (resp.text.trim().isNotEmpty || resp.reasoning.trim().isNotEmpty) {
          debugPrint(
            '[Eval:Tools] $debugLabel returned prose or incomplete JSON — '
            'retrying with text transport',
          );
        }
      }
      inconclusive = true;
      // Null resp, or a resp with no usable call AND no text: an EMPTY
      // answer is never a capability verdict. A KoboldCpp server-side abort
      // (/api/extra/abort — fired by stopGeneration, the eval-timeout
      // teardown, or LlmEvalEngine's ensureServerIdle retry hygiene)
      // completes the in-flight call NORMALLY: HTTP 200, zero tokens, no
      // tool_calls — indistinguishable here from "model can't speak tools",
      // and exactly how the tool-calling pill kept falling to
      // "not supported" after a Scene Guest join (the guest flow stacks a
      // long mint generation + a burst of concurrent evals + abort/idle
      // traffic on the single-slot backend). Models that genuinely can't
      // speak tools answer with prose; the ToolSupportTester owns that durable
      // verdict. This pass falls back for THIS round and retries next pass.
    } catch (e) {
      debugPrint('[Eval:Tools] $debugLabel attempt failed: $e');
      if (isCancelled?.call() ?? false) return null;
      // A transport failure (unreachable backend, client torn down by an
      // app-side abortGeneration — the "visiting character creation resets
      // tool calling to not-supported" bug — a whole-call timeout, or a
      // busy/5xx server) is a network event, not a verdict on the MODEL's
      // tool support. generateWithTools rethrows those, so they land here
      // and are filtered instead of branding the backend XML-only.
      inconclusive = isToolTransportFailure(e);
    }
    if (inconclusive) {
      probe.noteInconclusive(backendIdentity);
      debugPrint(
        '[Eval:Tools] skipping (this-send) on $backendIdentity ($debugLabel)',
      );
    } else {
      probe.markXmlOnly(backendIdentity);
      debugPrint(
        '[Eval:Tools] Tools unavailable on $backendIdentity — using text '
        '($debugLabel)',
      );
    }
  } else if (preferText) {
    debugPrint('[Eval:Tools] skipping (override) on $backendIdentity');
  }
  return fireTextEval(buildPrompt(toolsMode: false), onChunk: onChunk);
}
