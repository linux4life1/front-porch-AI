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

// Barrel for the story-pipeline domain leaves (self-extending barrel rule —
// this directory now holds 6 files with multi-file importers). Deliberately
// NOT re-exported from the curated `services.dart` (the chat/-leaf
// precedent: `services.dart` does not re-export domain leaves either).
export 'faithful_mode.dart';
export 'prompts/director_prompts.dart';
export 'prompts/studio_archive_prompts.dart';
export 'prompts/studio_bible_prompts.dart';
export 'prompts/studio_context.dart';
export 'prompts/studio_prose_prompts.dart';
export 'prompts/studio_structure_prompts.dart';
export 'story_archetypes.dart';
export 'story_context.dart';
export 'story_continuity.dart';
export 'story_director.dart';
export 'story_director_apply.dart';
export 'story_edits.dart';
export 'story_engine_types.dart';
export 'story_json.dart';
export 'story_lenses.dart';
export 'story_lore_index.dart';
export 'story_pacing.dart';
export 'story_prompts.dart';
export 'story_quality.dart';
export 'story_quick_xml.dart';
export 'story_review.dart';
export 'story_shelf.dart';
export 'story_structure.dart';
export 'story_studio_store.dart';
export 'story_xml.dart';
export 'studio_parse.dart';
export 'studio_parse_prose.dart';
