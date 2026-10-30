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

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/chat_tools/chat_tools.dart';
import 'package:front_porch_ai/services/web/facade/journal_web_surface.dart';
import 'package:front_porch_ai/services/web/streaming/stream_hub.dart';

/// Thin adapter for the chat *tools* sidebar — the memory/summary/chaos/NSFW/
/// scene-time/objective sections the desktop shows beside a chat. Every read is
/// a pure getter and every mutation delegates to the existing [ChatService]/
/// [StorageService] methods the desktop sidebar calls, so 1:1↔group parity and
/// the simulation behavior are inherited (never reimplemented here).
class ChatToolsFacade {
  ChatToolsFacade(
    ChatService chat,
    StorageService storage,
    StreamHub? hub, {
    StoryRepository? storyRepo,
    UserPersonaService? personas,
    ChatWorldRead? chatWorld,
  }) : _ctx = ChatToolsContext(chat, storage, hub) {
    _scene = ChatToolsScene(
      _ctx,
      storyRepo: storyRepo,
      personas: personas,
      chatWorld: chatWorld,
    );
    _snapshot = ChatToolsSnapshot(_ctx, _scene);
    _memory = ChatToolsMemory(_ctx);
    _switches = ChatToolsSwitches(_ctx);
    _objectives = ChatToolsObjectives(_ctx);
    _pockets = ChatToolsPockets(_ctx);
  }

  final ChatToolsContext _ctx;
  late final ChatToolsScene _scene;
  late final ChatToolsSnapshot _snapshot;
  late final ChatToolsMemory _memory;
  late final ChatToolsSwitches _switches;
  late final ChatToolsObjectives _objectives;
  late final ChatToolsPockets _pockets;

  /// Full tools snapshot mirroring the desktop sidebar (focus-scoped).
  Map<String, dynamic> state({String? participantId}) =>
      _snapshot.build(participantId: participantId);

  /// Apply any subset of the global memory/summary numeric+text settings. Keys
  /// mirror the [state] `memory`/`summary` blocks; absent keys are unchanged.
  Future<void> applySettings(Map<String, dynamic> f) async {
    Future<void> ifBool(String k, Future<void> Function(bool) set) async {
      if (f[k] is bool) await set(f[k] as bool);
    }

    Future<void> ifInt(String k, Future<void> Function(int) set) async {
      final v = f[k];
      if (v is int) await set(v);
    }

    final mem = _ctx.storage.memorySettings;
    await ifBool('ragEnabled', mem.setRagEnabled);
    await ifInt('ragRetrievalCount', mem.setRagRetrievalCount);
    await ifInt('ragWindowSize', mem.setRagWindowSize);
    await ifBool('journalEnabled', mem.setJournalEnabled);
    await ifInt('journalInterval', mem.setJournalInterval);
    await ifInt('journalMaxCards', mem.setJournalMaxCards);
    await ifBool('journalReviewFirst', mem.setJournalReviewFirst);
    await ifBool(
      'importLlmertaPorchMemories',
      mem.setImportLlmertaPorchMemories,
    );
    await ifBool('growthEnabled', mem.setCharacterEvolutionEnabled);
    await ifInt('growthInterval', mem.setGrowthInterval);
    await ifBool('growthReviewFirst', mem.setGrowthReviewFirst);
    _ctx.notify();
  }

  /// Same switch the desktop Recap panel and injection use.
  bool get journalEnabled => _ctx.storage.memorySettings.journalEnabled;

  /// Web Journal diary (audit P2.12) — Growth twin for cards + review-first.
  JournalWebSurface get journalWeb => JournalWebSurface(
    chat: _ctx.chat,
    storage: _ctx.storage,
    notify: _ctx.notify,
    resolveOwner: _ctx.growthOwner,
  );

  // ── Memory: Growth Rings, recap, timeline, promises ─────────────────────
  Map<String, dynamic> growth(String? participantId) =>
      _memory.growth(participantId);

  Future<void> growthAction(
    String? participantId,
    String action,
    Map<String, dynamic> body,
  ) => _memory.growthAction(participantId, action, body);

  Map<String, dynamic> growthReviewBatch() => _memory.growthReviewBatch();

  Future<void> settleGrowthReview({
    required bool apply,
    List<String> rejected = const [],
  }) => _memory.settleGrowthReview(apply: apply, rejected: rejected);

  Future<void> regenerateSummary() => _memory.regenerateSummary();

  void setSummaryPaused(bool v) => _memory.setSummaryPaused(v);

  void setSummaryText(String text) => _memory.setSummaryText(text);

  Future<Map<String, dynamic>> timeline(String? ownerId) =>
      _memory.timeline(ownerId);

  Future<Map<String, dynamic>> promises(String? ownerId) =>
      _memory.promises(ownerId);

  Future<bool> resolvePromise({
    required String ownerId,
    required String cardId,
    required bool kept,
  }) => _memory.resolvePromise(ownerId: ownerId, cardId: cardId, kept: kept);

  // ── Scene: story clock, calendar, story-from-chat ───────────────────────
  Future<void> setStoryClock(DateTime clock) => _scene.setStoryClock(clock);

  Future<void> setStoryStartDate(DateTime date) =>
      _scene.setStoryStartDate(date);

  Future<Map<String, dynamic>> calendar(String? ownerId) =>
      _scene.calendar(ownerId);

  Future<void> nudgeTime(int delta) => _scene.nudgeTime(delta);

  Future<Map<String, dynamic>> toStory({
    required bool faithful,
    required String length,
    required String pov,
    String? lead,
  }) =>
      _scene.toStory(faithful: faithful, length: length, pov: pov, lead: lead);

  // ── Switches ────────────────────────────────────────────────────────────
  Future<void> setRealismEnabled(bool v) => _switches.setRealismEnabled(v);

  Future<void> setNeedsEnabled(bool v) => _switches.setNeedsEnabled(v);

  Future<void> setOneShotEval(bool v) => _switches.setOneShotEval(v);

  Future<void> setOneShotMode(OneShotMode v) => _switches.setOneShotMode(v);

  Future<void> setChaosEnabled(bool v) => _switches.setChaosEnabled(v);

  Future<void> setChaosNsfw(bool v) => _switches.setChaosNsfw(v);

  Future<void> setAfterglow(bool v) => _switches.setAfterglow(v);
  Future<void> setPassageOfTime(bool v) => _switches.setPassageOfTime(v);

  Future<void> setDirectorMode(bool v) => _switches.setDirectorMode(v);

  Future<void> setWikiBaseUrl(String url) => _switches.setWikiBaseUrl(url);

  // ── Objectives ──────────────────────────────────────────────────────────
  Future<void> setObjective(
    String goal, {
    bool isPrimary = true,
    String? participantId,
  }) => _objectives.setObjective(
    goal,
    isPrimary: isPrimary,
    participantId: participantId,
  );

  Future<bool> generateTasks(
    String id, {
    int taskCount = 5,
    bool nsfw = false,
  }) => _objectives.generateTasks(id, taskCount: taskCount, nsfw: nsfw);

  Future<bool> addTask(String id, String description) =>
      _objectives.addTask(id, description);

  Future<bool> toggleTask(String id, int taskIndex) =>
      _objectives.toggleTask(id, taskIndex);

  Future<bool> updateTask(String id, int taskIndex, String description) =>
      _objectives.updateTask(id, taskIndex, description);

  Future<bool> removeTask(String id, int taskIndex) =>
      _objectives.removeTask(id, taskIndex);

  Future<bool> setCheckFrequency(String id, int frequency) =>
      _objectives.setCheckFrequency(id, frequency);

  Future<bool> clearObjective(String id) => _objectives.clearObjective(id);

  Future<bool> promoteObjective(String id) => _objectives.promoteObjective(id);

  void checkCompletion() => _objectives.checkCompletion();

  void abandonToday() => _objectives.abandonToday();

  // ── Pockets & Wardrobe ──────────────────────────────────────────────────
  Future<void> removePocketItem({
    String? participantId,
    required String section,
    required int index,
  }) => _pockets.removePocketItem(
    participantId: participantId,
    section: section,
    index: index,
  );

  Future<void> addPocketItem({
    String? participantId,
    required String section,
    required String name,
    bool gift = false,
    bool correction = false,
  }) => _pockets.addPocketItem(
    participantId: participantId,
    section: section,
    name: name,
    gift: gift,
    correction: correction,
  );

  Future<Map<String, dynamic>> belongings(String? ownerId) =>
      _pockets.belongings(ownerId);
}
