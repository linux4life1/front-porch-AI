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

import 'settings_base.dart';

/// RAG / memory, The Journal, and character evolution intervals and toggles.
/// (The old summary_* / auto_persona_* keys were replaced by the Journal —
/// docs/design/journal-memory.md; stale prefs entries are harmless.)
class MemorySettings with SettingsBase {
  // RAG. Retrieval default is deliberately small: each retrieved window is
  // ~5 messages of verbatim old transcript, and injecting many of them makes
  // models replay old events as if current (the "parroting" reports). Users
  // who want more can raise the "Memories per turn" slider (0 = All).
  bool _ragEnabled = false;
  int _ragRetrievalCount = 4;
  int _ragWindowSize = 5;
  String _ragEmbeddingSource = 'auto';
  String _ragEmbeddingModel = 'text-embedding-3-small';

  // The Journal (docs/design/journal-memory.md §6) — per-chat, per-character
  // memory cards + "Where we are" recap. Enabled by default (flagship;
  // works out of the box with no embedding setup).
  bool _journalEnabled = true;
  int _journalInterval = 10;
  int _journalMaxCards = 200;
  bool _journalReviewFirst = false; // §4.3 review-first mode (phase 4)

  // Character Growth (Growth Rings — docs/design/growth-rings.md §6).
  // The enable key is the old character_evolution_enabled pref so existing
  // users keep their on/off choice; the interval is a NEW key because rings
  // check far more often than the old whole-personality rewrites did (an
  // inherited 10-50 value would be wrong for rings).
  bool _characterEvolutionEnabled = false;
  int _growthInterval = 5;
  bool _growthReviewFirst = false; // default OFF — autonomous growth

  bool get ragEnabled => _ragEnabled;
  int get ragRetrievalCount => _ragRetrievalCount;
  int get ragWindowSize => _ragWindowSize;
  String get ragEmbeddingSource => _ragEmbeddingSource;
  String get ragEmbeddingModel => _ragEmbeddingModel;

  bool get journalEnabled => _journalEnabled;
  int get journalInterval => _journalInterval;
  int get journalMaxCards => _journalMaxCards;
  bool get journalReviewFirst => _journalReviewFirst;

  bool get characterEvolutionEnabled => _characterEvolutionEnabled;
  int get growthInterval => _growthInterval;
  bool get growthReviewFirst => _growthReviewFirst;

  void load() {
    _ragEnabled = prefs?.getBool(k('rag_enabled')) ?? false;
    _ragRetrievalCount = prefs?.getInt(k('rag_retrieval_count')) ?? 4;
    _ragWindowSize = prefs?.getInt(k('rag_window_size')) ?? 5;
    _ragEmbeddingSource = prefs?.getString(k('rag_embedding_source')) ?? 'auto';
    _ragEmbeddingModel =
        prefs?.getString(k('rag_embedding_model')) ?? 'text-embedding-3-small';

    _journalEnabled = prefs?.getBool(k('journal_enabled')) ?? true;
    _journalInterval = prefs?.getInt(k('journal_interval')) ?? 10;
    _journalMaxCards = prefs?.getInt(k('journal_max_cards')) ?? 200;
    _journalReviewFirst = prefs?.getBool(k('journal_review_first')) ?? false;

    _characterEvolutionEnabled =
        prefs?.getBool(k('character_evolution_enabled')) ?? false;
    _growthInterval = prefs?.getInt(k('growth_interval')) ?? 5;
    _growthReviewFirst = prefs?.getBool(k('growth_review_first')) ?? false;
  }

  Future<void> setRagEnabled(bool value) async {
    _ragEnabled = value;
    await prefs?.setBool(k('rag_enabled'), value);
    notify();
  }

  Future<void> setRagRetrievalCount(int value) async {
    _ragRetrievalCount = value.clamp(0, 50);
    await prefs?.setInt(k('rag_retrieval_count'), _ragRetrievalCount);
    notify();
  }

  Future<void> setRagWindowSize(int value) async {
    _ragWindowSize = value.clamp(2, 15);
    await prefs?.setInt(k('rag_window_size'), _ragWindowSize);
    notify();
  }

  Future<void> setRagEmbeddingSource(String value) async {
    _ragEmbeddingSource = value;
    await prefs?.setString(k('rag_embedding_source'), value);
    notify();
  }

  Future<void> setRagEmbeddingModel(String value) async {
    _ragEmbeddingModel = value;
    await prefs?.setString(k('rag_embedding_model'), value);
    notify();
  }

  Future<void> setJournalEnabled(bool value) async {
    _journalEnabled = value;
    await prefs?.setBool(k('journal_enabled'), value);
    notify();
  }

  Future<void> setJournalInterval(int value) async {
    _journalInterval = value.clamp(3, 50);
    await prefs?.setInt(k('journal_interval'), _journalInterval);
    notify();
  }

  Future<void> setJournalMaxCards(int value) async {
    _journalMaxCards = value.clamp(50, 1000);
    await prefs?.setInt(k('journal_max_cards'), _journalMaxCards);
    notify();
  }

  Future<void> setJournalReviewFirst(bool value) async {
    _journalReviewFirst = value;
    await prefs?.setBool(k('journal_review_first'), value);
    notify();
  }

  Future<void> setCharacterEvolutionEnabled(bool value) async {
    _characterEvolutionEnabled = value;
    await prefs?.setBool(k('character_evolution_enabled'), value);
    notify();
  }

  Future<void> setGrowthInterval(int value) async {
    _growthInterval = value.clamp(2, 20);
    await prefs?.setInt(k('growth_interval'), _growthInterval);
    notify();
  }

  Future<void> setGrowthReviewFirst(bool value) async {
    _growthReviewFirst = value;
    await prefs?.setBool(k('growth_review_first'), value);
    notify();
  }
}
