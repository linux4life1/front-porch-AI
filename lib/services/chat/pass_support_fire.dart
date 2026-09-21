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

part of 'pass_support.dart';

/// Schema salvage and the ONE tools-vs-text fire.
/// Owner loop and [ToolTransportProbe] stay on pass_support.dart.

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

String? usableEvalJsonText(
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
            usableEvalJsonText(
              resp.text,
              tools: tools,
              toolChoice: toolChoice,
              callToText: callToText,
            ) ??
            usableEvalJsonText(
              resp.reasoning,
              tools: tools,
              toolChoice: toolChoice,
              callToText: callToText,
            );
        if (salvaged != null) {
          onChunk?.call('$salvaged\n');
          return salvaged;
        }
        if (resp.isUnusableNativeToolCall) {
          debugPrint(
            '[Eval:Tools] $debugLabel empty tool_calls '
            '(finish_reason=tool_calls) — unusable, no text retry',
          );
          probe.noteInconclusive(backendIdentity);
          return null;
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
