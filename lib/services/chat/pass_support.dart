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

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/chat_message.dart';
import 'package:front_porch_ai/models/group_chat.dart';
import 'package:front_porch_ai/services/llm_service.dart'
    show LlmToolResponse, isToolTransportFailure;

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
      final spoke = window.any(
        (m) => !m.isUser && m.characterId == gid,
      );
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

  bool isXmlOnly(String backendIdentity) => _verdicts[backendIdentity] == false;

  void markXmlOnly(String backendIdentity) {
    if (_verdicts[backendIdentity] == false) return;
    _verdicts[backendIdentity] = false;
    notifyListeners();
  }

  /// A tools-mode request on [backendIdentity] came back with real tool
  /// calls — the transport is confirmed working.
  void markSupported(String backendIdentity) {
    if (_verdicts[backendIdentity] == true) return;
    _verdicts[backendIdentity] = true;
    notifyListeners();
  }

  /// Forget the verdict (manual retest / model reloaded under the same key).
  void reset(String backendIdentity) {
    if (_verdicts.remove(backendIdentity) != null) notifyListeners();
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
/// canonical text the downstream parser expects; a tool-less reply with text
/// is salvaged through the same parser; anything else marks the backend
/// text-only for the run and falls back to the streaming text path — UNLESS
/// [isCancelled] fires, because a user-aborted request is a cancellation,
/// never a capability verdict.
Future<String?> fireStructuredEval({
  required ToolTransportProbe probe,
  required String backendIdentity,
  required String debugLabel,
  required List<Map<String, dynamic>> tools,
  required String Function({required bool toolsMode}) buildPrompt,
  required String? Function(LlmToolResponse resp) callToText,
  required Future<LlmToolResponse?> Function(
    String prompt,
    List<Map<String, dynamic>> tools,
  )
  fireToolEval,
  required Future<String?> Function(
    String prompt, {
    void Function(String)? onChunk,
  })
  fireTextEval,
  bool Function()? isCancelled,
  void Function(String)? onChunk,
}) async {
  if (!probe.isXmlOnly(backendIdentity)) {
    var transportFailure = false;
    try {
      final resp = await fireToolEval(buildPrompt(toolsMode: true), tools);
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
        if (resp.text.trim().isNotEmpty) {
          onChunk?.call('${resp.text}\n');
          return resp.text;
        }
      }
    } catch (e) {
      debugPrint('[Eval:Tools] $debugLabel attempt failed: $e');
      if (isCancelled?.call() ?? false) return null;
      // A transport failure (unreachable backend, client torn down by an
      // app-side abortGeneration — the "visiting character creation resets
      // tool calling to not-supported" bug — a whole-call timeout, or a
      // busy/5xx server) is a network event, not a verdict on the MODEL's
      // tool support. generateWithTools rethrows those, so they land here
      // and are filtered instead of branding the backend XML-only.
      transportFailure = isToolTransportFailure(e);
    }
    if (!transportFailure) {
      probe.markXmlOnly(backendIdentity);
      debugPrint(
        '[Eval:Tools] Tools unavailable on $backendIdentity — using text '
        '($debugLabel)',
      );
    }
  }
  return fireTextEval(buildPrompt(toolsMode: false), onChunk: onChunk);
}
