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

/// The app services the web server talks to, injected one at a time by
/// `main.dart` through the host's setters. Any may be missing: the routes that
/// need a missing one are simply not wired.
class WebHostServices {
  ChatService? chat;
  CharacterRepository? characters;
  FolderService? folders;
  UserPersonaService? personas;
  GroupChatRepository? groups;
  LLMProvider? llm;
  WorldRepository? worlds;
  ModelManager? models;
  HardwareService? hardware;
  ImageGenService? imageGen;
  KoboldService? kobold;
  TtsService? tts;
  SttService? stt;
  StoryRepository? stories;
  StoryPipelineService? storyPipeline;
}
