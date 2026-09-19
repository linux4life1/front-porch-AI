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

part of 'journal_maintenance.dart';

/// Exchange, resolve, and stamp helpers for [JournalMaintenance].
extension JournalMaintenanceExchange on JournalMaintenance {
  /// One owner's LLM exchange — tools first when the backend allows, XML
  /// otherwise (§4.3: two front doors, same (ops, recap) out). A backend
  /// that rejects the probe (null) or answers with neither tool calls nor
  /// salvageable tags is remembered as XML-only for the rest of the run, so
  /// the probe costs at most one extra round trip per backend identity.
  Future<(List<JournalOp>, String?)?> _runExchange({
    required CharacterCard owner,
    required List<JournalMemoryData> cards,
    required List<ChatMessage> window,
    required int windowStart,
    required bool includeRecap,
    required int startedEpoch,
  }) async {
    String prompt({required bool toolsMode}) => buildJournalPrompt(
      ownerName: owner.name,
      userName: getUserName(),
      recap: getRecap(),
      cards: cards,
      window: window,
      windowStart: windowStart,
      includeRecap: includeRecap,
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
            tools: kJournalTools,
            maxLength: kProseToolMaxTokens,
            repeatPenalty: kProseToolRepeatPenalty,
          ),
        );
      } catch (e) {
        // Transport failure (unreachable backend, the call torn down by an
        // app-side abortGeneration — e.g. character creation clearing state —
        // a whole-call timeout, or a busy/5xx server): a network event, never
        // a capability verdict. Fall back to XML for THIS round only; the
        // next pass probes tools again.
        debugPrint('[Journal] Tools attempt failed in transport: $e');
        transportFailure = isToolTransportFailure(e);
      }
      if (resp != null) {
        if (resp.calls.isNotEmpty) probe.markSupported(backend);
        var (ops, recap) = parseJournalToolCalls(resp.calls);
        if (ops.isEmpty && recap == null && resp.text.trim().isNotEmpty) {
          // The model ignored the tools but wrote text — salvage any tags.
          final text = stripThinkBlocks(resp.text);
          ops = parseJournalOps(text);
          recap = includeRecap ? parseRecap(text) : null;
        }
        if (ops.isNotEmpty || recap != null) return (ops, recap);
        if (resp.calls.isNotEmpty) {
          return (const <JournalOp>[], null);
        }
        if (resp.isUnusableNativeToolCall) {
          probe.noteInconclusive(backend);
          return null;
        }
        if (resp.text.trim().isNotEmpty) {
          // Prose with no tool call and no parseable tags: the model
          // ANSWERED and chose words over tools — real capability evidence.
          probe.markXmlOnly(backend);
          debugPrint('[Journal] Tools unavailable on $backend — using XML');
        } else {
          probe.noteInconclusive(backend);
        }
      } else {
        probe.noteInconclusive(backend);
        if (!transportFailure) {
          debugPrint(
            '[Journal] Tools inconclusive on $backend — XML this round',
          );
        }
      }
    }

    if (getPassEpoch() != startedEpoch) return null;
    final raw = await fireLLMEval(prompt(toolsMode: false));
    if (raw == null || raw.trim().isEmpty) return null;
    final text = stripThinkBlocks(raw);
    return (parseJournalOps(text), includeRecap ? parseRecap(text) : null);
  }

  /// Resolve parsed ops into id-addressed proposals while the pass context
  /// is live: 1-based handles become card ids (+ current text for the review
  /// UI), and the emotion stamp is read from the cited messages. The applier
  /// then needs no window, and user edits between proposal and apply can't
  /// shift what an op targets.
  List<JournalProposedOp> _resolveOps(
    List<JournalOp> ops,
    List<JournalMemoryData> cards,
    List<ChatMessage> window,
    int windowStart,
  ) {
    final resolved = <JournalProposedOp>[];
    for (final op in ops) {
      switch (op.action) {
        case JournalOpAction.add:
          final stamp = _emotionStamp(op.sourcePositions, window, windowStart);
          final date = _dateStamp(op.sourcePositions, window, windowStart);
          resolved.add(
            JournalProposedOp(
              action: op.action,
              text: op.text,
              category: op.category,
              emotionLabel: stamp?.$1,
              emotionIntensity: stamp?.$2,
              sourcePositions: op.sourcePositions,
              storyDay: date.$1,
              storyClock: date.$2,
            ),
          );
          break;
        case JournalOpAction.revise:
        case JournalOpAction.retire:
        case JournalOpAction.pin:
          final card = _cardForHandle(cards, op.handle);
          if (card == null) continue;
          if (JournalPhysics.isPassLockedCard(card) &&
              op.action != JournalOpAction.pin) {
            continue;
          }
          resolved.add(
            JournalProposedOp(
              action: op.action,
              cardId: card.id,
              oldContent: card.content,
              text: op.text,
              feeling: op.feeling,
            ),
          );
          break;
      }
    }
    return resolved;
  }

  JournalMemoryData? _cardForHandle(
    List<JournalMemoryData> cards,
    int? handle,
  ) {
    if (handle == null || handle < 1 || handle > cards.length) return null;
    return cards[handle - 1];
  }

  /// Deterministic emotion stamp for a new card: the strongest recorded
  /// feeling among the cited messages, falling back to the last annotated
  /// message in the window. Returns (label, intensity) or null.
  (String, String?)? _emotionStamp(
    List<int> positions,
    List<ChatMessage> window,
    int windowStart,
  ) {
    (String, String?)? best;
    var bestRank = -1;

    void consider(ChatMessage m) {
      final label = m.activeMetadata?['emotion_label'];
      if (label is! String || label.isEmpty) return;
      final intensity = journalIntensityOf(m);
      final rank = switch (intensity) {
        'strong' => 3,
        'moderate' => 2,
        'mild' => 1,
        _ => 0,
      };
      if (rank > bestRank) {
        bestRank = rank;
        best = (label, intensity);
      }
    }

    for (final pos in positions) {
      final idx = pos - windowStart;
      if (idx >= 0 && idx < window.length) consider(window[idx]);
    }
    if (best == null) {
      for (final m in window.reversed) {
        consider(m);
        if (best != null) break;
      }
    }
    return best;
  }

  /// Deterministic story-date stamp for a new card (story-calendar §4): the
  /// LATEST cited message's realism_state time (a memory happened when its
  /// last cited moment happened), falling back to the last annotated message
  /// in the window, then to the current story time. Sibling of
  /// [_emotionStamp] — different selection rule (latest vs strongest), same
  /// snapshot-while-live contract. Returns (storyDay, storyClockIso).
  (int?, String?) _dateStamp(
    List<int> positions,
    List<ChatMessage> window,
    int windowStart,
  ) {
    (int?, String?)? found;

    void consider(ChatMessage m) {
      final state = m.activeMetadata?['realism_state'];
      if (state is! Map) return;
      final day = (state['dayCount'] as num?)?.toInt();
      final clock = state['storyClock'] as String?;
      if (day == null && clock == null) return;
      found = (day, clock);
    }

    for (final pos in positions.toList()..sort()) {
      final idx = pos - windowStart;
      if (idx >= 0 && idx < window.length) consider(window[idx]);
    }
    if (found == null) {
      for (final m in window.reversed) {
        consider(m);
        if (found != null) break;
      }
    }
    return found ?? (getCurrentStoryDay(), getCurrentStoryClockIso());
  }
}
