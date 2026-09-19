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

part of 'growth_service.dart';

/// Exchange + resolve helpers for [GrowthService].
extension GrowthServiceExchange on GrowthService {
  /// One owner's LLM exchange — tools first when the backend allows, XML
  /// otherwise (shared probe memory with the Journal pass). Null means the
  /// backend produced nothing usable.
  Future<List<GrowthOp>?> _runExchange({
    required CharacterCard owner,
    required List<GrowthRingData> activeRings,
    required List<JournalMemoryData> journalCards,
    required List<ChatMessage> window,
    required int windowStart,
    required String legacyBlob,
    required int startedEpoch,
  }) async {
    String prompt({required bool toolsMode}) => buildGrowthPrompt(
      ownerName: owner.name,
      userName: getUserName(),
      basePersonality: [
        if (owner.description.isNotEmpty) owner.description,
        if (owner.personality.isNotEmpty) owner.personality,
      ].join('\n'),
      recap: getRecap(),
      activeRings: activeRings,
      journalCards: journalCards,
      window: window,
      windowStart: windowStart,
      legacyBlob: legacyBlob,
      toolsMode: toolsMode,
    );

    final backend = getBackendIdentity();
    if (probe.shouldFireTools(backend, preferTextEvals: getPreferTextEvals())) {
      LlmToolResponse? resp;
      var transportFailure = false;
      try {
        resp = await invokeToolEval(
          fireToolEval,
          ToolEvalSpec(
            prompt: prompt(toolsMode: true),
            tools: kGrowthTools,
            maxLength: kProseToolMaxTokens,
            repeatPenalty: kProseToolRepeatPenalty,
          ),
        );
      } catch (e) {
        // Transport failure (unreachable backend, the call torn down by an
        // app-side abortGeneration, a whole-call timeout, or a busy/5xx
        // server): a network event, never a capability verdict. Fall back to
        // XML for THIS round only; the next pass probes tools again.
        // Mirrors the Journal's handling exactly.
        debugPrint('[Growth] Tools attempt failed in transport: $e');
        transportFailure = isToolTransportFailure(e);
      }
      if (resp != null) {
        if (resp.calls.isNotEmpty) probe.markSupported(backend);
        var ops = parseGrowthToolCalls(resp.calls);
        if (ops.isEmpty && resp.text.trim().isNotEmpty) {
          // The model ignored the tools but wrote text — salvage any tags.
          ops = parseGrowthOps(stripThinkBlocks(resp.text));
        }
        if (ops.isNotEmpty) return ops;
        if (resp.calls.isNotEmpty) {
          return const [];
        }
        if (resp.isUnusableNativeToolCall) {
          probe.noteInconclusive(backend);
          return null;
        }
        if (resp.text.trim().isNotEmpty) {
          // Prose with no tool call and no parseable tags: the model
          // ANSWERED and chose words over tools — real capability evidence.
          probe.markXmlOnly(backend);
          debugPrint('[Growth] Tools unavailable on $backend — using XML');
        } else {
          probe.noteInconclusive(backend);
        }
      } else {
        probe.noteInconclusive(backend);
        if (!transportFailure) {
          debugPrint(
            '[Growth] Tools inconclusive on $backend — XML this round',
          );
        }
      }
    }

    if (getPassEpoch() != startedEpoch) return null;
    final raw = await fireLLMEval(prompt(toolsMode: false));
    if (raw == null || raw.trim().isEmpty) return null;
    return parseGrowthOps(stripThinkBlocks(raw));
  }

  /// Resolve parsed ops into id-addressed proposals while the pass snapshot
  /// is live: 1-based handles become ring ids (+ current text for the review
  /// UI), and {{char}}/{{user}} macros the model wrote become real names —
  /// the review dialog displays proposal text verbatim, so placeholders must
  /// be gone before parking (the store resolves again at write time, which
  /// is then a no-op). Distill-mode adds seed at the higher starter strength.
  List<GrowthProposedOp> _resolveOps(
    List<GrowthOp> ops,
    List<GrowthRingData> activeRings, {
    required bool distillMode,
    required String ownerName,
  }) {
    String named(String text) =>
        resolveGrowthMacros(text, charName: ownerName, userName: getUserName());
    final resolved = <GrowthProposedOp>[];
    for (final op in ops) {
      switch (op.action) {
        case GrowthOpAction.add:
          resolved.add(
            GrowthProposedOp(
              action: op.action,
              text: named(op.text),
              category: op.category,
              sourcePositions: op.sourcePositions,
              seedStrength: distillMode
                  ? GrowthPhysics.kDistillSeedStrength
                  : GrowthPhysics.kNewRingStrength,
            ),
          );
          break;
        case GrowthOpAction.reinforce:
        case GrowthOpAction.revise:
        case GrowthOpAction.retire:
          final handle = op.handle;
          if (handle == null || handle < 1 || handle > activeRings.length) {
            continue;
          }
          final ring = activeRings[handle - 1];
          // User-pinned rings are permanent: the pass may reinforce or
          // reword them, but only the diary UI may retire them.
          if (op.action == GrowthOpAction.retire && ring.pinned) continue;
          resolved.add(
            GrowthProposedOp(
              action: op.action,
              ringId: ring.id,
              oldContent: ring.content,
              text: named(op.text),
              sourcePositions: op.sourcePositions,
            ),
          );
          break;
      }
    }
    return resolved;
  }
}
