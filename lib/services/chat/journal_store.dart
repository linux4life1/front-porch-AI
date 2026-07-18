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
import 'dart:typed_data';

import 'package:drift/drift.dart';

import 'package:front_porch_ai/database/database.dart';
import 'journal_physics.dart';

/// The Journal — card persistence (docs/design/journal-memory.md §5) plus
/// the DB half of the emotional physics (§4.4): per-pass cooling with
/// flashbulb resistance, re-warming on retrieval, trim-by-coldest, and card
/// embeddings for cold-card semantic recall.
///
/// Plain leaf owning the DB half of the shared ops applier. Cards are
/// strictly scoped per (sessionId, characterId) — no read or write ever
/// crosses chats; deleting a chat cascades in [AppDatabase.deleteSessionById].
///
/// Holds the database via a closure (not a constructor value) because
/// ChatService receives its AppDatabase post-construction via setDatabase and
/// the leaves are `late final` fields. Direct DB access mirrors MemoryService/
/// CharacterRepository (callbacks are reserved for mutable god *state*).
///
/// No bumpSyncVersion on writes, matching the MessageEmbeddings precedent
/// (derived, session-local data).
class JournalStore {
  final AppDatabase? Function() getDb;

  /// Optional embedder (wired to MemoryService.embedText). Null result or a
  /// null callback simply means no semantic recall — the Journal's hot/pinned
  /// path never needs embeddings (design invariant: no-RAG floor).
  final Future<List<double>?> Function(String text)? embedText;

  JournalStore({required this.getDb, this.embedText});

  /// All cards for one diary owner in one chat — pinned first, then oldest
  /// first. This exact order is what the maintenance prompt numbers its
  /// 1-based handles by and what the injection builder renders, so the three
  /// surfaces always agree.
  Future<List<JournalMemoryData>> cardsFor(
    String sessionId,
    String characterId,
  ) async {
    final db = getDb();
    if (db == null) return const [];
    return db.getJournalCards(sessionId, characterId);
  }

  /// Insert a new memory. Enforces the per-owner cap by retiring the coldest
  /// unpinned card (lowest heat; oldest wins the tie — design §4.4). The raw
  /// transcript stays in RAG, so a trimmed card is a demotion, not a loss.
  Future<void> addCard({
    required String sessionId,
    required String characterId,
    required String content,
    required String category,
    String? emotionLabel,
    String? emotionIntensity,
    List<int> sourcePositions = const [],
    required int maxCards,
  }) async {
    final db = getDb();
    if (db == null) return;
    final existing = await db.getJournalCards(sessionId, characterId);
    if (existing.length >= maxCards) {
      // getJournalCards orders pinned DESC then createdAt ASC, so scanning in
      // order and keeping strict `<` makes the oldest lowest-heat unpinned
      // card the victim.
      JournalMemoryData? coldest;
      for (final card in existing) {
        if (card.pinned) continue;
        if (coldest == null || card.heat < coldest.heat) coldest = card;
      }
      if (coldest != null) await db.deleteJournalCard(coldest.id);
    }
    await db.insertJournalCard(
      // id deliberately absent — filled by insertJournalCard (UUID).
      JournalMemoriesCompanion(
        sessionId: Value(sessionId),
        characterId: Value(characterId),
        content: Value(content),
        category: Value(category),
        emotionLabel: Value(emotionLabel),
        emotionIntensity: Value(emotionIntensity),
        sourceMessageIds: Value(
          sourcePositions.isEmpty ? null : jsonEncode(sourcePositions),
        ),
      ),
    );
  }

  /// Edit a card in place. On the first feeling change the original emotion
  /// is preserved in originalEmotionLabel ("feelings that heal" — the diary
  /// can show "once felt sad, now feels proud"). A revision re-warms the card
  /// to full heat (the memory was just actively reworked) and, when the text
  /// changed, drops the now-stale embedding so [embedMissing] re-embeds it.
  Future<void> reviseCard(
    JournalMemoryData card, {
    String? content,
    String? feeling,
  }) async {
    final db = getDb();
    if (db == null) return;
    final contentChanged = content != null && content.isNotEmpty;
    final feelingChanged =
        feeling != null && feeling.isNotEmpty && feeling != card.emotionLabel;
    await db.updateJournalCard(
      card.id,
      JournalMemoriesCompanion(
        content: contentChanged ? Value(content) : const Value.absent(),
        emotionLabel: feelingChanged ? Value(feeling) : const Value.absent(),
        originalEmotionLabel:
            feelingChanged && card.originalEmotionLabel == null
            ? Value(card.emotionLabel)
            : const Value.absent(),
        heat: const Value(JournalPhysics.kMaxHeat),
        embedding: contentChanged ? const Value(null) : const Value.absent(),
        dimensions: contentChanged ? const Value(0) : const Value.absent(),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> retireCard(String id) async {
    await getDb()?.deleteJournalCard(id);
  }

  Future<void> setPinned(String id, bool pinned) async {
    final db = getDb();
    if (db == null) return;
    await db.updateJournalCard(
      id,
      JournalMemoriesCompanion(
        pinned: Value(pinned),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Cool every unpinned card one maintenance-pass step (flashbulb decay —
  /// strong feelings barely fade, mild ones fade normally; JournalPhysics
  /// owns the numbers). Called once per diary owner per successful pass.
  Future<void> coolCards(String sessionId, String characterId) async {
    final db = getDb();
    if (db == null) return;
    for (final card in await db.getJournalCards(sessionId, characterId)) {
      final cooled = JournalPhysics.cooledHeat(card);
      if (cooled == card.heat) continue; // pinned or already at 0
      await db.updateJournalCard(
        card.id,
        JournalMemoriesCompanion(heat: Value(cooled)),
      );
    }
  }

  /// Semantic retrieval resurfaced a cold card: warm it back into the hot
  /// set and record the access (design §4.4 heat lifecycle).
  Future<void> rewarmCard(JournalMemoryData card) async {
    final db = getDb();
    if (db == null) return;
    await db.updateJournalCard(
      card.id,
      JournalMemoriesCompanion(
        heat: Value(
          card.heat < JournalPhysics.kRewarmHeat
              ? JournalPhysics.kRewarmHeat
              : card.heat,
        ),
        accessCount: Value(card.accessCount + 1),
        lastAccessedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Embed every card that has no vector yet (new cards, revised cards, and
  /// cards written while the sidecar was down — self-healing). One sweep per
  /// maintenance pass; silently a no-op without an embedder (no-RAG floor).
  Future<void> embedMissing(String sessionId, String characterId) async {
    final embed = embedText;
    final db = getDb();
    if (embed == null || db == null) return;
    for (final card in await db.getJournalCards(sessionId, characterId)) {
      if (card.embedding != null) continue;
      final vector = await embed(card.content);
      if (vector == null || vector.isEmpty) return; // embedder unavailable
      final bytes = Float32List.fromList(
        vector.map((e) => e.toDouble()).toList(),
      );
      await db.updateJournalCard(
        card.id,
        JournalMemoriesCompanion(
          embedding: Value(Uint8List.view(bytes.buffer)),
          dimensions: Value(vector.length),
        ),
      );
    }
  }
}
