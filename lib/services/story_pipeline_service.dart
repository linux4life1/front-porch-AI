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
import 'package:front_porch_ai/services/embedding_service.dart';
import 'package:front_porch_ai/services/story/story.dart';
import 'package:front_porch_ai/services/story_pipeline/story_pipeline.dart';
import 'package:front_porch_ai/services/story_repository.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/memory_service.dart';
import 'package:front_porch_ai/database/database.dart' hide StoryProject;

export 'package:front_porch_ai/services/story_pipeline/story_lanes.dart';
export 'package:front_porch_ai/services/story_pipeline/story_studio_bible.dart'
    show StoryPipelineStudioBible;

/// Orchestrates the multi-agent AI novel-writing pipeline for Porch Stories.
///
/// Each stage constructs a specialized prompt, calls the LLM via [LLMService],
/// parses the structured JSON response, and updates the [StoryProject] state.
/// Supports three prompt complexity tiers for different model capabilities.
///
/// The stages live in `story_pipeline/` as collaborators sharing one
/// [StoryPipelineContext]; this class keeps the public API as forwarders so
/// story pages, the web facade and test doubles see one surface.
class StoryPipelineService extends ChangeNotifier {
  final MemoryService
  _memoryService; // ignore: unused_field - Reserved for future story RAG / memory injection

  /// Run log and Director undo snapshots (side files, not the project blob).
  final StoryStudioStore store;
  late final StoryPipelineContext _ctx;
  late final StoryPipelineRunner _run;

  /// True for the whole of an outermost operation, including the gaps between
  /// its stages (each stage still clears its own busy flag in `finally`).
  bool get isRunning => _ctx.isRunning;
  bool get stopRequested => _ctx.stopRequested;
  String get currentStep => _ctx.currentStep;
  String get statusMessage => _ctx.statusMessage;
  String get streamingText => _ctx.streamingText;
  int get tokenCount => _ctx.tokenCount;

  StoryPipelineService(
    StoryRepository repository,
    LLMService llmService,
    this._memoryService,
    AppDatabase db, {
    StoryStudioStore? store,
    StoryLanes? lanes,
    EmbeddingService? embeddings,
  }) : store = store ?? StoryStudioStore() {
    _ctx = StoryPipelineContext(
      repository: repository,
      llmService: llmService,
      db: db,
      store: this.store,
      lanes: lanes,
      loreIndex: StoryLoreIndex(embeddings),
      notify: notifyListeners,
    );
    _run = StoryPipelineRunner(_ctx);
    repository.onDelete = this.store.deleteProject;
  }

  /// Ask the running operation to stop at the next safe point. Everything
  /// already written stays saved.
  void requestStop() => _run.requestStop();

  /// Re-point at a reopened database (backup restore, storage move, stable-DB
  /// import) — same contract as StoryRepository.updateDatabase. Without this
  /// the pipeline kept the CLOSED startup handle until an unrelated provider
  /// notification happened to rebuild it, and Porch Stories looked empty (or
  /// threw) until then.
  void updateDatabase(AppDatabase db) {
    _ctx.db = db;
  }

  /// Public method for the UI to preview what chat history will be imported.
  /// Always pulls full messages from the DB (not RAG embeddings which are windowed summaries).
  Future<List<String>> getChatPreviewMessages(StoryProject project) =>
      _run.history.previewMessages(project);

  /// Every 1:1 chat a story can start from, newest first. Chats where the
  /// user never wrote anything are left out: a greeting alone is no story.
  Future<List<StoryChatSourceRow>> chatSources() => _run.history.chatSources();

  /// Called when a run ends: put the chat model back.
  Future<void> restoreLaneHosts() => _run.llm.restoreLaneHosts();

  // ── Pipeline operations (guarded; see StoryPipelineRunner) ──────────

  /// Stage 0: chat history → event timeline (both engines).
  Future<void> runChatDistiller(StoryProject project) =>
      _run.runChatDistiller(project);

  /// Concept → story bible.
  Future<void> runStoryArchitect(StoryProject project) =>
      _run.runStoryArchitect(project);

  /// Bible → acts (and, in Studio, the eight sequences).
  Future<void> runActStructurer(StoryProject project) =>
      _run.runActStructurer(project);

  /// Act → scenes. In Studio every sequence of the act that has no scenes
  /// yet is planned; sequences already planned are left alone.
  Future<void> runSceneWeaver(StoryProject project, int actIndex) =>
      _run.runSceneWeaver(project, actIndex);

  /// Scene → beats.
  Future<void> runBeatDirector(
    StoryProject project,
    int actIndex,
    int sceneIndex,
  ) => _run.runBeatDirector(project, actIndex, sceneIndex);

  /// Write one beat (Quick: draft + edit; Studio: write + continuity check).
  Future<void> runDraftAndEdit(
    StoryProject project,
    int actIndex,
    int sceneIndex,
    int beatIndex,
  ) => _run.runDraftAndEdit(project, actIndex, sceneIndex, beatIndex);

  /// Rewrite a beat that already has prose, optionally with an instruction.
  Future<void> rewriteBeat(
    StoryProject project,
    int actIndex,
    int sceneIndex,
    int beatIndex, {
    String directive = '',
  }) => _run.rewriteBeat(
    project,
    actIndex,
    sceneIndex,
    beatIndex,
    directive: directive,
  );

  /// Write every unwritten beat of a scene, then archive it.
  Future<void> autoWriteScene(
    StoryProject project,
    int actIndex,
    int sceneIndex,
  ) => _run.autoWriteScene(project, actIndex, sceneIndex);

  /// Everything for one act: scenes, beats and prose.
  Future<void> generateFullAct(StoryProject project, int actIndex) =>
      _run.generateFullAct(project, actIndex);

  /// Throw a scene's prose away and write it again.
  Future<void> regenerateSceneProse(
    StoryProject project,
    int actIndex,
    int sceneIndex,
  ) => _run.regenerateSceneProse(project, actIndex, sceneIndex);

  /// Concept to finished prose without stopping.
  Future<void> runAutopilot(StoryProject project) => _run.runAutopilot(project);

  /// "Continue writing": one tap, one scene. Returns false when the story is
  /// finished.
  Future<bool> writeNextScene(StoryProject project) =>
      _run.writeNextScene(project);

  /// Rewrite the arc and nothing else. The world, cast and interviews stay.
  Future<void> runStoryArc(StoryProject project) => _run.runStoryArc(project);

  /// Interview (or re-interview) one cast member on request.
  Future<void> runCharacterInterview(StoryProject project, String name) =>
      _run.runCharacterInterview(project, name);

  /// Plan (or re-plan) the scenes of one sequence on request.
  Future<void> planSequenceScenes(StoryProject project, int number) =>
      _run.planSequenceScenes(project, number);

  /// Stage 8: Beat Validator — check continuity.
  Future<bool> runBeatValidator(
    StoryProject project,
    int actIndex,
    int sceneIndex,
    int beatIndex,
  ) => _run.quickProse.runBeatValidator(
    project,
    actIndex,
    sceneIndex,
    beatIndex,
  );

  /// Put a beat back the way it was before the continuity fix.
  Future<void> undoContinuityFix(
    StoryProject project,
    int act,
    int index,
    int beat,
  ) => _run.studioProse.undoContinuityFix(project, act, index, beat);

  // ── Director ────────────────────────────────────────────────────────

  /// Propose a plan for [directive]. With [refinement], the current plan is
  /// revised instead of replaced. Nothing changes until [applyDirectorPlan].
  Future<void> runDirectorPlan(
    StoryProject project,
    String directive, {
    required bool protectWrittenProse,
    String refinement = '',
  }) => _run.runDirectorPlan(
    project,
    directive,
    protectWrittenProse: protectWrittenProse,
    refinement: refinement,
  );

  /// Apply the ticked actions of the current plan, then re-archive every
  /// scene that changed.
  Future<void> applyDirectorPlan(StoryProject project) =>
      _run.applyDirectorPlan(project);

  /// Re-evaluate the locks after the user flips "Protect written prose".
  Future<void> setDirectorProtection(StoryProject project, bool protect) =>
      _run.director.setProtection(project, protect);

  Future<void> setDirectorActionEnabled(
    StoryProject project,
    int index,
    bool enabled,
  ) => _run.director.setActionEnabled(project, index, enabled);

  Future<void> discardDirectorPlan(StoryProject project) =>
      _run.director.discard(project);

  /// Put the story back as it was before the last applied plan.
  Future<bool> undoDirectorPlan(StoryProject project) =>
      _run.director.undo(project);

  // ── Lore ────────────────────────────────────────────────────────────

  /// Add an uploaded document to the story's lore, cut into searchable
  /// entries. Re-uploading a file of the same name replaces it.
  Future<int> addLoreDocument(StoryProject project, String name, String text) =>
      _run.memory.addLoreDocument(project, name, text);

  /// What the writer would be shown for [query] at scene ([act], [index]).
  Future<List<LoreHit>> searchLore(
    StoryProject project,
    String query, {
    int? act,
    int? index,
  }) => _run.memory.searchLore(project, query, act: act, index: index);

  /// Whether lore search is using the embedding model (true) or plain word
  /// overlap (false).
  bool get loreSearchIsSemantic => _run.memory.loreSearchIsSemantic;

  // ── Forwarders to lib/services/story/ leaves ────────────────────────
  // Kept as class members so external call sites (story pages, the web
  // facade, and the story_pipeline_leaves_test.dart provability net) need
  // zero changes. See the split map (H3) — generateArchetypes/exportAsText/
  // exportAsMarkdown are map-prescribed; parseJson is an ADDITIONAL
  // forwarder the map didn't call for (it assumed zero external callers,
  // which was true against the map's base commit but no longer holds now
  // that story_pipeline_leaves_test.dart — added after the map was written
  // — calls `StoryPipelineService.parseJson` directly as its provability
  // net for the JSON-repair machinery). cleanJson keeps NO forwarder: it
  // still has zero external callers, including in that new test file.

  /// Generate random story concept archetypes for the user to choose from.
  static List<Map<String, String>> generateArchetypes({int count = 10}) =>
      StoryArchetypes.generate(count: count);

  /// Parse JSON with fallback for malformed/truncated responses.
  static Map<String, dynamic>? parseJson(String raw) =>
      StoryJson.parseJson(raw);

  /// Export the full story as plain text.
  String exportAsText(StoryProject project) => StoryContext.exportText(project);

  /// Export the full story as Markdown.
  String exportAsMarkdown(StoryProject project) =>
      StoryContext.exportMarkdown(project);
}
