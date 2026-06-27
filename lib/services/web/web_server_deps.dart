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

import 'package:shelf/shelf.dart' as shelf;

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/web/auth/auth_service.dart';
import 'package:front_porch_ai/services/web/facade/facades.dart';
import 'package:front_porch_ai/services/web/streaming/stream_hub.dart';
import 'package:front_porch_ai/services/web/tunnels/tunnel_manager.dart';

/// Immutable bundle of collaborators passed *down* into route groups and
/// middleware, so the rewritten server inverts the legacy "every route reaches
/// up into the god object" dependency. Route groups depend on this — never on
/// [WebServerHost].
///
/// Phase 1 carries auth + storage + db. Service facades (chat/character/story/
/// …) are added here in Phase 3; tunnels/TLS context in Phase 4.
class WebServerDeps {
  WebServerDeps({
    required this.storage,
    required this.db,
    required this.auth,
    this.streamHub,
    this.characterFacade,
    this.characterAuthoringFacade,
    this.characterLibraryFacade,
    this.chargenFacade,
    this.chatFacade,
    this.chatToolsFacade,
    this.groupFacade,
    this.settingsFacade,
    this.worldFacade,
    this.backendFacade,
    this.imageFacade,
    this.voiceFacade,
    this.storyFacade,
    this.storyExportFacade,
    this.tunnelManager,
    this.onClientActive,
  });

  final StorageService storage;
  final AppDatabase db;
  final AuthService auth;

  /// WebSocket fan-out. Null when no ChatService has been injected (auth-only
  /// boot); the stream route is registered only when this is present.
  final StreamHub? streamHub;

  /// Service facades — null until their backing services are injected. Route
  /// groups are registered only when their facade is present.
  final CharacterFacade? characterFacade;

  /// Character write-side adapter (delete + avatar management) — null until the
  /// CharacterRepository is injected.
  final CharacterAuthoringFacade? characterAuthoringFacade;

  /// Character *library* write adapter (folder CRUD, move, duplicate, export) —
  /// null until both the CharacterRepository and FolderService are injected.
  final CharacterLibraryFacade? characterLibraryFacade;

  /// AI character-creator adapter — null until the LLM provider + character
  /// facade are wired.
  final ChargenFacade? chargenFacade;

  final ChatFacade? chatFacade;

  /// Chat sidebar tools adapter (memory/summary/chaos/NSFW/scene-time/
  /// objectives) — null until a ChatService is injected.
  final ChatToolsFacade? chatToolsFacade;

  /// Group-chat library adapter — null until the group repository is injected.
  final GroupFacade? groupFacade;

  /// Generation/backend settings adapter — null until the LLM provider is wired.
  final SettingsFacade? settingsFacade;

  /// World (shared lorebook) CRUD adapter — null until the WorldRepository is
  /// injected.
  final WorldFacade? worldFacade;

  /// Backend lifecycle + model management adapter — null until the ModelManager
  /// is injected.
  final BackendFacade? backendFacade;

  /// Image-generation adapter — null until the ImageGenService is injected.
  final ImageFacade? imageFacade;

  /// Voice adapter (TTS synthesis + STT transcription) — null until the TTS and
  /// STT services are injected.
  final VoiceFacade? voiceFacade;

  /// Porch Stories adapter — null until the story repository + pipeline are
  /// injected.
  final StoryFacade? storyFacade;

  /// Host-bound Porch Stories export adapter (EPUB / audiobook / read-to-me) —
  /// null until the story repository + TTS service are injected.
  final StoryExportFacade? storyExportFacade;

  /// Remote-access (Tailscale/ngrok/port-forward) orchestrator. Created once the
  /// server is bound (it needs the live port). Null before bind.
  final TunnelManager? tunnelManager;

  /// Invoked by the auth middleware after a request authenticates, with the
  /// client IP and a human-readable "Browser on OS" string, to drive the
  /// desktop presence/lock UI.
  final void Function(String? ip, String info)? onClientActive;

  /// Whether the response for [request] is travelling over a secure (HTTPS)
  /// transport — governs the `Secure` cookie flag and HSTS.
  ///
  /// We trust `X-Forwarded-Proto: https` only when the immediate peer is
  /// loopback — i.e. the local Tailscale-serve / ngrok TLS terminator proxying
  /// to us on 127.0.0.1. A direct LAN/tailnet client could otherwise spoof the
  /// header, so checking the peer per-request (rather than a global bind-time
  /// flag) lets us bind to all interfaces and still tell real HTTPS apart.
  bool isSecure(shelf.Request request) {
    if (request.requestedUri.scheme == 'https') return true;
    if (request.headers['x-forwarded-proto']?.toLowerCase() != 'https') {
      return false;
    }
    final conn = request.context['shelf.io.connection_info'];
    return conn is HttpConnectionInfo && conn.remoteAddress.isLoopback;
  }
}
