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
import 'package:front_porch_ai/services/chat/tool_verdict_stamp.dart';
import 'package:front_porch_ai/services/services.dart'
    show
        LlmRequestCancel,
        LlmToolCall,
        LlmToolResponse,
        OneShotMode,
        isToolTransportFailure;
import 'package:front_porch_ai/services/storage/storage.dart'
    show ToolVerdictSettings;
import 'package:front_porch_ai/utils/utils.dart' show namesUnknownLocalModel;

part 'pass_support_fire.dart';

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

/// The tool-calling verdict a studio wizard reads (see
/// `ChatService.toolCheckFor`).
typedef StudioToolCheck = ({
  ToolCallSupport support,
  bool testing,
  bool backendReady,
});

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

/// Memory of which backend identities can (or can't) speak the OpenAI tools
/// protocol — shared by every tool-negotiating consumer (the Journal, Growth,
/// and all structured evals) so a model answers the probe once no matter who
/// asks first.
///
/// A ChangeNotifier so the chat sidebar's tool-calling pill repaints live as
/// verdicts land (from background passes or the manual test). Identity keys
/// carry the backend name + model, so switching models resets the verdict to
/// [ToolCallSupport.untested] by construction.
///
/// With a [store], settled verdicts outlive the run: every verdict that lands
/// is written through to it, and a model it already knows is answered from it
/// before anything is asked. Skip, pause and inconclusive counts are per run
/// and never stored.
///
/// Distinct from `OpenRouterToolSupport` (services/openrouter_tool_support.dart)
/// on purpose. That one is inside the HTTP door and answers "is a `tools` POST
/// to this openrouter.ai route worth making", from the provider catalog and from
/// 400/404 bodies, keyed by model id. This one sits above any transport and
/// answers "did a real attempt produce tool calls, and should the next eval in
/// this send try again", for every backend including Kobold and oMLX. Do not
/// merge them: the transport would inherit per-send skip/pause bookkeeping, and
/// this probe would inherit one provider's catalog semantics.
class ToolTransportProbe extends ChangeNotifier {
  /// Where settled verdicts are kept between runs; null keeps them for this
  /// run only. Attached by the owner once storage exists.
  ToolVerdictSettings? store;

  /// true = tools confirmed working, false = XML/text-only. This run's
  /// verdicts; a model [store] knows and this run has not met is read from it.
  final Map<String, bool> _verdicts = {};
  final Set<String> _skipThisSend = {};
  final Map<String, int> _consecutiveInconclusive = {};
  final Set<String> _pausedUntilPing = {};
  bool _inUserSend = false;

  /// The stamp that holds now for [identity] (app, and engine for a local
  /// model), set by the owner. Null: kept answers are not stamped.
  String Function(String identity)? stampFor;

  /// This run's verdict, else the kept one. A kept "no" given under another
  /// engine or app is unknown again, so tools are tried and the model asked
  /// once more; a kept "yes" stands.
  bool? _verdictFor(String id) {
    final run = _verdicts[id];
    if (run != null) return run;
    final kept = store?.verdictFor(id);
    if (kept == false && !_keptNoStands(id)) return null;
    return kept;
  }

  bool _keptNoStands(String id) {
    final now = stampFor?.call(id);
    if (now == null) return true;
    return toolVerdictStampHolds(store?.stampFor(id) ?? '', now);
  }

  /// A verdict is kept for a model that can be named; one given while the
  /// engine ran a model nobody had confirmed belongs to none.
  bool _keepable(String id) => !namesUnknownLocalModel(id);

  bool isXmlOnly(String backendIdentity) =>
      _verdictFor(backendIdentity) == false;

  /// True when the answer for [backendIdentity] was kept from an earlier run
  /// and nothing this run has settled it since (the sidebar pill says so, and
  /// that a tap asks again).
  bool isKept(String backendIdentity) =>
      !_verdicts.containsKey(backendIdentity) &&
      _verdictFor(backendIdentity) != null;

  bool isPausedUntilPing(String backendIdentity) =>
      _pausedUntilPing.contains(backendIdentity);

  bool isSkippedThisSend(String backendIdentity) =>
      _skipThisSend.contains(backendIdentity);

  void markXmlOnly(String backendIdentity) {
    if (_verdictFor(backendIdentity) == false) return;
    _verdicts[backendIdentity] = false;
    if (_keepable(backendIdentity)) {
      store?.remember(
        backendIdentity,
        false,
        stamp: stampFor?.call(backendIdentity) ?? '',
      );
    }
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
    if (_verdictFor(backendIdentity) == true) return;
    _verdicts[backendIdentity] = true;
    if (_keepable(backendIdentity)) store?.remember(backendIdentity, true);
    notifyListeners();
  }

  /// Forget the verdict (manual retest / model reloaded under the same key),
  /// the kept one too: if the retest settles nothing the model is simply
  /// unknown again and the next run asks.
  /// `|` not `||`: a supported identity's pill tap must still drop pause.
  void reset(String backendIdentity) {
    // `|` not `||`: a supported identity's pill tap must still drop pause.
    final droppedVerdict =
        (_verdicts.remove(backendIdentity) != null) |
        (store?.forget(backendIdentity) ?? false);
    final droppedSkip = _skipThisSend.remove(backendIdentity);
    final droppedPause = _pausedUntilPing.remove(backendIdentity);
    final droppedConsecutive =
        _consecutiveInconclusive.remove(backendIdentity) != null;
    if (droppedVerdict | droppedSkip | droppedPause | droppedConsecutive) {
      notifyListeners();
    }
  }

  ToolCallSupport supportFor(String backendIdentity) =>
      switch (_verdictFor(backendIdentity)) {
        true => ToolCallSupport.supported,
        false => ToolCallSupport.unsupported,
        null => ToolCallSupport.untested,
      };
}
