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
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/folder_service.dart';
import 'package:front_porch_ai/services/group_chat_repository.dart';
import 'package:front_porch_ai/services/hardware_service.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
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
import 'package:front_porch_ai/services/web/tunnels/lan_ip.dart';
import 'package:front_porch_ai/services/web/tunnels/remote_setup_result.dart';
import 'package:front_porch_ai/services/web/web_server_deps.dart';

// Re-export the extracted RemoteSetupResult so existing consumers importing
// this host file are unaffected.
export 'package:front_porch_ai/services/web/tunnels/remote_setup_result.dart';

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
  KoboldService? _koboldService;
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
  bool _wasAwaitingChanceTime = false;
  bool _wasPendingImageReview = false;

  // Image-gen progress relay (see the imageGen listener in start()).
  VoidCallback? _imageProgressListener;
  bool _wasImageGenerating = false;
  DateTime _lastImageProgressSent = DateTime.fromMillisecondsSinceEpoch(0);

  // Truthful generation-status relay (parity with the desktop status bar):
  // live prompt-reading progress parsed from the managed KoboldCpp console +
  // which background pass is holding the single local slot. Listens on BOTH
  // the ChatService (phase flips) and the KoboldService (live counts), plus
  // a 1s heartbeat timer: console lines arrive only once per BATCH, so
  // between them no notifier fires and the interpolated fraction would
  // freeze on web without the tick.
  VoidCallback? _genStatusListener;
  Timer? _genStatusTicker;
  bool _wasBroadcastingGenStatus = false;
  DateTime _lastGenStatusSent = DateTime.fromMillisecondsSinceEpoch(0);

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
  void setKoboldService(KoboldService service) => _koboldService = service;
  void setTtsService(TtsService service) => _ttsService = service;
  void setSttService(SttService service) => _sttService = service;
  void setStoryRepository(StoryRepository repo) => _storyRepository = repo;
  void setStoryPipelineService(StoryPipelineService service) =>
      _storyPipelineService = service;

  /// The auth service (lazily built once a database is available) — exposed so
  /// the desktop settings UI can surface the account and offer the local
  /// recovery actions (sign out all devices / reset web login) even while the
  /// server itself is stopped. `start()` reuses the same instance.
  AuthService? get auth {
    final db = _db;
    if (db == null) return null;
    return _auth ??= AuthService(db);
  }

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

    final auth = _auth ??= AuthService(db);
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

        // Chance Time: chaos parks sendMessage on a completer until the user
        // accepts their fate. Desktop pops its wheel from a ChangeNotifier flag;
        // web clients have no such hook, so announce the park (and its release)
        // here so the reveal modal can open/close. `data` carries the
        // pre-resolved event for an instant reveal; /api/chat/state.chanceTime
        // is the reconnect fallback. Edge-triggered — a couple of cheap reads on
        // every other notify.
        final awaitingChance = chatService.isAwaitingChanceTime;
        if (awaitingChance != _wasAwaitingChanceTime) {
          streamHub.broadcast(
            awaitingChance
                ? {
                    'event': 'chance_time',
                    'pending': true,
                    'data': ?chatService.webChanceTimeDisplay,
                  }
                : {'event': 'chance_time', 'pending': false},
          );
          _wasAwaitingChanceTime = awaitingChance;
        }
        // /image prompt review parked/resolved — poke clients to refetch state
        // so the web review modal opens/closes (same transition pattern as
        // Chance Time; the send request itself is blocked on the completer).
        final pendingReview = chatService.pendingImagePromptReview != null;
        if (pendingReview != _wasPendingImageReview) {
          streamHub.broadcast({'event': 'chat_updated'});
          _wasPendingImageReview = pendingReview;
        }
      }

      _realismListener = onProcessing;
      chatService.addListener(onProcessing);
    }

    // Truthful generation status → web clients (parity with the desktop
    // status bar): live prompt-reading counts from the ACTIVE backend's
    // source (Kobold console, oMLX admin-stats poll, LM Studio runtime log
    // — resolved by chatService.activeLiveProgress), plus which background
    // pass (journal/growth) or queued request is holding the slot.
    // Throttled to ~2.5/s; one final {active:false} dismisses the line.
    // Plain remote backends never have fresh live counts, so clients fall
    // back to their plain indicator.
    final kobold = _koboldService;
    if (streamHub != null && chatService != null) {
      void onGenStatus() {
        final generating = chatService.isGenerating;
        if (!generating) {
          if (_wasBroadcastingGenStatus) {
            _wasBroadcastingGenStatus = false;
            streamHub.broadcast({'event': 'gen_status', 'active': false});
          }
          return;
        }
        final now = DateTime.now();
        if (now.difference(_lastGenStatusSent).inMilliseconds < 400) return;
        _lastGenStatusSent = now;
        _wasBroadcastingGenStatus = true;
        final live = chatService.activeLiveProgress;
        final fresh = live != null && live.isFresh;
        // Server-side interpolation between per-batch updates (same math as
        // the desktop bar) so web clients get a moving fraction without
        // doing their own estimation.
        final perfSpeed = chatService.lastPerfData?['last_process_speed'];
        final estFraction = fresh
            ? live.estimatedPromptFraction(
                tokensPerSecond: (perfSpeed is num && perfSpeed > 0)
                    ? perfSpeed.toDouble()
                    : null,
              )
            : null;
        streamHub.broadcast({
          'event': 'gen_status',
          'active': true,
          'phase': chatService.generationPhase.name,
          'busyWith': chatService.isSummaryGenerating
              ? 'journal'
              : (chatService.isGrowthPassRunning ? 'growth' : null),
          // Backend-reported queue depth — NOT attributable (may be someone
          // waiting on us), so clients state it neutrally (review finding).
          'queued': fresh ? live.waitingCount : 0,
          'promptCur': fresh ? live.promptCurrent : null,
          'promptTotal': fresh ? live.promptTotal : null,
          'promptDone': fresh && (live.promptFraction() ?? 0) >= 1.0,
          'estFraction': estFraction,
          'genCur': fresh ? live.genCurrent : null,
          'genTotal': fresh ? live.genTotal : null,
        });
      }

      _genStatusListener = onGenStatus;
      chatService.addListener(onGenStatus);
      // Kobold pushes console updates through notifyListeners; the polled
      // sources (oMLX / LM Studio) ride the 1s heartbeat below instead.
      kobold?.addListener(onGenStatus);
      // Heartbeat: keeps the interpolated fraction moving between console
      // lines. Cheap no-op whenever nothing is generating.
      _genStatusTicker = Timer.periodic(
        const Duration(seconds: 1),
        (_) => onGenStatus(),
      );
    }

    // Image generation live progress → web clients: percent + (when the
    // backend streams one) the in-progress preview frame, so the web chat
    // shows the image coming to life like the desktop bubble. Preview frames
    // are throttled to ~1/s to keep the socket light.
    final imageGen = _imageGenService;
    if (streamHub != null && imageGen != null) {
      void onImageProgress() {
        final generating = imageGen.isGenerating;
        if (!generating && !_wasImageGenerating) return;
        if (!generating) {
          streamHub.broadcast({'event': 'image_progress', 'generating': false});
          _wasImageGenerating = false;
          return;
        }
        final now = DateTime.now();
        if (_wasImageGenerating &&
            now.difference(_lastImageProgressSent).inMilliseconds < 700) {
          return;
        }
        _lastImageProgressSent = now;
        final preview = imageGen.genPreview;
        // A1111 previews are PNG, ComfyUI's are typically JPEG — sniff the
        // magic bytes so the data URL declares the right mime.
        String? previewUrl;
        if (preview != null && preview.length > 2) {
          final mime = (preview[0] == 0xFF && preview[1] == 0xD8)
              ? 'image/jpeg'
              : 'image/png';
          previewUrl = 'data:$mime;base64,${base64Encode(preview)}';
        }
        streamHub.broadcast({
          'event': 'image_progress',
          'generating': true,
          'progress': ?imageGen.genProgress,
          'preview': ?previewUrl,
        });
        _wasImageGenerating = true;
      }

      _imageProgressListener = onImageProgress;
      imageGen.addListener(onImageProgress);
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
          )
        : null;

    final chargenFacade = _llmProvider != null
        ? ChargenFacade(
            _llmProvider!,
            characterFacade,
            streamHub,
            _imageGenService,
          )
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

    // The Stoop relay. The web client keeps its own Stoop session (tokens in
    // browser localStorage, sent per-request); the facade only relays calls
    // and runs the local import chain on downloads.
    final stoopFacade = StoopFacade(
      _storage,
      db,
      characters: _characterRepository,
      groups: _groupChatRepository,
    );

    final worldFacade = _worldRepository != null
        ? WorldFacade(
            _worldRepository!,
            _characterRepository,
            chatService,
            _groupChatRepository,
          )
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
      chatToolsFacade: chatToolsFacade,
      groupFacade: groupFacade,
      settingsFacade: settingsFacade,
      stoopFacade: stoopFacade,
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

    if (exposeAll) _lanIp = await detectPrivateLanIp();
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

  /// Crash-loop-safe entry point for starting the server, used by launch-time
  /// auto-start (main.dart) and the Settings toggle. A hung or crashing [start]
  /// must never lock the user out, since "enabled" is already persisted and
  /// would re-crash every launch. So a persisted "starting" breadcrumb is set
  /// before the risky bind and cleared on success — if [isAutoStart] still sees
  /// it set on a later launch, the previous start never finished, so we disable
  /// the server and open cleanly. The start is also time-boxed, and any
  /// error/timeout disables it and tears down the half-started state. Returns
  /// whether the server ended up running.
  Future<bool> startSafely(int port, {bool isAutoStart = false}) async {
    final settings = _storage.webServerSettings;
    if (isAutoStart && settings.webServerStarting) {
      debugPrint(
        '[WebServerHost] Previous start did not finish — disabling the web '
        'server so the app launches cleanly (re-enable it in Settings).',
      );
      await settings.setWebServerStarting(false);
      await settings.setWebServerEnabled(false);
      return false;
    }
    try {
      await settings.setWebServerStarting(true);
      await start(port).timeout(const Duration(seconds: 25));
      await settings.setWebServerStarting(false);
      return isRunning;
    } catch (e) {
      debugPrint('[WebServerHost] Web server start failed: $e — disabling.');
      await settings.setWebServerStarting(false);
      await settings.setWebServerEnabled(false);
      try {
        await stop();
      } catch (_) {}
      return false;
    }
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
    if (_genStatusListener != null) {
      _chatService?.removeListener(_genStatusListener!);
      _koboldService?.removeListener(_genStatusListener!);
      _genStatusListener = null;
    }
    _genStatusTicker?.cancel();
    _genStatusTicker = null;
    _wasBroadcastingGenStatus = false;
    if (_imageProgressListener != null) {
      _imageGenService?.removeListener(_imageProgressListener!);
      _imageProgressListener = null;
    }
    _wasImageGenerating = false;
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
}
