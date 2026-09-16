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
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/auth/auth_service.dart';
import 'package:front_porch_ai/services/web/facade/facades.dart';
import 'package:front_porch_ai/services/web/server_bootstrap.dart';
import 'package:front_porch_ai/services/web/streaming/stream_hub.dart';
import 'package:front_porch_ai/services/web/tunnels/tunnels.dart';
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

  /// Bumped by every [start] and every [stop]. `startSafely` time-boxes start
  /// with `Future.timeout`, which does NOT cancel the awaited work — it only
  /// completes the caller's future early. Without this counter a start that
  /// timed out (or was stopped mid-bind) would go on to publish a live socket
  /// AFTER the caller had already persisted "disabled" and reported failure,
  /// leaving the app listening with the UI insisting it is off. A run that
  /// finds the generation moved on closes what it just opened and exits.
  int _startGeneration = 0;

  // Realism-eval overlay streaming: a ChatService listener that pushes the
  // accumulating eval text over the hub while the Realism Engine is thinking, so
  // the web shows the same live "processing" overlay the desktop does. Stored so
  // we can detach it on stop().
  VoidCallback? _realismListener;
  bool _wasEvaluatingRealism = false;
  bool _wasAwaitingChanceTime = false;
  bool _wasPendingImageReview = false;
  // Throttle/dedupe state for the processing broadcast: during evals every
  // ChatService notify (≤150ms apart) used to re-send the FULL accumulated
  // eval text — O(n²) bytes over the socket and a client re-render per frame,
  // which is a big part of the reported iPad stalls. Transitions always send;
  // text growth is rate-limited and unchanged payloads are skipped.
  DateTime _lastProcessingSent = DateTime.fromMillisecondsSinceEpoch(0);
  int _lastProcessingTextLen = -1;
  bool _lastProcessingVerifying = false;
  bool _lastProcessingObjective = false;

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
  VoidCallback? _llmReadyListener;
  bool? _lastLlmReady;
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

  /// Human-readable reason the last [startSafely] attempt failed, so the
  /// Settings toggle can tell the user WHY instead of a bare "failed" toast
  /// (release builds have no visible logs, which made these reports
  /// undiagnosable). Null after a successful start.
  String? get lastStartError => _lastStartError;
  String? _lastStartError;

  /// True when the last failure was a socket/bind problem — the class where
  /// "use a different port" is the one-tap fix the failure dialog offers.
  bool get lastStartPortConflict => _lastStartPortConflict;
  bool _lastStartPortConflict = false;

  /// Probe loopback for a free port near [port] so the failure dialog can
  /// offer "Use port N instead" without the user knowing what a port is.
  /// Best-effort: a later bind on all interfaces can still fail and will be
  /// reported through the same dialog.
  Future<int?> findFreePortNear(int port) async {
    for (var candidate = port + 1; candidate <= port + 20; candidate++) {
      try {
        final probe = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          candidate,
        );
        await probe.close();
        return candidate;
      } catch (_) {
        // Taken or reserved — keep walking.
      }
    }
    return null;
  }

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

  /// Injected from main.dart (mirrors the legacy setX wiring style), and again
  /// by `reopenAndRebindDatabase` after a database SWAP (backup restore,
  /// storage-root move, beta stable-DB import) — which CLOSES the old instance.
  ///
  /// Swapping the field alone was not enough: `start()` copies the handle into
  /// the shelf handler, every facade and the memoized [AuthService], so a live
  /// server kept querying the closed database and 500'd on every request —
  /// including login, because the memoized auth survived even a manual
  /// stop/start, leaving a full app restart as the only cure. So drop the
  /// memoized auth and bounce a running server onto the new handle.
  void setDatabase(AppDatabase db) {
    if (identical(_db, db)) return;
    _db = db;
    _auth = null;
    if (!isRunning) return;
    final port = _server!.port;
    // The rebind callers are synchronous, so the bounce runs detached. A
    // failure is reported the same way a failed Settings start is, rather than
    // swallowed: the server ends up stopped with lastStartError set.
    unawaited(() async {
      try {
        await stop();
        await start(port);
        _lastStartError = null;
        _lastStartPortConflict = false;
      } catch (e) {
        _lastStartError = describeStartFailure(e, port);
        _lastStartPortConflict = e is SocketException;
        debugPrint(
          '[WebServerHost] Restart after the database was swapped failed: $e',
        );
        try {
          await stop();
        } catch (_) {}
        notifyListeners();
      }
    }());
  }

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
          final verifying = chatService.isVerifyingRealism;
          final text = chatService.realismEvalStreamTextClean;
          final now = DateTime.now();
          // A phase transition (eval started, verifier flipped, objective
          // phase joined) always sends; otherwise only send when the eval
          // text actually grew AND the 300ms window elapsed. This turns the
          // ~6.6 full-payload frames/s of a long local eval into ≤3 delta-
          // worthy ones and drops the identical re-broadcasts entirely.
          final transition =
              !_wasEvaluatingRealism ||
              verifying != _lastProcessingVerifying ||
              objective != _lastProcessingObjective;
          final textChanged = text.length != _lastProcessingTextLen;
          if (transition ||
              (textChanged &&
                  now.difference(_lastProcessingSent).inMilliseconds >= 300)) {
            _lastProcessingSent = now;
            _lastProcessingTextLen = text.length;
            _lastProcessingVerifying = verifying;
            _lastProcessingObjective = objective;
            streamHub.broadcast({
              'event': 'processing',
              'active': true,
              'realism': realism,
              'objective': objective,
              'greeting': chatService.isProcessingGreeting,
              'verifying': verifying,
              'text': text,
            });
          }
        } else if (_wasEvaluatingRealism) {
          _lastProcessingTextLen = -1;
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

    // Composer "No API connection" placeholder — push chat_updated only when
    // the connection flag flips (not on one-off request failures).
    final llm = _llmProvider;
    if (streamHub != null && llm != null) {
      void onLlmReady() {
        final ready = llm.activeService.isReady;
        if (_lastLlmReady == ready) return;
        _lastLlmReady = ready;
        streamHub.broadcastChatUpdate();
      }

      _llmReadyListener = onLlmReady;
      _lastLlmReady = llm.activeService.isReady;
      llm.addListener(onLlmReady);
      llm.openRouterService.addListener(onLlmReady);
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

    final characterFacade = CharacterFacade(
      db,
      _storage,
      _folderService,
      chatService,
      _characterRepository,
    );

    // Library live-sync: broadcast a single debounced `library_changed` whenever
    // characters, folders or groups change (from the desktop or a web client),
    // so every browser refreshes its library near-instantly. Debounced ~150ms to
    // coalesce the multiple notifies a single op can fire (e.g. an import).
    if (streamHub != null) {
      void onLibraryChanged() {
        // Undebounced: the refetch this broadcast triggers must not be served
        // from a memo that predates the change, or a swapped portrait would
        // keep its old `v=` token and stay cached in the browser.
        characterFacade.invalidateAvatarVersions();
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
      _lastStartError = null;
      _lastStartPortConflict = false;
      return isRunning;
    } catch (e) {
      _lastStartError = describeStartFailure(e, port);
      _lastStartPortConflict = e is SocketException;
      debugPrint('[WebServerHost] Web server start failed: $e — disabling.');
      await settings.setWebServerStarting(false);
      await settings.setWebServerEnabled(false);
      try {
        await stop();
      } catch (_) {}
      return false;
    }
  }

  /// Turn a [startSafely] failure into an actionable one-liner. The two big
  /// prod classes are port conflicts (another app — or a second running copy
  /// of Front Porch AI, e.g. stable + nightly — camping the fixed port) and
  /// Windows reserved-port ranges (Hyper-V/WSL exclusions make bind fail with
  /// access-denied on an apparently free port). Static + pure for testing.
  static String describeStartFailure(Object e, int port) {
    // Copy is written for NON-technical users (maintainer directive
    // 2026-08-04): say what happened and what to press, no networking
    // knowledge assumed. Keep the anchor phrases the start-failure test
    // asserts ('already in use', 'second running copy', 'refused access',
    // 'timed out').
    if (e is TimeoutException) {
      return 'Starting timed out (it took too long, so the app stopped '
          'waiting to keep itself responsive). This is usually temporary — '
          'try again.';
    }
    if (e is SocketException) {
      // EADDRINUSE: macOS 48, Linux 98, Windows 10048. The "shared flag"
      // message is Dart's in-process flavor of the same collision (two binds
      // from one process — e.g. overlapping start() calls).
      // EACCES: 13 (Unix), 10013 (Windows reserved port ranges).
      final code = e.osError?.errorCode;
      final msg = '${e.message} ${e.osError?.message ?? ''}'.toLowerCase();
      if (code == 48 ||
          code == 98 ||
          code == 10048 ||
          msg.contains('already in use') ||
          msg.contains('shared flag')) {
        return 'Its "door number" (port $port) is already in use by another '
            'program on this computer — usually a second running copy of '
            'Front Porch AI. Close the other program, or let the app switch '
            'to a free one.';
      }
      if (code == 13 || code == 10013 || msg.contains('access')) {
        return 'This computer refused access to door number (port) $port — '
            'Windows sometimes reserves numbers for itself. Switching to a '
            'different one fixes this.';
      }
      return 'Could not open port $port: ${e.osError?.message ?? e.message}';
    }
    return 'Start failed: $e';
  }

  Future<void> stop() async {
    // Disown any start still in flight FIRST — before the early return below,
    // which is exactly the case a start that has not reached its bind yet hits
    // (nothing wired, no server): otherwise its socket would surface after we
    // returned. See [_startGeneration].
    _startGeneration++;
    final server = _server;
    // `start()` attaches every listener, the 1s heartbeat timer, the StreamHub
    // (which subscribes to the token stream in its constructor) and the
    // TunnelManager BEFORE it binds — so a failed bind (EADDRINUSE, the
    // stable+nightly case describeStartFailure is written for) leaves all of
    // that attached with `_server` still null. `startSafely`'s catch calls
    // stop() to tear the half-started state down, so returning early on a null
    // server leaked one full set of listeners/timer/hub per failed attempt,
    // permanently (the next attempt overwrites the fields without detaching).
    // Bail only when there is genuinely nothing left to release.
    final wired =
        _streamHub != null ||
        _tunnelManager != null ||
        _realismListener != null ||
        _genStatusListener != null ||
        _llmReadyListener != null ||
        _imageProgressListener != null ||
        _libraryListener != null ||
        _genStatusTicker != null ||
        _libraryDebounce != null;
    if (server == null && !wired) return;
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
    if (_llmReadyListener != null) {
      _llmProvider?.removeListener(_llmReadyListener!);
      _llmProvider?.openRouterService.removeListener(_llmReadyListener!);
      _llmReadyListener = null;
    }
    _lastLlmReady = null;
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
    await server?.close(force: true);
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
