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
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/chat/journal_physics.dart';
import 'package:front_porch_ai/services/chat/journal_store.dart';
import 'package:front_porch_ai/services/chat/porch_memory_mailbox.dart';
import 'package:front_porch_ai/services/chat/porch_memory_models.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/porch_night_injection.dart';

/// Imports LLMerta porch-memory bundles into The Journal and arms the
/// one-shot force-ack injection for the next reply.
/// Design: docs/design/llmerta-porch-memories.md.
class PorchMemoryImportService {
  final JournalStore journalStore;
  final String? Function() getFpaRootPath;
  final bool Function() isImportEnabled;
  final int Function() getMaxCards;

  /// Library stableGroupIds currently present (for skip-missing).
  final Set<String> Function() libraryStableGroupIds;

  /// Prefs-backed set of fully imported block keys (`gameId\\tcharacterId`).
  final Set<String> Function() getConsumedBlockKeys;
  final Future<void> Function(Set<String> keys) setConsumedBlockKeys;

  /// Optional dir override for tests.
  final List<Directory>? mailboxDirsOverride;

  final PorchNightAckState ackState = PorchNightAckState();

  PorchMemoryImportService({
    required this.journalStore,
    required this.getFpaRootPath,
    required this.isImportEnabled,
    required this.getMaxCards,
    required this.libraryStableGroupIds,
    required this.getConsumedBlockKeys,
    required this.setConsumedBlockKeys,
    this.mailboxDirsOverride,
  });

  static const String kMetaKind = 'llmerta_game';

  /// Plant matching pending cards for this session + arm force-ack.
  /// Never throws — failures log and leave files for retry.
  Future<int> tryImportForSession({
    required String sessionId,
    required String userPersonaId,
    required List<PorchDiaryTarget> targets,
  }) async {
    if (!isImportEnabled()) return 0;
    if (sessionId.isEmpty || userPersonaId.isEmpty || targets.isEmpty) {
      return 0;
    }

    try {
      final bundles = await PorchMemoryMailbox.listPendingBundles(
        fpaRootPath: getFpaRootPath(),
        dirsOverride: mailboxDirsOverride,
      );
      if (bundles.isEmpty) {
        await _armFromPendingCards(sessionId, targets);
        return 0;
      }

      final targetByLibrary = <String, PorchDiaryTarget>{
        for (final t in targets) t.libraryStableGroupId: t,
      };
      final library = libraryStableGroupIds();
      final consumed = Set<String>.from(getConsumedBlockKeys());
      var plantedTotal = 0;

      for (final bundle in bundles) {
        if (bundle.userPersonaId != userPersonaId) continue;

        var bundleDirty = false;
        for (final block in bundle.characters) {
          final blockKey = '${bundle.gameId}\t${block.characterId}';
          if (consumed.contains(blockKey)) continue;

          final target = targetByLibrary[block.characterId];
          if (target == null) {
            // Not the open chat's character — leave for another session,
            // unless the library no longer has them (then mark skipped).
            if (!library.contains(block.characterId)) {
              consumed.add(blockKey);
              bundleDirty = true;
              debugPrint(
                '[PorchMemories] skip missing library char '
                '${block.characterId} game=${bundle.gameId}',
              );
            }
            continue;
          }

          final n = await _plantBlock(
            sessionId: sessionId,
            diaryCharacterId: target.diaryCharacterId,
            bundle: bundle,
            block: block,
          );
          plantedTotal += n;
          // Only mark consumed when every card id for the block is present
          // (planted this pass or already present from a prior partial).
          if (await _blockFullyPlanted(
            sessionId,
            target.diaryCharacterId,
            block,
          )) {
            consumed.add(blockKey);
            bundleDirty = true;
          }
        }

        if (bundleDirty) {
          await setConsumedBlockKeys(consumed);
        }

        // Delete only when every character block is consumed (planted or missing).
        final allDone = bundle.characters.every(
          (b) => consumed.contains('${bundle.gameId}\t${b.characterId}'),
        );
        if (allDone) {
          await PorchMemoryMailbox.deleteBundleFile(bundle);
        }
      }

      await _armFromPendingCards(sessionId, targets);
      if (plantedTotal > 0) {
        debugPrint(
          '[PorchMemories] planted $plantedTotal card(s) session=$sessionId',
        );
      }
      return plantedTotal;
    } catch (e, st) {
      debugPrint('[PorchMemories] import failed: $e\n$st');
      return 0;
    }
  }

  /// Clear force-ack only after the user **continues past** a turn that
  /// already showed the block (next [sendMessage]). Regen of the reacting
  /// AI message must still re-inject until then.
  Future<void> clearAfterAcceptedUserTurn() async {
    if (!ackState.hasShownAny) return;
    final cardIds = ackState.shownCardIds();
    ackState.clearAfterAcceptedUserTurn();
    for (final id in cardIds) {
      try {
        final card = await _findCardById(id);
        if (card == null) continue;
        await journalStore.updateCardMetadata(card, {'porchAckPending': false});
      } catch (e) {
        debugPrint('[PorchMemories] clear ack meta failed $id: $e');
      }
    }
  }

  /// Re-arm from diary if in-memory was lost (restart) but cards still pending.
  Future<void> ensureArmedForDiary({
    required String sessionId,
    required String diaryCharacterId,
  }) async {
    if (ackState.isArmed(diaryCharacterId)) return;
    await _armFromPendingCards(sessionId, [
      PorchDiaryTarget(
        libraryStableGroupId: diaryCharacterId,
        diaryCharacterId: diaryCharacterId,
      ),
    ]);
  }

  String takeInjectionForDiary(String diaryCharacterId) =>
      ackState.takeForPrompt(diaryCharacterId);

  // ── internals ──────────────────────────────────────────────────────────

  Future<int> _plantBlock({
    required String sessionId,
    required String diaryCharacterId,
    required PorchMemoryBundle bundle,
    required PorchCharacterBlock block,
  }) async {
    final existing = await journalStore.cardsFor(sessionId, diaryCharacterId);
    final already = <String>{};
    for (final c in existing) {
      final pid = _porchCardIdOf(c);
      if (pid != null) already.add(pid);
    }

    final sorted = List<PorchMemoryCard>.from(block.cards)
      ..sort((a, b) => b.salience.compareTo(a.salience));

    var planted = 0;
    for (final card in sorted) {
      if (already.contains(card.id)) continue;
      try {
        await journalStore.addCard(
          sessionId: sessionId,
          characterId: diaryCharacterId,
          content: card.content,
          category: card.category,
          emotionLabel: card.emotionLabel,
          emotionIntensity: card.emotionIntensity,
          kind: kMetaKind,
          maxCards: getMaxCards(),
          extraMetadata: {
            'porchCardId': card.id,
            'porchKind': card.kind,
            'gameId': bundle.gameId,
            if (bundle.finishedAt != null)
              'finishedAt': bundle.finishedAt!.toIso8601String(),
            if (bundle.townName != null && bundle.townName!.isNotEmpty)
              'townName': bundle.townName,
            'porchAckPending': true,
          },
        );
        already.add(card.id);
        planted++;
      } catch (e) {
        debugPrint('[PorchMemories] plant card ${card.id} failed: $e');
      }
    }
    return planted;
  }

  Future<void> _armFromPendingCards(
    String sessionId,
    List<PorchDiaryTarget> targets,
  ) async {
    for (final t in targets) {
      final cards = await journalStore.cardsFor(sessionId, t.diaryCharacterId);
      final pending = <JournalMemoryData>[];
      for (final c in cards) {
        if (JournalPhysics.cardKind(c) != kMetaKind) continue;
        if (_porchAckPendingOf(c)) pending.add(c);
      }
      if (pending.isEmpty) continue;

      // Sort by salience stored? We don't store salience — use createdAt order
      // (getJournalCards is oldest first). Prefer stronger intensities first.
      pending.sort((a, b) {
        int rank(String? i) => switch (i) {
          'strong' => 0,
          'moderate' => 1,
          _ => 2,
        };
        return rank(a.emotionIntensity).compareTo(rank(b.emotionIntensity));
      });

      String? town;
      final bullets = <({String emotion, String content})>[];
      for (final c in pending) {
        bullets.add((
          emotion: c.emotionLabel ?? 'reflective',
          content: c.content,
        ));
        town ??= _metaString(c, 'townName');
      }

      final text = PorchNightInjection.build(bullets: bullets, townName: town);
      if (text.isEmpty) continue;
      ackState.arm(
        diaryCharacterId: t.diaryCharacterId,
        injectionText: text,
        journalCardIds: pending.map((c) => c.id).toList(),
      );
    }
  }

  Future<JournalMemoryData?> _findCardById(String id) =>
      journalStore.findCardById(id);

  Future<bool> _blockFullyPlanted(
    String sessionId,
    String diaryCharacterId,
    PorchCharacterBlock block,
  ) async {
    final existing = await journalStore.cardsFor(sessionId, diaryCharacterId);
    final have = <String>{};
    for (final c in existing) {
      final pid = _porchCardIdOf(c);
      if (pid != null) have.add(pid);
    }
    return block.cards.every((c) => have.contains(c.id));
  }

  static String? _porchCardIdOf(JournalMemoryData card) {
    final m = _metaMap(card);
    final v = m['porchCardId'];
    return v is String && v.isNotEmpty ? v : null;
  }

  static bool _porchAckPendingOf(JournalMemoryData card) {
    final m = _metaMap(card);
    final v = m['porchAckPending'];
    if (v is bool) return v;
    if (v is String) return v.toLowerCase() == 'true';
    return false;
  }

  static String? _metaString(JournalMemoryData card, String key) {
    final v = _metaMap(card)[key];
    return v is String && v.isNotEmpty ? v : null;
  }

  static Map<String, dynamic> _metaMap(JournalMemoryData card) {
    final raw = card.metadata;
    if (raw == null || raw.isEmpty) return const {};
    try {
      final d = jsonDecode(raw);
      if (d is Map<String, dynamic>) return d;
      if (d is Map) return Map<String, dynamic>.from(d);
    } catch (_) {}
    return const {};
  }
}
