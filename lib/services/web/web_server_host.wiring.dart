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

part of 'web_server_host.dart';

/// Facade assembly, bind, and remote-access setup.
extension WebServerHostWiring on WebServerHost {
  Future<void> start([int? portOverride]) async {
    if (isRunning) return;
    final int generation = ++_startGeneration;
    final db = _db;
    if (db == null) {
      throw StateError('WebServerHost.start() called before setDatabase()');
    }

    final settings = _storage.webServerSettings;
    final bindPort = portOverride ?? settings.webServerPort;

    // Decide the bind interface. We listen on all interfaces when LAN access is
    // explicitly allowed, OR when the user has opted into remote access and
    // Tailscale is actually running — otherwise the MagicDNS address (which
    // resolves to the 100.x tailnet interface, not loopback) can never reach
    // us. Loopback stays reachable in every case. One provider instance is
    // reused for the bind decision, the TunnelManager, and the auto-serve.
    final tailscale = TailscaleProvider();
    final tsRunning = settings.webServerAutoRemote
        ? (await tailscale.status()).running
        : false;
    final exposeAll =
        settings.webServerAllowLan ||
        (settings.webServerAutoRemote && tsRunning);
    final bindAddress = exposeAll ? InternetAddress.anyIPv4 : '127.0.0.1';

    final auth = _auth ??= AuthService(db);
    await auth.sessions.sweep();

    final chatService = _chatService;
    final streamHub = _streamHub = chatService != null
        ? StreamHub(chatService.tokenStream, () => chatService.isGenerating)
        : null;

    _attachLiveRelays(chatService, streamHub);

    final characterFacade = CharacterFacade(
      db,
      _storage,
      _folderService,
      chatService,
      _characterRepository,
    );

    if (streamHub != null) {
      _attachLibraryRelay(characterFacade, streamHub);
    }

    // Built before ChatFacade so its saved-image resolver (basename → File
    // with the traversal guard) can be shared for chat image messages.
    final imageFacade = _imageGenService != null
        ? ImageFacade(_imageGenService!, _storage)
        : null;

    final chatFacade = (chatService != null && _characterRepository != null)
        ? ChatFacade(
            chatService,
            _characterRepository!,
            _userPersonaService,
            streamHub,
            _groupChatRepository,
            resolveSavedImage: imageFacade?.savedImageFile,
            llm: _llmProvider,
          )
        : null;

    final characterAuthoringFacade = _characterRepository != null
        ? CharacterAuthoringFacade(_characterRepository!, _storage)
        : null;

    final folderService = _folderService;
    final characterLibraryFacade =
        (_characterRepository != null && folderService != null)
        ? CharacterLibraryFacade(
            _characterRepository!,
            folderService,
            _storage,
            _groupChatRepository,
          )
        : null;

    final chargenFacade = _llmProvider != null
        ? ChargenFacade(
            _llmProvider!,
            characterFacade,
            streamHub,
            _imageGenService,
            _storage,
            chatService,
          )
        : null;

    final chatToolsFacade = chatService != null
        ? ChatToolsFacade(
            chatService,
            _storage,
            streamHub,
            storyRepo: _storyRepository,
            personas: _userPersonaService,
          )
        : null;

    final groupFacade = _groupChatRepository != null
        ? GroupFacade(
            _groupChatRepository!,
            _storage,
            _characterRepository,
            db,
            _folderService,
          )
        : null;

    final settingsFacade = _llmProvider != null
        ? SettingsFacade(_storage, _llmProvider!, chat: _chatService)
        : null;

    // The Stoop relay. The web client keeps its own Stoop session (tokens in
    // browser localStorage, sent per-request); the facade only relays calls
    // and runs the local import chain on downloads.
    final stoopFacade = StoopFacade(
      _storage,
      db,
      characters: _characterRepository,
      groups: _groupChatRepository,
      worlds: _worldRepository,
    );

    final worldFacade = _worldRepository != null
        ? WorldFacade(
            _worldRepository!,
            _characterRepository,
            chatService,
            _groupChatRepository,
          )
        : null;

    final worldFromWikiFacade = _llmProvider != null
        ? WorldFromWikiFacade(_llmProvider!, _storage, streamHub)
        : null;

    final backendFacade = (_llmProvider != null && _modelManager != null)
        ? BackendFacade(
            _llmProvider!,
            _storage,
            _modelManager!,
            _hardwareService,
          )
        : null;

    final voiceFacade = (_ttsService != null && _sttService != null)
        ? VoiceFacade(_ttsService!, _sttService!, _storage)
        : null;

    // Snapshots are rebuilt server-side from authoritative card text + roles, so
    // "seed from chats" / "include persona" actually carry data into the
    // pipeline (the web client has no card text to send).
    final snapshotBuilder = _characterRepository != null
        ? StorySnapshotBuilder(_characterRepository!, _userPersonaService)
        : null;
    final storyFacade =
        (_storyRepository != null && _storyPipelineService != null)
        ? StoryFacade(
            _storyRepository!,
            _storyPipelineService!,
            streamHub,
            snapshotBuilder: snapshotBuilder,
            tts: _ttsService,
          )
        : null;

    final storyExportFacade = (_storyRepository != null && _ttsService != null)
        ? StoryExportFacade(
            _storyRepository!,
            _ttsService!,
            _storage,
            streamHub,
          )
        : null;

    final tunnelManager = _tunnelManager = TunnelManager(
      bindPort,
      tailscale: tailscale,
    );

    final deps = WebServerDeps(
      storage: _storage,
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
      onClientActive: markClientActive,
    );

    // Direct binds (localhost or LAN) are always plain HTTP — never a
    // self-signed cert, whose browser trust warning is worse UX than http.
    // Real HTTPS comes only from a trusted external terminator (Tailscale
    // serve / ngrok); over those our server stays plain http on loopback.
    final bound =
        await shelf_io.serve(buildWebHandler(deps), bindAddress, bindPort)
          ..autoCompress = true;

    // The caller gave up on this run while it was binding (startSafely's
    // timeout, or a stop()). Publishing the socket now would leave the app
    // listening with "disabled" already persisted and the UI insisting the
    // server is off — so close what we just opened and leave.
    if (generation != _startGeneration) {
      await bound.close(force: true);
      debugPrint('[WebServerHost] Abandoned start — closed the late socket');
      return;
    }
    _server = bound;

    if (exposeAll) {
      final ip = await detectPrivateLanIp();
      // Same race, one await later: a stop() during the LAN lookup already
      // closed the socket above, so leave rather than report an address (or
      // open a tunnel) for a server that is gone.
      if (generation != _startGeneration) return;
      _lanIp = ip;
    }
    debugPrint(
      '[WebServerHost] Listening on http://${exposeAll ? (_lanIp ?? '0.0.0.0') : 'localhost'}:${bound.port}',
    );

    // Re-establish the clean no-port HTTPS URL on launch for opted-in users.
    // Best-effort: a failure here just means they fall back to the port URL.
    if (settings.webServerAutoRemote && tsRunning) {
      await tunnelManager.enableTailscale();
    }
    notify();
  }

  /// "Take the wheel" remote-access setup driven by the web-access tutorial:
  /// persist the opt-in, (re)bind so the tailnet address reaches us, turn on
  /// Tailscale HTTPS (auto-cert), and verify the result actually routes back.
  /// Returns everything the dialog needs to show the right next step; the port
  /// URL is always offered as a guaranteed fallback to the HTTPS URL.
  ///
  /// Pass `restart: false` for the "I've enabled HTTPS, check again" button —
  /// it just re-attempts serve + verify without bouncing the live server.
  Future<RemoteSetupResult> setupRemoteAccess({bool restart = true}) async {
    await _storage.webServerSettings.setWebServerAutoRemote(true);

    if (restart && isRunning) await stop();
    if (!isRunning) await start(_storage.webServerSettings.webServerPort);

    final tunnels = _tunnelManager;
    if (tunnels == null) {
      return const RemoteSetupResult(outcome: TailscaleServeOutcome.failed);
    }

    final serve = await tunnels.enableTailscale();
    final ts = await tunnels.tailscaleStatus();
    final dns = ts.magicDnsName;
    final portUrl = dns != null ? 'http://$dns:${tunnels.port}' : null;

    // Verify the best address we have (HTTPS if serve succeeded, else the port).
    final best = serve.url ?? portUrl;
    final reachable = best != null && await tunnels.verifyReachable(best);

    return RemoteSetupResult(
      outcome: serve.outcome,
      httpsUrl: serve.url,
      portUrl: portUrl,
      reachable: reachable,
    );
  }
}
