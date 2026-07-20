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

// Barrel file for all data models.
//
// Import this instead of individual model files to reduce import boilerplate:
//
// ```dart
// import 'package:front_porch_ai/models/models.dart';
// ```
//
// Direct imports of individual model files remain supported for cases where
// only one or two models are needed.

export 'avatar_image.dart';
export 'character_card.dart';
export 'chat_generation_settings.dart';
export 'chat_message.dart';
export 'chat_theme_overrides.dart';
export 'chat_theme_preset.dart';
export 'chat_participant.dart';
export 'download_task.dart';
export 'group_chat.dart';
export 'group_card.dart';
export 'group_member.dart';
export 'hf_model.dart';
export 'local_model_info.dart';
export 'lorebook.dart';
export 'lorebook_codec.dart';
export 'lorebook_export.dart';
export 'story_project.dart';
export 'world.dart';
export 'needs_impact.dart';
