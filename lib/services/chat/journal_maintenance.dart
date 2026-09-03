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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/services.dart';
import 'journal_ops.dart';
import 'journal_physics.dart';
import 'journal_prompt.dart';
import 'journal_review.dart';
import 'journal_store.dart';
import 'pass_support.dart';
import 'tool_eval_spec.dart';

/// The Journal — the one periodic background job
/// (docs/design/journal-memory.md §4.2). Replaces BOTH the old SummaryService
/// and FactExtraction with a single eval call per diary owner per pass,
/// producing (a) memory-card operations and (b) the per-chat "Where we are"
/// recap (written into the same _summary slot the old summary used, so the
/// injection plumbing, sidebar, web facade, and the growth pass's recap
/// dependency keep working untouched).
///
/// Plain leaf, callback-wired like its dead siblings. Reuses only existing
/// god state (_summary, _summaryLastIndex, _isSummaryGenerating via cbs) —
/// no new flags, so every existing reset/zeroing hygiene site keeps working.
///
/// Key invariants:
/// - Strictly per-chat: cards are read and written for the CURRENT session
///   only; a session switch mid-pass aborts recap/cursor writes (card writes
///   target the captured session id, which is safe either way).
/// - Salience is deterministic, not judged: the window is pre-annotated with
///   engine-stamped per-message metadata (journal_prompt.dart). Emotion
///   stamping is read, not asked: a new card's feeling comes from the cited
///   messages' recorded metadata — never from the model.
/// - 1:1 ↔ group parity by construction: the same owner loop runs in both
///   modes (1:1 = one owner). Scene guests never journal (unresolvable ids
///   are skipped — the guest parity guard).
/// - Two transports, one applier (§4.3): tool calls when the backend accepts
///   them ([_runExchange] probes once per backend identity per run, then
///   remembers), XML tags everywhere else — both normalize to the same
///   [JournalOp] list, resolved here into id-addressed proposals and applied
///   through [JournalReview.applyOwnerProposals] whether immediately or
///   after user review (review-first mode).
/// - Local-model floor: XML-tag transport (journal_ops.dart), reasoning off +
///   think-strip via the shared LlmEvalEngine plumbing.
class JournalMaintenance {
  final JournalStore store;

  /// Review-first parking + the single proposal applier (both modes).
  final JournalReview review;

  /// Tools-vs-XML probe memory, shared with the growth pass (pass_support) —
  /// one probe per backend identity per run no matter which pass asks first.
  final ToolTransportProbe probe;

  final Future<String?> Function(String prompt) fireLLMEval;

  /// Tool-calling door (LLMService.generateWithTools): null result means the
  /// backend can't (or won't) speak tools and this run should use XML; a
  /// THROW is a transport failure (unreachable/aborted/timeout/busy) and
  /// must not brand the backend — see isToolTransportFailure.
  final Object fireToolEval;
  final bool Function() getPreferTextEvals;

  /// Regen bumps this; a pass started against the rejected window must not
  /// apply, and must not fall through to XML after tools abort.
  final int Function() getPassEpoch;

  final String Function(String) stripThinkBlocks;

  final String? Function() getSessionId;
  final CharacterCard? Function() getActiveCharacter;
  final GroupChat? Function() getActiveGroup;
  final List<CharacterCard> Function() getGroupCharacters;
  final String Function(CharacterCard) getCharacterIdFromCard;
  final List<ChatMessage> Function() getMessages;
  final String Function() getUserName;

  /// Pass cursor — reuses the god's _summaryLastIndex scalar (persisted to
  /// Sessions.summaryLastIndex; zeroed on every existing reset site).
  final int Function() getCursor;
  final void Function(int) setCursor;

  /// Recap — reuses the god's _summary scalar (persisted to Sessions.summary).
  final String Function() getRecap;
  final void Function(String) setRecap;

  /// In-flight flag — reuses the god's _isSummaryGenerating (spinners keep
  /// working; no new flag, no new zeroing sites).
  final bool Function() getIsPassRunning;
  final void Function(bool) setIsPassRunning;

  /// Review-first mode (§4.3): park proposals instead of applying them.
  final bool Function() getReviewFirst;

  /// Identity string for the active backend+model — the key for remembering
  /// "this backend journals over XML" after a failed tools probe.
  final String Function() getBackendIdentity;

  final int Function() getMaxCards;
  final VoidCallback onNotify;
  final Future<void> Function() onSaveChat;

  /// Current story time (TimeService) — the fallback date stamp for new
  /// cards whose cited messages carry no realism_state snapshot
  /// (story-calendar §4; realism-off chats, legacy messages).
  final int Function() getCurrentStoryDay;
  final String Function() getCurrentStoryClockIso;

  JournalMaintenance({
    required this.store,
    required this.review,
    required this.probe,
    required this.fireLLMEval,
    required this.fireToolEval,
    this.getPreferTextEvals = preferTextEvalsOff,
    this.getPassEpoch = passEpochNeverStale,
    required this.stripThinkBlocks,
    required this.getSessionId,
    required this.getActiveCharacter,
    required this.getActiveGroup,
    required this.getGroupCharacters,
    required this.getCharacterIdFromCard,
    required this.getMessages,
    required this.getUserName,
    required this.getCursor,
    required this.setCursor,
    required this.getRecap,
    required this.setRecap,
    required this.getIsPassRunning,
    required this.setIsPassRunning,
    required this.getReviewFirst,
    required this.getBackendIdentity,
    required this.getMaxCards,
    required this.onNotify,
    required this.onSaveChat,
    required this.getCurrentStoryDay,
    required this.getCurrentStoryClockIso,
  });

  /// How many trailing messages to re-read when a force pass finds an empty
  /// window (manual "regenerate" with nothing new since the cursor).
  static const int kForceWindowFallback = 10;

  /// Set when a significant event fires outside message metadata (objective
  /// completion, whose check runs pre-generation). Consumed by ChatService's
  /// _maybeRunJournalPass — which runs post-generation, so the event pass
  /// never competes with the main LLM call for the backend.
  bool eventKickPending = false;

  Future<void> runMaintenancePass({bool force = false}) async {
    final sessionToken = getSessionId();
    if (sessionToken == null) return;
    if (getIsPassRunning()) return;
    // A parked review blocks further automatic passes (they would silently
    // replace what the user hasn't looked at yet); a manual force regen
    // deliberately proposes fresh.
    if (!force && review.hasPendingFor(sessionToken)) return;
    // Consume the event kick only once a pass actually starts — the caller
    // used to clear it BEFORE calling, so a pass blocked by a parked review
    // (or an already-running pass) silently ate the kick.
    eventKickPending = false;
    final epoch = getPassEpoch();
    // Set synchronously before the first await — the only re-entrancy guard
    // for this fire-and-forget per-turn hook.
    setIsPassRunning(true);
    onNotify();

    try {
      final messages = getMessages();
      var start = getCursor().clamp(0, messages.length);
      // THE WINDOW IS CAPPED ON EVERY PASS, not just a virgin one.
      //
      // This cap used to be gated on `start == 0`, so it protected a fresh
      // journal on a long chat and nothing else. That made the pass a one-way
      // trap, because the cursor only advances when a call SUCCEEDS (see the
      // `anySucceeded` guard below): one failed pass — a timeout, a model swap,
      // a backend hiccup — left the cursor behind, the next pass read from that
      // same stale cursor to now, the window grew, and a bigger window fails
      // more easily. Every failure made the next failure more likely, forever.
      //
      // Found in the maintainer's own database: a 9,488-message chat with the
      // cursor stuck at 590, i.e. every pass was trying to send 8,898 messages
      // (~4.37 MILLION tokens) into an 8-16k context, every `journalInterval`
      // messages, burning a model call each time and never once succeeding.
      // A second chat sat at 2,168 messages behind (~720k tokens). Their
      // recaps had been frozen since the day the first call failed, which is
      // what a reasoning model then reports as "the recap contradicts the
      // scene" — the memory system had silently stopped, not drifted.
      //
      // A pass that far behind cannot catch up in one call anyway, and the
      // older material is exactly what RAG and the already-written cards are
      // for. So the tail is bounded unconditionally and the cursor is allowed
      // to jump the gap: falling behind must not be self-perpetuating.
      if (messages.length - start > JournalPhysics.kFirstPassCap) {
        start = messages.length - JournalPhysics.kFirstPassCap;
      }
      if (start >= messages.length) {
        if (!force) return;
        start = (messages.length - kForceWindowFallback).clamp(
          0,
          messages.length,
        );
      }
      final window = messages.sublist(start);
      if (window.isEmpty) return;
      // The cursor target is the SNAPSHOT's end, never the live list's.
      // `messages` IS the god's `_messages`, mutated in place, and the user is
      // free to send while this pass awaits its LLM call (sendMessage guards
      // only on _isGenerating). Reading messages.length after the awaits below
      // would park the cursor past turns this pass never read, and nothing
      // ever rewinds it — those exchanges would be silently un-journaled.
      final cursorTarget = start + window.length;

      // Shared owner loop (pass_support). No guests passed — scene guests
      // never journal (the guest parity guard).
      final owners = resolvePassOwners(
        window: window,
        group: getActiveGroup(),
        members: getGroupCharacters(),
        active: getActiveCharacter(),
        idOf: getCharacterIdFromCard,
      );
      if (owners.isEmpty) return;

      final reviewMode = getReviewFirst();
      final parked = <JournalOwnerProposals>[];
      String? parkedRecap;
      var anySucceeded = false;

      // The recap is asked of the first owner whose call COMES BACK, not
      // rigidly of owner 0. It used to be `i == 0`, and a failed first call
      // then lost the window's recap for good: a later owner succeeding still
      // advanced the cursor past the window, so nothing ever re-read those
      // turns and "Where we are" silently aged behind the story — exactly the
      // frozen-recap failure the window-cap comment above documents, but
      // reached one flaky call at a time. Still exactly ONE owner is asked per
      // pass, so the prompt cost is unchanged.
      var recapOwed = true;

      for (final owner in owners) {
        final ownerId = getCharacterIdFromCard(owner);
        if (ownerId.isEmpty) continue;

        final cards = await store.cardsFor(sessionToken, ownerId);
        final exchange = await _runExchange(
          owner: owner,
          cards: cards,
          window: window,
          windowStart: start,
          includeRecap: recapOwed,
          startedEpoch: epoch,
        );
        if (exchange == null || getPassEpoch() != epoch) {
          debugPrint('[Journal] ✗ ${owner.name}: empty eval response');
          continue;
        }
        final (ops, recapText) = exchange;
        final isRecapOwner = recapOwed;
        recapOwed = false;

        // Emotional physics: cool the existing cards one step first
        // (flashbulb decay — strong feelings barely fade), so adds and
        // revises land at full heat afterwards. Only on a successful eval —
        // a failed pass retries next interval without double-cooling.
        await store.coolCards(sessionToken, ownerId);

        final ownerProposals = JournalOwnerProposals(
          ownerId: ownerId,
          ownerName: owner.name,
          // Clamp add-floods (double the prompt-side ask as headroom) so one
          // verbose model can't churn the card cap in a single evening.
          ops: _resolveOps(
            clampJournalAdds(ops, kJournalMaxNewMemories * 2),
            cards,
            window,
            start,
          ),
        );

        if (reviewMode) {
          if (ownerProposals.ops.isNotEmpty) parked.add(ownerProposals);
          if (isRecapOwner) parkedRecap = recapText;
        } else {
          await review.applyOwnerProposals(sessionToken, ownerProposals);
          if (isRecapOwner &&
              recapText != null &&
              getSessionId() == sessionToken) {
            setRecap(recapText);
          } else if (isRecapOwner &&
              recapText == null &&
              ownerProposals.ops.isNotEmpty) {
            debugPrint(
              '[Journal] ⚠ ${owner.name}: pass produced ops but NO recap — '
              'the model skipped the recap-first instruction (or truncation '
              'was total); "Where we are" stays stale this pass.',
            );
          }
        }
        anySucceeded = true;
        debugPrint(
          '[Journal] ✓ ${owner.name}: ${ownerProposals.ops.length} op(s)'
          '${isRecapOwner && recapText != null ? ' + recap' : ''}'
          '${reviewMode ? ' (for review)' : ''}',
        );
      }

      // Advance the cursor only when at least one owner call succeeded — an
      // all-failed pass auto-retries next interval (old summary semantics).
      // In review mode a non-empty batch parks instead and carries the
      // cursor target with it; an empty "nothing to journal" result settles
      // immediately (there is nothing to review).
      if (anySucceeded && getSessionId() == sessionToken) {
        if (reviewMode && (parked.isNotEmpty || parkedRecap != null)) {
          review.park(
            JournalReviewBatch(
              sessionId: sessionToken,
              cursorTarget: cursorTarget,
              owners: parked,
              recap: parkedRecap,
            ),
          );
        } else {
          setCursor(cursorTarget);
          await onSaveChat();
        }
      }
    } catch (e) {
      debugPrint('[Journal] Maintenance pass failed: $e');
    } finally {
      setIsPassRunning(false);
      onNotify();
    }
  }

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
          // It spoke tools; the calls just validated to nothing — an honest
          // "nothing worth journaling" result, not a transport failure.
          // Do NOT skip. Do NOT brand. Do NOT fall through to XML.
          return (const <JournalOp>[], null);
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
