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

import 'dart:io';

import 'package:path/path.dart' as path;

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/embedding_service.dart';
import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/services/memory_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/story/story.dart';
import 'package:front_porch_ai/services/story_pipeline_service.dart';
import 'package:front_porch_ai/services/story_repository.dart';

/// The pipeline with every collaborator wired: the worker lane for Studio
/// review jobs, the per-story side files under the storage root, and the
/// embedding model for lore search. Kept out of `main.providers.dart`, which
/// is at the file-size line.
StoryPipelineService buildStoryPipelineService({
  required StoryRepository repository,
  required LLMProvider llm,
  required StorageService storage,
  required EmbeddingService embeddings,
  required AppDatabase db,
}) {
  return StoryPipelineService(
    repository,
    llm.activeService,
    MemoryService(embeddings, storage, db),
    db,
    store: StoryStudioStore(
      directory: () {
        final root = storage.rootPath;
        return root == null ? null : Directory(path.join(root, 'story_studio'));
      },
    ),
    lanes: StoryLanes(
      worker: () => llm.workerService,
      hold: llm.withWorkerLane,
    ),
    embeddings: embeddings,
  );
}
