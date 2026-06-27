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

// Barrel file for the most frequently used services.
//
// This is a *curated* surface, not an exhaustive export of every service.
// Internal-only or rarely-used modules (grpc generated code, kokoro worker
// pools, setup internals, etc.) are intentionally left as direct imports.
//
// Preferred usage for new or refactored code:
//
// ```dart
// import 'package:front_porch_ai/services/services.dart';
// ```
//
// Direct imports of individual service files remain fully supported and are
// the correct choice when only one or two niche services are needed.

export 'storage_service.dart';
export 'character_repository.dart';
export 'group_chat_repository.dart';
export 'group_card_service.dart';
export 'group_card_exporter.dart';
export 'world_repository.dart';
export 'story_repository.dart';

// LLM & chat
export 'llm_provider.dart';
export 'llm_service.dart';
export 'kobold_service.dart';
export 'chat_service.dart';
export 'backend_manager.dart';
export 'pseudo_remote_service.dart';
export 'open_router_service.dart';

// Chat domain leaves (curated high-freq per extraction policy; needs impact evaluator
// for the consolidated eval/impact layer; direct import also supported).
export 'chat/needs_impact_evaluator.dart';

// TTS / STT / media
export 'tts_service.dart';
export 'tts_voice_info.dart';
export 'stt_service.dart';
export 'image_gen_service.dart';

// Sync & data
export 'cloud_sync_service.dart';
export 'v2_card_service.dart';
export 'user_persona_service.dart';
export 'folder_service.dart';

// Other frequently used
export 'expression_classifier.dart';
export 'hardware_service.dart';
export 'voice_manager.dart';
export 'update_service.dart';
export 'story_pipeline_service.dart';

// Backup & generation tools (now used by web server + UI)
export 'backup_service.dart';
export 'character_gen_service.dart';
