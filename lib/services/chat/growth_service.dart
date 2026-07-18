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
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'growth_ops.dart';
import 'growth_physics.dart';
import 'growth_prompt.dart';
import 'growth_review.dart';
import 'growth_store.dart';
import 'journal_physics.dart';
import 'pass_support.dart';

/// Growth Rings — the growth pass + effective-personality layering
/// (docs/design/growth-rings.md). Replaces EvolutionService's monolithic
/// personality/scenario rewrites with small receipt-backed ring operations.
///
/// Plain leaf, callback-wired (JournalMaintenance's sibling). Its own small
/// background job with its own cursor (growth_state) — deliberately NOT a
/// rider on the Journal pass, whose per-pass cooling is tuned to
/// journalInterval (§4.2).
///
/// Key invariants:
/// - Strictly per-chat: rings are read and written for the CURRENT session
///   only and die with the chat.
/// - The original card is immutable; rings only ever layer on top.
/// - LLM proposes, code disposes: caps, fade, tiers, and receipts are
///   deterministic (GrowthPhysics) — never model judgment.
/// - 1:1 ↔ group parity by construction: the same owner loop runs in both
///   modes (resolvePassOwners). Scene Guests grow too (1:1) — rings are
///   keyed by their stable charId exactly like members'.
/// - Two transports, one applier: tool calls when the backend accepts them,
///   XML tags everywhere else — both normalize to the same [GrowthOp] list,
///   resolved here into id-addressed proposals and applied through
///   [GrowthReview.applyOwnerProposals] immediately or after user review
///   (review-first, default OFF — autonomous growth by default).
/// - Scenario evolution is retired (§3.2): the Journal recap owns "where we
///   are", so there is no effectiveScenario here — callers use the card's
///   original scenario.
class GrowthService {
  final GrowthStore store;
  final GrowthReview review;

  /// Shared with the Journal pass — one tools probe per backend identity
  /// per run, no matter which pass asks first.
  final ToolTransportProbe probe;

  final Future<String?> Function(String prompt) fireLLMEval;
  final Future<LlmToolResponse?> Function(
    String prompt,
    List<Map<String, dynamic>> tools,
  )
  fireToolEval;
  final String Function(String) stripThinkBlocks;
  final String Function() getBackendIdentity;

  final String? Function() getSessionId;
  final CharacterCard? Function() getActiveCharacter;
  final GroupChat? Function() getActiveGroup;
  final List<CharacterCard> Function() getGroupCharacters;
  final List<CharacterCard> Function() getSceneGuestCards;
  final String Function(CharacterCard) getCharacterIdFromCard;
  final List<ChatMessage> Function() getMessages;
  final String Function() getUserName;

  /// The Journal recap + hot cards ground the pass in distilled state
  /// instead of raw RAG chunks (§4.2).
  final String Function() getRecap;
  final Future<List<JournalMemoryData>> Function(
    String sessionId,
    String characterId,
  )
  getJournalCards;

  final bool Function() getGrowthEnabled;
  final bool Function() getReviewFirst;
  final bool Function() getIsPassRunning;
  final void Function(bool) setIsPassRunning;

  /// Reloads the store's injection cache with the current roster (god
  /// helper — it knows the session, members, and guests).
  final Future<void> Function() refreshCache;
  final VoidCallback onNotify;

  GrowthService({
    required this.store,
    required this.review,
    required this.probe,
    required this.fireLLMEval,
    required this.fireToolEval,
    required this.stripThinkBlocks,
    required this.getBackendIdentity,
    required this.getSessionId,
    required this.getActiveCharacter,
    required this.getActiveGroup,
    required this.getGroupCharacters,
    required this.getSceneGuestCards,
    required this.getCharacterIdFromCard,
    required this.getMessages,
    required this.getUserName,
    required this.getRecap,
    required this.getJournalCards,
    required this.getGrowthEnabled,
    required this.getReviewFirst,
    required this.getIsPassRunning,
    required this.setIsPassRunning,
    required this.refreshCache,
    required this.onNotify,
  });

  /// How many trailing messages a force pass re-reads when nothing is new
  /// since the cursor (manual "Check now" with an empty window).
  static const int kForceWindowFallback = 10;

  /// Set when a significant event fires outside message metadata (objective
  /// completion). Consumed by ChatService's post-generation trigger.
  bool eventKickPending = false;

  // ── Layering (the injection payoff, §4.5) ────────────────────────────

  /// The effective personality for [card]: original description +
  /// personality, plus the compact tier-prefixed ring block (or the legacy
  /// evolved blob while it awaits distillation — no behavior cliff).
  String effectivePersonality(CharacterCard card) {
    final base = [
      if (card.description.isNotEmpty) card.description,
      if (card.personality.isNotEmpty) card.personality,
    ].join('\n');
    if (!getGrowthEnabled()) return base;
    return '$base${growthBlockFor(card)}';
  }

  /// The standalone [Character Growth] block for [card] ('' when there is
  /// nothing to inject). Synchronous — reads the store cache.
  String growthBlockFor(CharacterCard card) {
    final charId = getCharacterIdFromCard(card);
    final session = getSessionId();
    final legacy = store.legacyBlobFor(session, charId);
    return buildGrowthInjection(
      charName: card.name,
      activeRings: store.activeRingsFor(session, charId),
      legacyBlob: legacy == null ? '' : legacy.$1,
    );
  }

  /// Raw growth lines for prompt-budgeted consumers (the realism dossier):
  /// tier-prefixed ring lines, or the legacy personality blob pre-distill.
  String growthLinesFor(CharacterCard card) {
    if (!getGrowthEnabled()) return '';
    final charId = getCharacterIdFromCard(card);
    final session = getSessionId();
    final legacy = store.legacyBlobFor(session, charId);
    if (legacy != null && legacy.$1.isNotEmpty) return legacy.$1;
    return GrowthPhysics.injectionSelection(
      store.activeRingsFor(session, charId),
    ).map((r) => GrowthPhysics.injectionLine(r, charName: card.name)).join('\n');
  }

  // ── The growth pass (§4.2) ───────────────────────────────────────────

  Future<void> runGrowthPass({bool force = false}) async {
    final sessionToken = getSessionId();
    if (sessionToken == null) return;
    if (getIsPassRunning()) return;
    if (!force && review.hasPendingFor(sessionToken)) return;
    // Consume the event kick only once a pass actually starts — the caller
    // used to clear it BEFORE calling, so a pass blocked by a parked review
    // (or an already-running pass) silently ate the kick.
    eventKickPending = false;
    setIsPassRunning(true);
    onNotify();

    try {
      // Fresh cache first: the legacy blobs decide distill mode, and a
      // stale cache would skip the migration.
      await refreshCache();

      final messages = getMessages();
      var start = (await store.cursorFor(sessionToken)).clamp(
        0,
        messages.length,
      );
      if (start == 0 && messages.length > JournalPhysics.kFirstPassCap) {
        // Virgin growth record on a long chat: read the recent tail only
        // (the legacy blob distill carries the older growth forward).
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

      final owners = resolvePassOwners(
        window: window,
        group: getActiveGroup(),
        members: getGroupCharacters(),
        active: getActiveCharacter(),
        idOf: getCharacterIdFromCard,
        guests: getSceneGuestCards(),
      );
      if (owners.isEmpty) return;

      final reviewMode = getReviewFirst();
      final parked = <GrowthOwnerProposals>[];
      var anySucceeded = false;

      for (final owner in owners) {
        final ownerId = getCharacterIdFromCard(owner);
        if (ownerId.isEmpty) continue;

        final allRings = await store.ringsFor(sessionToken, ownerId);
        final active = allRings.where((r) => !r.retired).toList();
        final legacy = store.legacyBlobFor(sessionToken, ownerId);
        final legacyText = legacy == null
            ? ''
            : [
                if (legacy.$1.isNotEmpty) legacy.$1,
                if (legacy.$2.isNotEmpty) legacy.$2,
              ].join('\n\n');

        final journalCards = (await getJournalCards(sessionToken, ownerId))
            .where(JournalPhysics.isHot)
            .toList();

        final ops = await _runExchange(
          owner: owner,
          activeRings: active,
          journalCards: journalCards,
          window: window,
          windowStart: start,
          legacyBlob: legacyText,
        );
        if (ops == null) {
          debugPrint('[Growth] ✗ ${owner.name}: empty eval response');
          continue;
        }

        final distillMode = legacyText.isNotEmpty;
        final resolved = _resolveOps(
          ops,
          active,
          distillMode: distillMode,
          ownerName: owner.name,
        );
        final proposals = GrowthOwnerProposals(
          ownerId: ownerId,
          ownerName: owner.name,
          ops: resolved,
          // Only count the distill done when it actually produced starter
          // rings — a whiffed distill retries on the next pass (the blob
          // keeps injecting meanwhile, so nothing is lost).
          distilled:
              distillMode &&
              resolved.any((op) => op.action == GrowthOpAction.add),
        );

        // Ring physics: rings this pass actively engaged (reinforced or
        // revised) don't fade; everything else non-established steps down.
        // Applied at pass time in both modes (JournalStore.coolCards
        // precedent — a later discarded review doesn't undo physics).
        final engagedIds = proposals.ops
            .where(
              (op) =>
                  op.action == GrowthOpAction.reinforce ||
                  op.action == GrowthOpAction.revise,
            )
            .map((op) => op.ringId)
            .whereType<String>()
            .toSet();
        await store.fadeUnreinforced(sessionToken, ownerId, engagedIds);

        if (reviewMode) {
          if (proposals.ops.isNotEmpty) parked.add(proposals);
        } else {
          await review.applyOwnerProposals(sessionToken, proposals);
        }
        anySucceeded = true;
        debugPrint(
          '[Growth] ✓ ${owner.name}: ${proposals.ops.length} op(s)'
          '${proposals.distilled ? ' (distilled legacy growth)' : ''}'
          '${reviewMode ? ' (for review)' : ''}',
        );
      }

      // Cursor advances only when at least one owner call succeeded — an
      // all-failed pass auto-retries next interval. In review mode a
      // non-empty batch parks and carries the cursor target; an empty
      // "no growth" result settles immediately.
      if (anySucceeded && getSessionId() == sessionToken) {
        if (reviewMode && parked.isNotEmpty) {
          review.park(
            GrowthReviewBatch(
              sessionId: sessionToken,
              cursorTarget: messages.length,
              owners: parked,
            ),
          );
        } else {
          await store.setCursor(sessionToken, messages.length);
        }
        await refreshCache();
      }
    } catch (e) {
      debugPrint('[Growth] Pass failed: $e');
    } finally {
      setIsPassRunning(false);
      onNotify();
    }
  }

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
    if (!probe.isXmlOnly(backend)) {
      final resp = await fireToolEval(prompt(toolsMode: true), kGrowthTools);
      if (resp != null) {
        if (resp.calls.isNotEmpty) probe.markSupported(backend);
        var ops = parseGrowthToolCalls(resp.calls);
        if (ops.isEmpty && resp.text.trim().isNotEmpty) {
          // The model ignored the tools but wrote text — salvage any tags.
          ops = parseGrowthOps(stripThinkBlocks(resp.text));
        }
        if (ops.isNotEmpty) return ops;
        if (resp.calls.isNotEmpty) {
          // It spoke tools, they just validated to nothing — an honest
          // "no growth" result, not a transport failure.
          return const [];
        }
        // Non-null response, no calls, no usable text: the model answered
        // without tools — a capability verdict. (A null resp also lands
        // here: generateWithTools collapses every failure to null, and the
        // probe is deliberately one-shot per backend identity.)
      }
      probe.markXmlOnly(backend);
      debugPrint('[Growth] Tools unavailable on $backend — using XML');
    }

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
    String named(String text) => resolveGrowthMacros(
      text,
      charName: ownerName,
      userName: getUserName(),
    );
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
