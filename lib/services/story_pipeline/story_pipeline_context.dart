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
import 'package:front_porch_ai/database/database.dart' hide StoryProject;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/story/story.dart';
import 'package:front_porch_ai/services/story_pipeline/story_pipeline.dart';
import 'package:front_porch_ai/services/story_repository.dart';

/// What every pipeline stage shares: the services it works through and the
/// run state the story pages watch. The owning [ChangeNotifier] hands in its
/// `notifyListeners` as [notify].
class StoryPipelineContext {
  StoryPipelineContext({
    required this.repository,
    required this.llmService,
    required this.db,
    required this.store,
    required this.lanes,
    required this.loreIndex,
    required VoidCallback notify,
    StoryWorldBrief Function(String worldId)? worldBrief,
  }) : _notify = notify,
       _worldBrief = worldBrief ?? _noWorld;

  static StoryWorldBrief _noWorld(String _) =>
      StoryWorldBrief(chain: const [], places: const []);

  final StoryWorldBrief Function(String worldId) _worldBrief;

  /// The Living World a story is set in, read live from the library; an
  /// empty brief when the story has none or its world was deleted
  /// (docs/design/stories-in-worlds.md §3.1).
  StoryWorldBrief worldFor(StoryProject project) =>
      briefFor(project.worldId ?? '');

  /// The brief for a place id straight from the library; empty for ''.
  StoryWorldBrief briefFor(String worldId) =>
      worldId.isEmpty ? _noWorld('') : _worldBrief(worldId);

  final StoryRepository repository;
  final LLMService llmService;

  /// Re-pointed by a database reopen (see `updateDatabase`).
  AppDatabase db;

  /// Run log and Director undo snapshots (side files, not the project blob).
  final StoryStudioStore store;
  final StoryLanes? lanes;
  final StoryLoreIndex loreIndex;
  final VoidCallback _notify;

  /// The current stage's own busy flag; each stage clears it in `finally`.
  bool running = false;
  String currentStep = '';
  String statusMessage = '';
  String streamingText = '';
  int tokenCount = 0;

  /// Nesting depth of public operations; see `StoryPipelineRunner.guard`.
  int depth = 0;
  bool stopRequested = false;

  /// True for the whole of an outermost operation, including the gaps between
  /// its stages (each stage still clears [running] in its own `finally`).
  bool get isRunning => running || depth > 0;

  void setStatus(String step, String message) {
    currentStep = step;
    statusMessage = message;
    notify();
  }

  void notify() => _notify();
}
