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

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/folder_service.dart';
import 'package:front_porch_ai/services/group_chat_repository.dart';
import 'package:front_porch_ai/services/hardware_service.dart';
import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/model_manager.dart';
import 'package:front_porch_ai/services/story_pipeline_service.dart';
import 'package:front_porch_ai/services/story_repository.dart';
import 'package:front_porch_ai/services/stt_service.dart';
import 'package:front_porch_ai/services/tts_service.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/services/world_repository.dart';
import 'package:front_porch_ai/services/web/auth/auth_service.dart';
import 'package:front_porch_ai/services/web/facade/facades.dart';
import 'package:front_porch_ai/services/web/server_bootstrap.dart';
import 'package:front_porch_ai/services/web/streaming/stream_hub.dart';
import 'package:front_porch_ai/services/web/tunnels/tailscale_provider.dart';
import 'package:front_porch_ai/services/web/tunnels/tunnel_manager.dart';
import 'package:front_porch_ai/services/web/web_server_deps.dart';

/// Lifecycle owner for the web server (the ChangeNotifier that `main.dart` and
/// the settings UI talk to). It only bootstraps + binds; all request behavior
/// lives in [buildWebHandler] and the route groups. This is the sole web server
/// — the legacy `WebServerService` was removed at cutover.
class WebServerHost extends ChangeNotifier {
  WebServerHost(this._storage);

  final StorageService _storage;
  AppDatabase? _db;
  ChatService? _chatService;
  CharacterRepository? _characterRepository;
  FolderService? _folderService;
  UserPersonaService? _userPersonaService;
  GroupChatRepository? _groupChatRepository;
  LLMProvider? _llmProvider;
  WorldRepository? _worldRepository;
  ModelManager? _modelManager;
  HardwareService? _hardwareService;
  ImageGenService? _imageGenService;
  TtsService? _ttsService;
  SttService? _sttService;
  StoryRepository? _storyRepository;
  StoryPipelineService? _storyPipelineService;

  HttpServer? _server;
  AuthService? _auth;
  StreamHub? _streamHub;
  TunnelManager? _tunnelManager;
  String? _lanIp;

  // Realism-eval overlay streaming: a ChatService listener that pushes the
  // accumulating eval text over the hub while the Realism Engine is thinking, so
  // the web shows the same live "processing" overlay the desktop does. Stored so
  // we can detach it on stop().
  VoidCallback? _realismListener;
  bool _wasEvaluatingRealism = false;

  // Near-instant library live-sync: one debounced listener attached to the
  // CharacterRepository, FolderService and GroupChatRepository (all
  // ChangeNotifiers). Because the desktop UI and the web facades mutate through
  // these same shared services, ANY library change — from the desktop app or a
  // web client — fans a single `library_changed` event out to every connected
  // browser so its library refreshes without a manual reload. Stored so we can
  // detach + cancel on stop().
  VoidCallback? _libraryListener;
  Timer? _libraryDebounce;

  // Connected-client presence (drives the desktop remote-lock overlay + the
  // settings "client connected" line). Set on the first authenticated request.
  bool _hasActiveClient = false;
  String? _connectedClientIp;
  String? _connectedClientInfo;

  bool get isRunning => _server != null;
  int get port => _server?.port ?? _storage.webServerSettings.webServerPort;
  String? get lanIp => _lanIp;
  bool get hasActiveClient => _hasActiveClient;
  String? get connectedClientIp => _connectedClientIp;
  String? get connectedClientInfo => _connectedClientInfo;

  /// Called by the auth middleware after a request authenticates. Updates the
  /// presence fields and notifies listeners only when something changed.
  void markClientActive(String? ip, String info) {
    if (_hasActiveClient && _connectedClientIp == ip) return;
    _hasActiveClient = true;
    _connectedClientIp = ip;
    _connectedClientInfo = info;
    notifyListeners();
  }

  /// Clear the active-client state (desktop "Disconnect" button).
  void disconnectClient() {
    if (!_hasActiveClient) return;
    _hasActiveClient = false;
    _connectedClientIp = null;
    _connectedClientInfo = null;
    notifyListeners();
  }

  /// Injected from main.dart (mirrors the legacy setX wiring style).
  void setDatabase(AppDatabase db) => _db = db;

  /// Chat service for live token streaming over the WebSocket hub.
  void setChatService(ChatService chatService) => _chatService = chatService;

  void setCharacterRepository(CharacterRepository repo) =>
      _characterRepository = repo;
  void setGroupChatRepository(GroupChatRepository repo) =>
      _groupChatRepository = repo;
  void setLlmProvider(LLMProvider provider) => _llmProvider = provider;
  void setFolderService(FolderService service) => _folderService = service;
  void setUserPersonaService(UserPersonaService service) =>
      _userPersonaService = service;
  void setWorldRepository(WorldRepository repo) => _worldRepository = repo;
  void setModelManager(ModelManager manager) => _modelManager = manager;
  void setHardwareService(HardwareService service) =>
      _hardwareService = service;
  void setImageGenService(ImageGenService service) =>
      _imageGenService = service;
  void setTtsService(TtsService service) => _ttsService = service;
  void setSttService(SttService service) => _sttService = service;
  void setStoryRepository(StoryRepository repo) => _storyRepository = repo;
  void setStoryPipelineService(StoryPipelineService service) =>
      _storyPipelineService = service;

  /// The auth service (lazily built once a database is available) — exposed so
  /// settings UI can surface account/2FA state.
  AuthService? get auth => _auth;

  /// Remote-access orchestrator (null until the server is running). Exposed so
  /// the Flutter settings UI can read tunnel state directly.
  TunnelManager? get tunnels => _tunnelManager;

  Future<void> start([int? portOverride]) async {
    if (isRunning) return;
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

    final auth = _auth = AuthService(db);
    await auth.sessions.sweep();

    final chatService = _chatService;
    final streamHub = _streamHub = chatService != null
        ? StreamHub(chatService.tokenStream, () => chatService.isGenerating)
        : null;

    // Stream the Realism + Objective engines' "processing" state to the web
    // overlay. ChatService notifies (debounced ~150ms) as eval chunks arrive; we
    // only broadcast while something is actually processing, and emit one final
    // {active:false} so the overlay dismisses. Cheap no-op on every other notify
    // (just a couple of bool reads).
    if (chatService != null && streamHub != null) {
      void onProcessing() {
        final realism = chatService.isEvaluatingRealism;
        final objective = chatService.isCheckingCompletion;
        final active = realism || objective;
        if (active) {
          streamHub.broadcast({
            'event': 'processing',
            'active': true,
            'realism': realism,
            'objective': objective,
            'greeting': chatService.isProcessingGreeting,
            'verifying': chatService.isVerifyingRealism,
            'text': chatService.realismEvalStreamTextClean,
          });
        } else if (_wasEvaluatingRealism) {
          streamHub.broadcast({'event': 'processing', 'active': false});
        }
        _wasEvaluatingRealism = active;
      }

      _realismListener = onProcessing;
      chatService.addListener(onProcessing);
    }

    // Library live-sync: broadcast a single debounced `library_changed` whenever
    // characters, folders or groups change (from the desktop or a web client),
    // so every browser refreshes its library near-instantly. Debounced ~150ms to
    // coalesce the multiple notifies a single op can fire (e.g. an import).
    if (streamHub != null) {
      void onLibraryChanged() {
        _libraryDebounce?.cancel();
        _libraryDebounce = Timer(const Duration(milliseconds: 150), () {
          streamHub.broadcast({'event': 'library_changed'});
        });
      }

      _libraryListener = onLibraryChanged;
      _characterRepository?.addListener(onLibraryChanged);
      _folderService?.addListener(onLibraryChanged);
      _groupChatRepository?.addListener(onLibraryChanged);
    }

    final characterFacade = CharacterFacade(
      db,
      _storage,
      _folderService,
      chatService,
      _characterRepository,
    );
    final chatFacade = (chatService != null && _characterRepository != null)
        ? ChatFacade(
            chatService,
            _characterRepository!,
            _userPersonaService,
            streamHub,
            _groupChatRepository,
          )
        : null;

    final characterAuthoringFacade = _characterRepository != null
        ? CharacterAuthoringFacade(_characterRepository!, _storage)
        : null;

    final folderService = _folderService;
    final characterLibraryFacade =
        (_characterRepository != null && folderService != null)
        ? CharacterLibraryFacade(_characterRepository!, folderService)
        : null;

    final chargenFacade = _llmProvider != null
        ? ChargenFacade(_llmProvider!, characterFacade, streamHub, _imageGenService)
        : null;

    final chatToolsFacade = chatService != null
        ? ChatToolsFacade(chatService, _storage, streamHub)
        : null;

    final groupFacade = _groupChatRepository != null
        ? GroupFacade(_groupChatRepository!, _storage, _characterRepository, db)
        : null;

    final settingsFacade = _llmProvider != null
        ? SettingsFacade(_storage, _llmProvider!)
        : null;

    final worldFacade = _worldRepository != null
        ? WorldFacade(_worldRepository!, _characterRepository)
        : null;

    final backendFacade = (_llmProvider != null && _modelManager != null)
        ? BackendFacade(
            _llmProvider!,
            _storage,
            _modelManager!,
            _hardwareService,
          )
        : null;

    final imageFacade = _imageGenService != null
        ? ImageFacade(_imageGenService!, _storage)
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
      chatToolsFacade: chatToolsFacade,
      groupFacade: groupFacade,
      settingsFacade: settingsFacade,
      worldFacade: worldFacade,
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
    _server = await shelf_io.serve(buildWebHandler(deps), bindAddress, bindPort)
      ..autoCompress = true;

    if (exposeAll) _lanIp = await _detectLanIp();
    debugPrint(
      '[WebServerHost] Listening on http://${exposeAll ? (_lanIp ?? '0.0.0.0') : 'localhost'}:${_server!.port}',
    );

    // Re-establish the clean no-port HTTPS URL on launch for opted-in users.
    // Best-effort: a failure here just means they fall back to the port URL.
    if (settings.webServerAutoRemote && tsRunning) {
      await tunnelManager.enableTailscale();
    }
    notifyListeners();
  }

  Future<void> stop() async {
    final server = _server;
    if (server == null) return;
    _server = null;
    if (_realismListener != null) {
      _chatService?.removeListener(_realismListener!);
      _realismListener = null;
    }
    _wasEvaluatingRealism = false;
    if (_libraryListener != null) {
      _characterRepository?.removeListener(_libraryListener!);
      _folderService?.removeListener(_libraryListener!);
      _groupChatRepository?.removeListener(_libraryListener!);
      _libraryListener = null;
    }
    _libraryDebounce?.cancel();
    _libraryDebounce = null;
    await _streamHub?.dispose();
    _streamHub = null;
    await _tunnelManager?.dispose();
    _tunnelManager = null;
    await server.close(force: true);
    _lanIp = null;
    _hasActiveClient = false;
    _connectedClientIp = null;
    _connectedClientInfo = null;
    debugPrint('[WebServerHost] Stopped');
    notifyListeners();
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

  Future<String?> _detectLanIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (ip.startsWith('192.168.') ||
              ip.startsWith('10.') ||
              _is172Private(ip)) {
            return ip;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  bool _is172Private(String ip) {
    if (!ip.startsWith('172.')) return false;
    final second = int.tryParse(ip.split('.')[1]) ?? 0;
    return second >= 16 && second <= 31;
  }
}

/// Outcome of [WebServerHost.setupRemoteAccess] — drives the tutorial's final
/// "you're live / enable HTTPS / not yet" state.
class RemoteSetupResult {
  const RemoteSetupResult({
    required this.outcome,
    this.httpsUrl,
    this.portUrl,
    this.reachable = false,
  });

  /// How the Tailscale HTTPS serve resolved (ok / needs the admin toggle / …).
  final TailscaleServeOutcome outcome;

  /// Clean no-port `https://<magicdns>` address — null unless [outcome] is ok.
  final String? httpsUrl;

  /// `http://<magicdns>:<port>` fallback — works whenever Tailscale is up, even
  /// before HTTPS certs are enabled.
  final String? portUrl;

  /// Whether the best available address was just verified to route back here.
  final bool reachable;

  /// The address to surface first: HTTPS when available, else the port URL.
  String? get primaryUrl => httpsUrl ?? portUrl;
}
