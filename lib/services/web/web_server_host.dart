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

part 'web_server_host.streams.dart';
part 'web_server_host.wiring.dart';

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

  // Public notify for same-library extensions (avoids protected member warnings).
  void notify() => notifyListeners();

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
}
