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

import 'package:flutter/widgets.dart';
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/web_server_host.dart';
import 'package:provider/provider.dart';

/// The web relay with every collaborator wired. A named function rather than
/// an inline `create:` so the WebServerHost proxy's `update` can fall back to
/// it instead of ever handing out a half-wired host. [context] must sit below
/// every provider it reads; [db] is the startup database handle.
WebServerHost createWiredWebServerHost(BuildContext context, AppDatabase db) {
  final host = WebServerHost(
    Provider.of<StorageService>(context, listen: false),
  );
  host.setDatabase(db);
  host.setChatService(Provider.of<ChatService>(context, listen: false));
  host.setKoboldService(Provider.of<KoboldService>(context, listen: false));
  host.setCharacterRepository(
    Provider.of<CharacterRepository>(context, listen: false),
  );
  host.setGroupChatRepository(
    Provider.of<GroupChatRepository>(context, listen: false),
  );
  host.setLlmProvider(Provider.of<LLMProvider>(context, listen: false));
  host.setFolderService(Provider.of<FolderService>(context, listen: false));
  host.setUserPersonaService(
    Provider.of<UserPersonaService>(context, listen: false),
  );
  host.setWorldRepository(Provider.of<WorldRepository>(context, listen: false));
  host.setModelManager(Provider.of<ModelManager>(context, listen: false));
  host.setHardwareService(Provider.of<HardwareService>(context, listen: false));
  host.setImageGenService(Provider.of<ImageGenService>(context, listen: false));
  host.setTtsService(Provider.of<TtsService>(context, listen: false));
  host.setSttService(Provider.of<SttService>(context, listen: false));
  host.setStoryRepository(Provider.of<StoryRepository>(context, listen: false));
  host.setStoryPipelineService(
    Provider.of<StoryPipelineService>(context, listen: false),
  );
  return host;
}
