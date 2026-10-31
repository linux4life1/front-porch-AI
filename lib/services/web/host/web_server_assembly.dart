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

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/auth/auth_service.dart';
import 'package:front_porch_ai/services/web/facade/facades.dart';
import 'package:front_porch_ai/services/web/host/web_host_services.dart';
import 'package:front_porch_ai/services/web/streaming/stream_hub.dart';
import 'package:front_porch_ai/services/web/tunnels/tunnels.dart';
import 'package:front_porch_ai/services/web/web_server_deps.dart';

/// Builds every service facade the routes need from the services the host
/// was given, and bundles them into [WebServerDeps]. A facade whose services
/// are missing is left null, which switches its routes off. Also returns the
/// story facade, which the host re-points when the story pipeline changes.
({WebServerDeps deps, StoryFacade? storyFacade}) assembleWebServerDeps({
  required WebHostServices services,
  required StorageService storage,
  required AppDatabase db,
  required AuthService auth,
  required StreamHub? streamHub,
  required CharacterFacade characterFacade,
  required TunnelManager tunnelManager,
  required void Function(String? ip, String info) onClientActive,
}) {
  final chatService = services.chat;
  final characters = services.characters;
  final folders = services.folders;
  final personas = services.personas;
  final groups = services.groups;
  final llm = services.llm;
  final worlds = services.worlds;
  final models = services.models;
  final imageGen = services.imageGen;
  final tts = services.tts;
  final stt = services.stt;
  final stories = services.stories;
  final storyPipeline = services.storyPipeline;

  // Built before ChatFacade so its saved-image resolver (basename → File
  // with the traversal guard) can be shared for chat image messages.
  final imageFacade = imageGen != null
      ? ImageFacade(imageGen, storage, characters)
      : null;
  imageFacade?.promptLlm = () {
    final service = services.llm?.activeService;
    return service?.isReady == true ? service : null;
  };

  final chatFacade = (chatService != null && characters != null)
      ? ChatFacade(
          chatService,
          characters,
          personas,
          streamHub,
          groups,
          resolveSavedImage: imageFacade?.savedImageFile,
          llm: llm,
        )
      : null;

  final personaConversionFacade = (characters != null && personas != null)
      ? PersonaConversionFacade(characters, personas, storage)
      : null;
  // "Make a Character" from a persona keeps the persona's picture.
  characterFacade.personaPortrait = personaConversionFacade?.portraitPathFor;
  characterFacade.worlds = worlds;

  final characterAuthoringFacade = characters != null
      ? CharacterAuthoringFacade(characters, storage)
      : null;

  final characterLibraryFacade = (characters != null && folders != null)
      ? CharacterLibraryFacade(characters, folders, storage, groups)
      : null;

  final chargenFacade = llm != null
      ? ChargenFacade(
          llm,
          characterFacade,
          streamHub,
          imageGen,
          storage,
          chatService,
        )
      : null;

  final chatToolsFacade = chatService != null
      ? ChatToolsFacade(
          chatService,
          storage,
          streamHub,
          storyRepo: stories,
          personas: personas,
        )
      : null;

  final groupFacade = groups != null
      ? GroupFacade(groups, storage, characters, db, folders, worlds)
      : null;
  // A member picture found to be the no-portrait placeholder asks for one
  // library refetch, through the same debounce as the character list.
  groupFacade?.onPlaceholderPortraitsFound =
      characterFacade.onPlaceholderPortraitsFound;
  if (llm != null) {
    groupFacade?.opening = GroupDraftOpening(llm, characters, worlds);
  }
  groupFacade?.memberEdit = GroupMemberEdit(db, storage, chatService, worlds);

  final settingsFacade = llm != null
      ? SettingsFacade(storage, llm, chat: chatService)
      : null;

  // The Stoop relay. The web client keeps its own Stoop session (tokens in
  // browser localStorage, sent per-request); the facade only relays calls
  // and runs the local import chain on downloads.
  final stoopFacade = StoopFacade(
    storage,
    db,
    characters: characters,
    groups: groups,
    worlds: worlds,
  );

  final worldFacade = worlds != null
      ? WorldFacade(worlds, characters, chatService, groups)
      : null;

  final worldFromWikiFacade = (llm != null && chatService != null)
      ? WorldFromWikiFacade(
          llm,
          storage,
          streamHub,
          chatService,
          db: db,
          characters: characters,
        )
      : null;

  final backendFacade = (llm != null && models != null)
      ? BackendFacade(llm, storage, models, services.hardware)
      : null;

  final voiceFacade = (tts != null && stt != null)
      ? VoiceFacade(tts, stt, storage)
      : null;

  // Snapshots are rebuilt server-side from authoritative card text + roles, so
  // "seed from chats" / "include persona" actually carry data into the
  // pipeline (the web client has no card text to send).
  final snapshotBuilder = characters != null
      ? StorySnapshotBuilder(characters, personas)
      : null;
  final storyFacade = (stories != null && storyPipeline != null)
      ? StoryFacade(
          stories,
          storyPipeline,
          streamHub,
          snapshotBuilder: snapshotBuilder,
          tts: tts,
          storage: storage,
          llm: llm,
          imageGen: imageGen,
        )
      : null;

  final storyExportFacade = (stories != null && tts != null)
      ? StoryExportFacade(stories, tts, storage, streamHub)
      : null;

  final deps = WebServerDeps(
    storage: storage,
    db: db,
    auth: auth,
    streamHub: streamHub,
    characterFacade: characterFacade,
    characterAuthoringFacade: characterAuthoringFacade,
    characterLibraryFacade: characterLibraryFacade,
    chargenFacade: chargenFacade,
    chatFacade: chatFacade,
    chatPackageFacade: chatService != null
        ? ChatPackageFacade(chatService)
        : null,
    porchFacade: (chatService != null && characters != null)
        ? PorchFacade(characters, chatService, storage)
        : null,
    personaConversionFacade: personaConversionFacade,
    chatToolsFacade: chatToolsFacade,
    groupFacade: groupFacade,
    settingsFacade: settingsFacade,
    stoopFacade: stoopFacade,
    worldFacade: worldFacade,
    worldFromWikiFacade: worldFromWikiFacade,
    backendFacade: backendFacade,
    imageFacade: imageFacade,
    voiceFacade: voiceFacade,
    storyFacade: storyFacade,
    storyExportFacade: storyExportFacade,
    tunnelManager: tunnelManager,
    onClientActive: onClientActive,
  );
  return (deps: deps, storyFacade: storyFacade);
}
