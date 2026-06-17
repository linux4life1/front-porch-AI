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
import 'package:front_porch_ai/app_version.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:math';

import 'package:uuid/uuid.dart';

import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

// Barrel imports for high-frequency services and models
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';

// Items not in the curated services barrel (internal, low-frequency, or sidecar)
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/web_chat_bridge.dart';
import 'package:front_porch_ai/services/byaf_service.dart';
import 'package:front_porch_ai/services/embedding_sidecar.dart';
import 'package:front_porch_ai/services/cloud_providers/webdav_provider.dart';
import 'package:front_porch_ai/services/cloud_providers/google_drive_provider.dart';
import 'package:front_porch_ai/models/story_project.dart' as story_model;
import 'package:drift/drift.dart' show Value;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'web_server/routes/character_routes.dart';
import 'web_server/routes/chat_routes.dart';

// Stage 6 web server extraction (internal submodules; direct imports)
import 'package:front_porch_ai/services/web_server/middleware/cors_middleware.dart';
import 'package:front_porch_ai/services/web_server/middleware/auth_middleware.dart';
import 'package:front_porch_ai/services/web_server/middleware/client_tracker.dart';
import 'package:front_porch_ai/services/web_server/routes/auth_routes.dart';
import 'package:front_porch_ai/services/web_server/helpers/web_asset_server.dart';
import 'package:front_porch_ai/services/web_server/helpers/image_cache.dart';
import 'package:front_porch_ai/services/web_server/sse/chargen_stream.dart';
import 'package:front_porch_ai/services/web_server/sse/story_pipeline_stream.dart';

/// Embedded HTTP server that serves the web UI and REST API.
///
/// When a remote client connects (any authenticated API request),
/// [hasActiveClient] is set to `true`, which causes the Flutter desktop
/// app to display a lock overlay.

/// Cached Intel Mac detection (matches BackendManager logic).
bool? _isIntelMacCached;
bool _checkIsIntelMac() {
  if (_isIntelMacCached != null) return _isIntelMacCached!;
  if (!Platform.isMacOS) {
    _isIntelMacCached = false;
    return false;
  }
  try {
    final result = Process.runSync('uname', ['-m']);
    _isIntelMacCached =
        result.exitCode == 0 && result.stdout.toString().trim() != 'arm64';
  } catch (_) {
    _isIntelMacCached = false;
  }
  return _isIntelMacCached!;
}

class WebServerService extends ChangeNotifier {
  final StorageService _storageService;
  ChatService? _chatService;
  CharacterRepository? _characterRepository;
  AppDatabase? _db;
  WebChatBridge? _chatBridge;
  LLMProvider? _llmProvider;
  FolderService? _folderService;
  TtsService? _ttsService;
  UserPersonaService? _userPersonaService;
  GroupChatRepository? _groupChatRepository;
  CloudSyncService? _cloudSyncService;
  ImageGenService? _imageGenService;
  EmbeddingSidecar? _embeddingSidecar;
  StoryRepository? _storyRepository;
  StoryPipelineService? _storyPipelineService;

  // ── Chargen SSE state ──
  final Set<StreamController<List<int>>> _chargenSseClients = {};

  // Chargen state for polling fallback
  String _chargenStatus = '';
  String _chargenPreview = '';
  Map<String, dynamic>? _chargenCompletedCard;
  String? _chargenError;
  bool _isChargenRunning = false;

  // ── Porch Stories SSE state ──
  final Set<StreamController<List<int>>> _storySseClients = {};
  String _storyStatus = '';
  String _storyStreamingText = '';
  bool _storyPipelineRunning = false;
  String? _storyCurrentId;

  HttpServer? _server;
  bool _isRunning = false;
  bool _hasActiveClient = false;
  String? _lanIp;
  String? _connectedClientIp;
  String? _connectedClientInfo;

  // ── Session-token auth ──
  final Map<String, DateTime> _activeSessions = {};

  bool get isRunning => _isRunning;
  bool get hasActiveClient => _hasActiveClient;
  String? get lanIp => _lanIp;
  int get port => _storageService.webServerPort;
  String? get connectedClientIp => _connectedClientIp;
  String? get connectedClientInfo => _connectedClientInfo;

  // Public accessors for extracted web_server/ submodules (Stage 6 extraction).
  // Minimal surface only; these are not "void _" private methods.
  // Keep reset/zero sites in sync with stop()/disconnectClient()/start() (see below).
  StorageService get storageService => _storageService;
  Map<String, DateTime> get activeSessions => _activeSessions;

  void markClientActive({String? ip, String? info}) {
    if (!_hasActiveClient) {
      _hasActiveClient = true;
      _connectedClientIp = ip;
      _connectedClientInfo = info;
      notifyListeners();
    }
  }

  // SSE state exposure for chargen_stream.dart / story_pipeline_stream.dart
  Set<StreamController<List<int>>> get chargenSseClients => _chargenSseClients;
  Set<StreamController<List<int>>> get storySseClients => _storySseClients;
  String get chargenStatus => _chargenStatus;
  String get chargenPreview => _chargenPreview;
  Map<String, dynamic>? get chargenCompletedCard => _chargenCompletedCard;
  String? get chargenError => _chargenError;
  bool get isChargenRunning => _isChargenRunning;
  String get storyStatus => _storyStatus;
  String get storyStreamingText => _storyStreamingText;
  bool get storyPipelineRunning => _storyPipelineRunning;
  String? get storyCurrentId => _storyCurrentId;

  WebServerService(this._storageService) {
    _detectLanIp();
  }

  /// Inject dependencies that aren't available at construction time.
  void setChatService(ChatService service) => _chatService = service;
  void setCharacterRepository(CharacterRepository repo) =>
      _characterRepository = repo;
  void setDatabase(AppDatabase db) => _db = db;
  void setChatBridge(WebChatBridge bridge) => _chatBridge = bridge;
  void setLLMProvider(LLMProvider provider) => _llmProvider = provider;
  void setFolderService(FolderService fs) => _folderService = fs;
  void setTtsService(TtsService tts) => _ttsService = tts;
  void setUserPersonaService(UserPersonaService ups) =>
      _userPersonaService = ups;
  void setGroupChatRepository(GroupChatRepository gcr) =>
      _groupChatRepository = gcr;
  void setCloudSyncService(CloudSyncService css) => _cloudSyncService = css;
  void setImageGenService(ImageGenService igs) => _imageGenService = igs;
  void setEmbeddingSidecar(EmbeddingSidecar es) => _embeddingSidecar = es;
  void setStoryRepository(StoryRepository sr) => _storyRepository = sr;
  void setStoryPipelineService(StoryPipelineService sps) =>
      _storyPipelineService = sps;

  // Thins for extracted route classes (Stage 6 registration lift; the core getters like storageService/activeSessions/markClientActive are in the public getters section above; bodies for remaining groups delegated here; full body excision follow-up per plan).
  // (Not void _ private methods.)

  // (chargen*/story* getters already present above for SSE leaves)
  // Delegate thins for remaining route groups (registrations lifted to *Routes classes; bodies stay in god for now).
  Future<shelf.Response> handleGetCharacters(shelf.Request request) =>
      _handleGetCharacters(request);
  Future<shelf.Response> handleGetAvatar(shelf.Request request, String id) =>
      _handleGetAvatar(request, id);
  Future<shelf.Response> handleGetSessions(shelf.Request request, String id) =>
      _handleGetSessions(request, id);
  Future<shelf.Response> handleGetCharacterDetail(
    shelf.Request request,
    String id,
  ) => _handleGetCharacterDetail(request, id);
  Future<shelf.Response> handleEditCharacter(
    shelf.Request request,
    String id,
  ) => _handleEditCharacter(request, id);
  Future<shelf.Response> handleUploadAvatar(shelf.Request request, String id) =>
      _handleUploadAvatar(request, id);
  Future<shelf.Response> handleUpdateEvolution(
    shelf.Request request,
    String id,
  ) => _handleUpdateEvolution(request, id);
  Future<shelf.Response> handleDeleteCharacter(
    shelf.Request request,
    String id,
  ) => _handleDeleteCharacter(request, id);
  Future<shelf.Response> handleExportCharacterPng(
    shelf.Request request,
    String id,
  ) => _handleExportCharacterPng(request, id);
  Future<shelf.Response> handleImportCharacter(shelf.Request request) =>
      _handleImportCharacter(request);
  Future<shelf.Response> handleGetDataBank(shelf.Request request, String id) =>
      _handleGetDataBank(request, id);
  Future<shelf.Response> handleCreateDataBankEntry(
    shelf.Request request,
    String id,
  ) => _handleCreateDataBankEntry(request, id);
  Future<shelf.Response> handleUpdateDataBankEntry(
    shelf.Request request,
    String id,
    String entryId,
  ) => _handleUpdateDataBankEntry(request, id, entryId);
  Future<shelf.Response> handleDeleteDataBankEntry(
    shelf.Request request,
    String id,
    String entryId,
  ) => _handleDeleteDataBankEntry(request, id, entryId);
  Future<shelf.Response> handleCreateCharacter(shelf.Request request) =>
      _handleCreateCharacter(request);
  // (chargen non-stream, groups, folders, generate, chat*, tts, settings, personas, backend, models, worlds, stories, image-gen, cloud, rag, backups, image-cache old, statics covered by helpers or thins as needed for the registration lift; add more public thins here if a leaf needs a specific _handle not yet exposed.)
  Future<shelf.Response> handleGetChatState(shelf.Request request) =>
      _handleGetChatState(request);
  Future<shelf.Response> handleSetAuthorNote(shelf.Request request) =>
      _handleSetAuthorNote(request);
  Future<shelf.Response> handleChatSelect(shelf.Request request) =>
      _handleChatSelect(request);
  Future<shelf.Response> handleChatSend(shelf.Request request) =>
      _handleChatSend(request);
  Future<shelf.Response> handleChatStop(shelf.Request request) =>
      _handleChatStop(request);
  Future<shelf.Response> handleChatRegenerate(shelf.Request request) =>
      _handleChatRegenerate(request);
  Future<shelf.Response> handleChatSession(shelf.Request request) =>
      _handleChatSession(request);
  Future<shelf.Response> handleChatSwipe(shelf.Request request) =>
      _handleChatSwipe(request);
  Future<shelf.Response> handleChatContinue(shelf.Request request) =>
      _handleChatContinue(request);
  Future<shelf.Response> handleChatEdit(shelf.Request request) =>
      _handleChatEdit(request);
  Future<shelf.Response> handleChatDelete(shelf.Request request) =>
      _handleChatDelete(request);
  Future<shelf.Response> handleChatImpersonate(shelf.Request request) =>
      _handleChatImpersonate(request);
  Future<shelf.Response> handleChatCycleGreeting(shelf.Request request) =>
      _handleChatCycleGreeting(request);
  Future<shelf.Response> handleChatFork(shelf.Request request) =>
      _handleChatFork(request);
  Future<shelf.Response> handleDeleteSession(shelf.Request request) =>
      _handleDeleteSession(request);
  Future<shelf.Response> handleChatStream(shelf.Request request) =>
      Future.value(_handleChatStream(request));
  Future<shelf.Response> handleGetSummary(shelf.Request request) =>
      _handleGetSummary(request);
  Future<shelf.Response> handleSetSummary(shelf.Request request) =>
      _handleSetSummary(request);
  Future<shelf.Response> handleSummaryPause(shelf.Request request) =>
      _handleSummaryPause(request);
  Future<shelf.Response> handleSummaryRegenerate(shelf.Request request) =>
      _handleSummaryRegenerate(request);

  // ─────────────────────────────────────────────────────────────────────
  // LAN IP detection
  // ─────────────────────────────────────────────────────────────────────

  Future<void> _detectLanIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.address.startsWith('192.168.') ||
              addr.address.startsWith('10.') ||
              addr.address.startsWith('172.')) {
            _lanIp = addr.address;
            notifyListeners();
            return;
          }
        }
      }
      if (interfaces.isNotEmpty && interfaces.first.addresses.isNotEmpty) {
        _lanIp = interfaces.first.addresses.first.address;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[WebServer] Failed to detect LAN IP: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // Server lifecycle
  // ─────────────────────────────────────────────────────────────────────

  Future<void> start([int? portOverride]) async {
    if (_isRunning) return;

    // Ensure a PIN is set — auto-generate if empty
    if (_storageService.webServerPin.isEmpty) {
      final pin = _generatePin();
      await _storageService.setWebServerPin(pin);
      debugPrint('[WebServer] Auto-generated PIN: $pin');
    }

    final bindPort = portOverride ?? _storageService.webServerPort;
    final router = Router();

    // ── Route classes (Stage 6 extraction) ──
    // Auth (login/logout/health/disconnect)
    AuthRoutes(this, router);

    // (Other groups: CharacterRoutes, ChatRoutes, ... wired the same way;
    // full per canonical plan. SSE last.)

    // Chargen non-stream would be in character_routes; streams below.

    // ── Character routes (registration lifted to CharacterRoutes per Stage 6 plan; bodies delegated via public thins) ──
    CharacterRoutes(this, router);

    // ── Chat routes (registration lifted to ChatRoutes per Stage 6 plan; bodies delegated via public thins) ──
    ChatRoutes(this, router);

    // ── TTS routes ──
    router.post('/api/tts/speak', _handleTtsSpeak);

    // ── Settings routes ──
    router.get('/api/settings', _handleGetSettings);
    router.post('/api/settings', _handleSetSettings);

    // ── Persona routes ──
    router.get('/api/personas', _handleGetPersonas);
    router.post('/api/personas/active', _handleSetActivePersona);
    router.post('/api/personas', _handleCreatePersona);
    router.post('/api/personas/update', _handleUpdatePersona);
    router.post('/api/personas/delete', _handleDeletePersona);

    // ── Character creation routes ──
    router.post('/api/characters/create', _handleCreateCharacter);

    // ── Backend status & control ──
    router.get('/api/backend/status', _handleBackendStatus);
    router.get('/api/backend/local-models', _handleListLocalModels);
    router.post('/api/backend/start', _handleStartKobold);
    router.post('/api/backend/stop', _handleStopKobold);

    // ── Model routes ──
    router.get('/api/models/list', _handleGetModelList);
    router.post('/api/models/test-connection', _handleTestConnection);

    // ── World routes ──
    router.get('/api/worlds', _handleGetWorlds);
    router.post('/api/worlds', _handleCreateWorld);
    router.post('/api/worlds/update', _handleUpdateWorld);
    router.post('/api/worlds/delete', _handleDeleteWorld);

    // ── Group chat routes ──
    router.get('/api/groups', _handleGetGroups);
    router.post('/api/groups/create', _handleCreateGroup);
    router.post('/api/groups/update', _handleUpdateGroup);
    router.post('/api/groups/delete', _handleDeleteGroup);
    router.post('/api/groups/select', _handleSelectGroup);
    router.post('/api/groups/fork', _handleForkToGroup);
    router.post('/api/groups/add-character', _handleGroupAddCharacter);
    router.post('/api/groups/remove-character', _handleGroupRemoveCharacter);
    router.post('/api/groups/set-next', _handleGroupSetNext);

    // ── AI generation route ──
    router.post('/api/generate', _handleGenerate);

    // ── Character generator (AI creator) routes ──
    router.post('/api/chargen/generate', _handleChargenGenerate);
    router.post('/api/chargen/describe', _handleChargenDescribe);
    router.post('/api/chargen/randomname', _handleChargenRandomName);
    router.get('/api/chargen/status', _handleChargenStatus);
    router.get('/api/chargen/stream', _handleChargenStream);
    router.post('/api/chargen/avatar', _handleChargenAvatar);
    router.post('/api/chargen/save', _handleChargenSave);
    router.post('/api/chargen/expand', _handleChargenExpand);

    // ── Image gen local proxy routes ──
    router.post('/api/image-gen/test-connection', _handleImgenTestConnection);
    router.get('/api/image-gen/local-models', _handleImgenLocalModels);
    router.get('/api/image-gen/loras', _handleImgenLoras);
    router.post('/api/image-gen/unload-model', _handleImgenUnloadModel);
    router.post('/api/image-gen/switch-model', _handleImgenSwitchModel);

    // ── Porch Stories routes ──
    router.get('/api/stories', _handleGetStories);
    router.post('/api/stories/create', _handleCreateStory);
    router.post('/api/stories/update', _handleUpdateStory);
    router.post('/api/stories/delete', _handleDeleteStory);
    router.get('/api/stories/<id>', _handleGetStory);
    router.post('/api/stories/<id>/pipeline/run', _handleRunPipelineStage);
    router.get('/api/stories/<id>/pipeline/stream', _handlePipelineStream);
    router.get('/api/stories/<id>/pipeline/status', _handlePipelineStatus);
    router.post('/api/stories/<id>/prose/edit', _handleProseEdit);
    router.post('/api/stories/<id>/distill', _handleDistillChatHistory);

    // ── Cloud sync routes ──
    router.get('/api/sync/status', _handleGetSyncStatus);
    router.post('/api/sync/config', _handleSetSyncConfig);
    router.post('/api/sync/test', _handleSyncTestConnection);
    router.post('/api/sync/now', _handleSyncNow);
    router.post('/api/sync/force-upload', _handleSyncForceUpload);
    router.post('/api/sync/purge', _handleSyncPurge);
    router.get('/api/sync/cloud-characters', _handleListCloudCharacters);
    router.post(
      '/api/sync/download-characters',
      _handleDownloadCloudCharacters,
    );

    // ── RAG sidecar routes ──
    router.get('/api/rag/status', _handleRagStatus);
    router.post('/api/rag/setup', _handleRagSetup);

    // ── Backup routes ──
    router.get('/api/backups', _handleGetBackups);
    router.post('/api/backups/create', _handleCreateBackup);
    router.post('/api/backups/restore', _handleRestoreBackup);
    router.post('/api/backups/delete', _handleDeleteBackup);

    // ── Folder routes ──
    router.get('/api/folders', _handleGetFolders);
    router.post('/api/folders/create', _handleCreateFolder);
    router.post('/api/folders/rename', _handleRenameFolder);
    router.post('/api/folders/delete', _handleDeleteFolder);
    router.post('/api/folders/add-character', _handleAddCharToFolder);
    router.post('/api/folders/remove-character', _handleRemoveCharFromFolder);

    // ── Image cache proxy ──
    router.get('/api/image-cache/check', _handleImageCacheCheck);
    router.get('/api/image-cache/serve', _handleImageCacheServe);

    // ── Static web assets (via helper) ──
    final assetServer = WebAssetServer(this);
    router.get('/', (shelf.Request request) => assetServer.serve('index.html'));
    router.get(
      '/css/<file|.*>',
      (shelf.Request request, String file) => assetServer.serve('css/$file'),
    );
    router.get(
      '/js/<file|.*>',
      (shelf.Request request, String file) => assetServer.serve('js/$file'),
    );
    router.get(
      '/img/<file|.*>',
      (shelf.Request request, String file) => assetServer.serve('img/$file'),
    );

    // Image cache routes (via helper; registered here for the ones not yet in full character/ routes)
    final imageCache = ImageCacheHelper(this);
    router.get('/api/image-cache/check', imageCache.check);
    router.get('/api/image-cache/serve', imageCache.serve);

    final handler = const shelf.Pipeline()
        .addMiddleware(CorsMiddleware().middleware)
        .addMiddleware(AuthMiddleware(this).middleware)
        .addMiddleware(ClientTracker(this).middleware)
        .addHandler(router.call);

    try {
      _server = await shelf_io.serve(handler, '0.0.0.0', bindPort);
      _server!.autoCompress = true;
      _isRunning = true;
      debugPrint('[WebServer] Listening on http://0.0.0.0:$bindPort');
      debugPrint('[WebServer] LAN access: http://$_lanIp:$bindPort');
      notifyListeners();
    } catch (e) {
      debugPrint('[WebServer] Failed to start: $e');
      _isRunning = false;
      notifyListeners();
    }

    // SSE (last per plan)
    ChargenStream(this, router);
    StoryPipelineStream(this, router);
  }

  /// Generate a random 6-digit PIN.
  String _generatePin() {
    final rng = Random.secure();
    return (100000 + rng.nextInt(900000)).toString();
  }

  // _authMiddleware (and related old auth middleware logic) extracted to middleware/auth_middleware.dart (Stage 6; deletion part of task). Old body removed; now wired via AuthMiddleware(this) in start().

  // Auth handlers (_handleLogin/_handleLogout/_handleHealth/_handleDisconnect + _generateSessionToken) extracted to routes/auth_routes.dart + middleware/auth_middleware.dart + helpers/route_utils.dart (Stage 6; deletion part of task). Bodies removed; old calls in start() already thinned to AuthRoutes(this, router).

  // ─────────────────────────────────────────────────────────────────────
  // Character API (remaining groups follow identical pattern; see auth_routes for example + plan)
  // ─────────────────────────────────────────────────────────────────────

  Future<shelf.Response> _handleGetCharacters(shelf.Request request) async {
    if (_db == null) {
      return _errorResponse(503, 'Database not available');
    }

    try {
      final query = request.url.queryParameters;
      final searchTerm = query['search']?.toLowerCase();
      final folderId = query['folder'];

      var characters = await _db!.getAllCharacters();

      // Fetch message counts per character (keyed by character DB id)
      final msgCounts = await _db!.getMessageCountsPerCharacter();

      // Apply search filter (bypasses folder filtering)
      if (searchTerm != null && searchTerm.isNotEmpty) {
        characters = characters.where((c) {
          if (c.name.toLowerCase().contains(searchTerm)) return true;
          final tags = _tryParseJsonList(c.tags);
          if (tags.any(
            (t) => t.toString().toLowerCase().contains(searchTerm),
          )) {
            return true;
          }
          return false;
        }).toList();
      } else {
        // Apply folder filter (only when not searching)
        if (folderId != null && folderId.isNotEmpty && _folderService != null) {
          // Use FolderService (same as desktop app) to find characters in folder
          final folderFilenames = _folderService!.getCharactersInFolder(
            folderId,
          );
          characters = characters
              .where(
                (c) =>
                    c.imagePath != null &&
                    folderFilenames.contains(_basename(c.imagePath!)),
              )
              .toList();
        } else if (folderId == null || folderId.isEmpty) {
          // Top level: show characters not in any folder
          if (_folderService != null) {
            final folderedPaths = _folderService!.getUnfolderedCharacterPaths();
            characters = characters
                .where(
                  (c) =>
                      c.imagePath == null ||
                      !folderedPaths.contains(_basename(c.imagePath!)),
                )
                .toList();
          }
        }
      }

      // Apply sort
      final sortMode = query['sort'] ?? 'name';
      switch (sortMode) {
        case 'name':
          characters.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
          break;
        case 'recent':
          // reversed so newest first — sort by updatedAt or leave as-is
          characters = characters.reversed.toList();
          break;
        case 'messages':
          // Sort by message count descending (most messages first)
          characters.sort((a, b) {
            final aCount = msgCounts[a.id] ?? 0;
            final bCount = msgCounts[b.id] ?? 0;
            return bCount.compareTo(aCount);
          });
          break;
      }

      final result = characters
          .map(
            (c) => {
              'id': c.id,
              'charId': (c.imagePath != null && c.imagePath!.isNotEmpty)
                  ? p.basenameWithoutExtension(c.imagePath!)
                  : c.name
                        .replaceAll(RegExp(r'[^\w\s]'), '')
                        .replaceAll(' ', '_'),
              'name': c.name,
              'description': c.description,
              'scenario': c.scenario,
              'personality': c.personality,
              'tags': _tryParseJsonList(c.tags),
              'hasAvatar': c.imagePath != null && c.imagePath!.isNotEmpty,
              'folderId': c.folderId ?? '',
              'messageCount': msgCounts[c.id] ?? 0,
            },
          )
          .toList();

      return shelf.Response.ok(
        jsonEncode(result),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to fetch characters: $e');
    }
  }

  Future<shelf.Response> _handleGetAvatar(
    shelf.Request request,
    String id,
  ) async {
    if (_db == null) return _errorResponse(503, 'Database not available');

    try {
      final character = await _db!.getCharacterById(id);
      if (character.imagePath == null || character.imagePath!.isEmpty) {
        return shelf.Response.notFound('No avatar');
      }

      // DB stores basename only — resolve to full local path
      final basename = p.basename(character.imagePath!);
      final fullPath = p.join(_storageService.charactersDir.path, basename);
      final file = File(fullPath);
      if (!file.existsSync()) {
        return shelf.Response.notFound('Avatar file not found');
      }

      return shelf.Response.ok(
        file.readAsBytesSync(),
        headers: {
          'Content-Type': 'image/png',
          'Cache-Control': 'public, max-age=3600',
        },
      );
    } catch (e) {
      return shelf.Response.notFound('Character not found');
    }
  }

  Future<shelf.Response> _handleGetSessions(
    shelf.Request request,
    String id,
  ) async {
    if (_db == null || _chatService == null) {
      return _errorResponse(503, 'Service not available');
    }

    try {
      final sessions = await _db!.getSessionsForCharacter(id);
      final result = <Map<String, dynamic>>[];

      for (final s in sessions) {
        final msgs = await _db!.getMessagesForSession(s.id);
        String preview = s.name ?? 'New Conversation';
        if (s.name == null && msgs.length > 1) {
          try {
            final swipes = List<String>.from(jsonDecode(msgs[1].swipes));
            preview = swipes.isNotEmpty ? swipes[msgs[1].swipeIndex] : '';
            if (preview.length > 80) preview = '${preview.substring(0, 80)}...';
          } catch (_) {}
        }

        result.add({
          'id': s.id,
          'name': s.name,
          'preview': preview,
          'messageCount': msgs.length,
          'createdAt': s.createdAt.toIso8601String(),
          'updatedAt': s.updatedAt.toIso8601String(),
        });
      }

      return shelf.Response.ok(
        jsonEncode(result),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to fetch sessions: $e');
    }
  }

  Future<shelf.Response> _handleGetCharacterDetail(
    shelf.Request request,
    String id,
  ) async {
    if (_db == null) return _errorResponse(503, 'Database not available');

    try {
      final c = await _db!.getCharacterById(id);
      List<dynamic> altGreetings = [];
      try {
        altGreetings = jsonDecode(c.alternateGreetings);
      } catch (_) {}
      List<dynamic> tags = [];
      try {
        tags = jsonDecode(c.tags);
      } catch (_) {}
      List<dynamic> worldNames = [];
      try {
        worldNames = jsonDecode(c.worldNames);
      } catch (_) {}
      Map<String, dynamic>? lorebook;
      if (c.lorebook != null) {
        try {
          final raw = jsonDecode(c.lorebook!);
          // Normalize DB format (keys array, comment) → frontend format (key string, name)
          if (raw is Map<String, dynamic> && raw['entries'] is List) {
            final entries = (raw['entries'] as List).map((e) {
              if (e is Map<String, dynamic>) {
                // Join keys array → comma-separated string
                String keyStr = '';
                if (e['keys'] is List) {
                  keyStr = (e['keys'] as List)
                      .map((k) => k.toString())
                      .join(', ');
                } else if (e['key'] is String) {
                  keyStr = e['key'] as String;
                }
                return {
                  'name':
                      e['comment']?.toString() ?? e['name']?.toString() ?? '',
                  'key': keyStr,
                  'content': e['content']?.toString() ?? '',
                  'enabled': e['enabled'] ?? true,
                  'constant': e['constant'] ?? false,
                  'stickyDepth': e['sticky_depth'] ?? e['insertion_order'] ?? 4,
                };
              }
              return e;
            }).toList();
            lorebook = {'entries': entries};
          } else {
            lorebook = raw;
          }
        } catch (_) {}
      }

      return shelf.Response.ok(
        jsonEncode({
          'id': c.id,
          'name': c.name,
          'description': c.description,
          'personality': c.personality,
          'scenario': c.scenario,
          'firstMessage': c.firstMessage,
          'mesExample': c.mesExample,
          'systemPrompt': c.systemPrompt,
          'postHistoryInstructions': c.postHistoryInstructions,
          'alternateGreetings': altGreetings,
          'tags': tags,
          'worldNames': worldNames,
          'lorebook': lorebook,
          'ttsVoice': c.ttsVoice,
          'imagePath': c.imagePath,
          // Evolution state is per-session — read from the active chat session if available
          'evolvedPersonality': _chatService?.getEffectivePersonality ?? '',
          'evolvedScenario': _chatService?.getEffectiveScenario ?? '',
          'evolutionCount': _chatService?.characterEvolutionCount ?? 0,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to get character: $e');
    }
  }

  Future<shelf.Response> _handleEditCharacter(
    shelf.Request request,
    String id,
  ) async {
    if (_db == null) return _errorResponse(503, 'Database not available');

    try {
      final body = jsonDecode(await request.readAsString());
      final character = await _db!.getCharacterById(id);

      final companion = CharactersCompanion(
        id: Value(character.id),
        name: Value(body['name']?.toString() ?? character.name),
        description: Value(
          body['description']?.toString() ?? character.description,
        ),
        scenario: Value(body['scenario']?.toString() ?? character.scenario),
        personality: Value(
          body['personality']?.toString() ?? character.personality,
        ),
        firstMessage: Value(
          body['firstMessage']?.toString() ?? character.firstMessage,
        ),
        mesExample: Value(
          body['mesExample']?.toString() ?? character.mesExample,
        ),
        systemPrompt: Value(
          body['systemPrompt']?.toString() ?? character.systemPrompt,
        ),
        postHistoryInstructions: Value(
          body['postHistoryInstructions']?.toString() ??
              character.postHistoryInstructions,
        ),
        alternateGreetings: Value(
          body.containsKey('alternateGreetings')
              ? jsonEncode(body['alternateGreetings'])
              : character.alternateGreetings,
        ),
        tags: Value(
          body.containsKey('tags') ? jsonEncode(body['tags']) : character.tags,
        ),
        imagePath: Value(
          character.imagePath != null ? p.basename(character.imagePath!) : null,
        ),
        ttsVoice: Value(character.ttsVoice),
        folderId: Value(character.folderId),
        lorebook: Value(
          body.containsKey('lorebook')
              ? _normalizeLorebookForDb(body['lorebook'])
              : character.lorebook,
        ),
        worldNames: Value(
          body.containsKey('worldNames')
              ? jsonEncode(body['worldNames'])
              : character.worldNames,
        ),
        createdAt: Value(character.createdAt),
        updatedAt: Value(DateTime.now()),
      );

      await _db!.updateCharacter(companion);

      // Also update the in-memory character in the repository
      if (_characterRepository != null) {
        await _characterRepository!.loadCharacters();
      }

      return shelf.Response.ok(
        jsonEncode({'status': 'ok'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to update character: $e');
    }
  }

  /// POST `/api/characters/<id>/avatar` — Upload a new avatar image.
  /// Body: `{ "data": "<base64 PNG>" }`
  Future<shelf.Response> _handleUploadAvatar(
    shelf.Request request,
    String id,
  ) async {
    if (_db == null) return _errorResponse(503, 'Database not available');

    try {
      final body = jsonDecode(await request.readAsString());
      final dataBase64 = body['data']?.toString() ?? '';
      if (dataBase64.isEmpty) {
        return _errorResponse(400, 'Base64 image data required');
      }

      final bytes = base64Decode(dataBase64);
      final character = await _db!.getCharacterById(id);

      // Save to charactersDir
      final charDir = _storageService.charactersDir;
      await charDir.create(recursive: true);

      final safeName = character.name
          .replaceAll(RegExp(r'[^\w\s-]'), '')
          .replaceAll(RegExp(r'\s+'), '_');
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filename = '${safeName}_$timestamp.png';
      final destPath = p.join(charDir.path, filename);
      await File(destPath).writeAsBytes(bytes);

      // Embed V2 card data (use the repository-fetched card so lorebooks + extensions survive avatar replacement)
      try {
        CharacterCard? fullCard;
        if (_characterRepository != null) {
          fullCard = await _characterRepository!.getCharacterCardById(id);
        }
        fullCard ??= CharacterCard(
          name: character.name,
          description: character.description,
          personality: character.personality,
          scenario: character.scenario,
          firstMessage: character.firstMessage,
          mesExample: character.mesExample,
          systemPrompt: character.systemPrompt,
          postHistoryInstructions: character.postHistoryInstructions,
          alternateGreetings: character.alternateGreetings.isNotEmpty
              ? List<String>.from(jsonDecode(character.alternateGreetings))
              : [],
          tags: character.tags.isNotEmpty
              ? List<String>.from(jsonDecode(character.tags))
              : [],
        );
        await V2CardService().saveCardAsPng(fullCard, destPath, destPath);
      } catch (e) {
        debugPrint('[WebServer] Failed to embed V2 card data: $e');
      }

      // Update character's imagePath in DB
      await _db!.updateCharacter(
        CharactersCompanion(
          id: Value(character.id),
          name: Value(character.name),
          description: Value(character.description),
          scenario: Value(character.scenario),
          personality: Value(character.personality),
          firstMessage: Value(character.firstMessage),
          mesExample: Value(character.mesExample),
          systemPrompt: Value(character.systemPrompt),
          postHistoryInstructions: Value(character.postHistoryInstructions),
          alternateGreetings: Value(character.alternateGreetings),
          tags: Value(character.tags),
          imagePath: Value(filename),
          ttsVoice: Value(character.ttsVoice),
          folderId: Value(character.folderId),
          lorebook: Value(character.lorebook),
          worldNames: Value(character.worldNames),
          createdAt: Value(character.createdAt),
          updatedAt: Value(DateTime.now()),
        ),
      );

      if (_characterRepository != null) {
        await _characterRepository!.loadCharacters();
      }

      return shelf.Response.ok(
        jsonEncode({'status': 'ok', 'filename': filename}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to upload avatar: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // Data Bank API
  // ─────────────────────────────────────────────────────────────────────

  /// GET `/api/characters/<id>/databank` — List all Data Bank entries.
  Future<shelf.Response> _handleGetDataBank(
    shelf.Request request,
    String id,
  ) async {
    if (_db == null) return _errorResponse(503, 'Database not available');

    try {
      final entries = await _db!.getDataBankEntriesForCharacter(id);
      final result = entries
          .map(
            (e) => {
              'id': e.id,
              'characterId': e.characterId,
              'title': e.title,
              'content': e.content,
              'createdAt': e.createdAt.toIso8601String(),
            },
          )
          .toList();
      return shelf.Response.ok(
        jsonEncode(result),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to get data bank: $e');
    }
  }

  /// POST `/api/characters/<id>/databank` — Create a new entry.
  Future<shelf.Response> _handleCreateDataBankEntry(
    shelf.Request request,
    String id,
  ) async {
    if (_db == null) return _errorResponse(503, 'Database not available');

    try {
      final body = jsonDecode(await request.readAsString());
      final title = body['title']?.toString() ?? 'Untitled';
      final content = body['content']?.toString() ?? '';
      final entryId =
          'db_${DateTime.now().millisecondsSinceEpoch}_${id.hashCode.abs()}';

      await _db!.insertDataBankEntry(
        DataBankEntriesCompanion(
          id: Value(entryId),
          characterId: Value(id),
          title: Value(title),
          content: Value(content),
        ),
      );
      return shelf.Response.ok(
        jsonEncode({'status': 'ok', 'id': entryId}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to create data bank entry: $e');
    }
  }

  /// POST `/api/characters/<id>/databank/<entryId>/update` — Update an entry.
  Future<shelf.Response> _handleUpdateDataBankEntry(
    shelf.Request request,
    String id,
    String entryId,
  ) async {
    if (_db == null) return _errorResponse(503, 'Database not available');

    try {
      final body = jsonDecode(await request.readAsString());
      await _db!.updateDataBankEntry(
        DataBankEntriesCompanion(
          id: Value(entryId),
          characterId: Value(id),
          title: Value(body['title']?.toString() ?? ''),
          content: Value(body['content']?.toString() ?? ''),
        ),
      );
      return shelf.Response.ok(
        jsonEncode({'status': 'ok'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to update data bank entry: $e');
    }
  }

  /// POST `/api/characters/<id>/databank/<entryId>/delete` — Delete an entry.
  Future<shelf.Response> _handleDeleteDataBankEntry(
    shelf.Request request,
    String id,
    String entryId,
  ) async {
    if (_db == null) return _errorResponse(503, 'Database not available');

    try {
      await _db!.deleteDataBankEntry(entryId);
      return shelf.Response.ok(
        jsonEncode({'status': 'ok'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to delete data bank entry: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // Chat API
  // ─────────────────────────────────────────────────────────────────────

  Future<shelf.Response> _handleGetChatState(shelf.Request request) async {
    if (_chatService == null) {
      return _errorResponse(503, 'Chat service not available');
    }

    final chat = _chatService!;
    final activeChar = chat.activeCharacter;

    final messagesJson = chat.messages.asMap().entries.map((entry) {
      final i = entry.key;
      final m = entry.value;
      return {
        'index': i,
        'sender': m.sender,
        'text': m.displayText,
        'isUser': m.isUser,
        'hasThinking': m.hasThinking,
        'thinkingContent': m.thinkingContent,
        'thinkingDurationMs': m.thinkingDurationMs,
        'swipeCount': m.swipes.length,
        'swipeIndex': m.swipeIndex,
        'characterId': m.characterId,
      };
    }).toList();

    // Greeting info for first message cycling
    int greetingIndex = chat.greetingIndex;
    int totalGreetings = 1;
    if (activeChar != null) {
      totalGreetings = activeChar.allGreetings.length;
    }

    // Active persona name for {{user}} replacement
    String userPersonaName = 'User';
    if (_userPersonaService != null) {
      userPersonaName = _userPersonaService!.persona.name;
    }

    // Collect lorebook entries with trigger state
    final lorebookEntries = <Map<String, dynamic>>[];
    if (activeChar != null && activeChar.lorebook != null) {
      for (final entry in activeChar.lorebook!.entries) {
        if (!entry.enabled) continue;
        lorebookEntries.add({
          'key': entry.key,
          'name': entry.displayName,
          'isTriggered': entry.isTriggered,
          'constant': entry.constant,
          'remainingDepth': entry.remainingDepth,
        });
      }
    }
    // Also include world lorebook entries via chat service's group characters
    if (chat.isGroupMode) {
      for (final ch in chat.groupCharacters) {
        if (ch.lorebook == null) continue;
        for (final entry in ch.lorebook!.entries) {
          if (!entry.enabled) continue;
          lorebookEntries.add({
            'key': entry.key,
            'name': '${ch.name}: ${entry.displayName}',
            'isTriggered': entry.isTriggered,
            'constant': entry.constant,
            'remainingDepth': entry.remainingDepth,
          });
        }
      }
    }

    return shelf.Response.ok(
      jsonEncode({
        'character': activeChar != null
            ? {'name': activeChar.name, 'id': activeChar.dbId}
            : null,
        'sessionId': chat.currentSessionId,
        'sessionName': chat.sessionName,
        'messages': messagesJson,
        'isGenerating': chat.isGenerating,
        'isGroupMode': chat.isGroupMode,
        'groupId': chat.activeGroup?.id,
        'groupMembers': chat.isGroupMode
            ? chat.groupCharacters.map((c) {
                final charId = c.imagePath != null
                    ? p.basenameWithoutExtension(c.imagePath!)
                    : c.name
                          .replaceAll(RegExp(r'[^\w\s]'), '')
                          .replaceAll(' ', '_');
                return {
                  'name': c.name,
                  'charId': charId,
                  'hasAvatar': c.imagePath != null && c.imagePath!.isNotEmpty,
                  'dbId': c.dbId,
                };
              }).toList()
            : null,
        'tokensPerSecond': chat.tokensPerSecond,
        'tokensGenerated': chat.tokensGenerated,
        'authorNote': chat.authorNote,
        'authorNoteDepth': chat.authorNoteStrength,
        'summary': chat.summary,
        'summaryLastIndex': chat.summaryLastIndex,
        'summaryPaused': chat.summaryPaused,
        'isSummaryGenerating': chat.isSummaryGenerating,
        'greetingIndex': greetingIndex,
        'totalGreetings': totalGreetings,
        'userPersonaName': userPersonaName,
        'lorebook': lorebookEntries,
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<shelf.Response> _handleSetAuthorNote(shelf.Request request) async {
    if (_chatService == null) {
      return _errorResponse(503, 'Chat service not available');
    }

    try {
      final body = jsonDecode(await request.readAsString());
      final note = body['authorNote']?.toString() ?? '';
      final strength = body['strength'] is int ? body['strength'] as int : null;
      _chatService!.setAuthorNote(note, strength: strength);
      return shelf.Response.ok(
        jsonEncode({'status': 'ok'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to set author note: $e');
    }
  }

  // ── Summary API ──

  Future<shelf.Response> _handleGetSummary(shelf.Request request) async {
    if (_chatService == null) {
      return _errorResponse(503, 'Chat service not available');
    }
    return shelf.Response.ok(
      jsonEncode({
        'summary': _chatService!.summary,
        'summaryLastIndex': _chatService!.summaryLastIndex,
        'paused': _chatService!.summaryPaused,
        'isGenerating': _chatService!.isSummaryGenerating,
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<shelf.Response> _handleSetSummary(shelf.Request request) async {
    if (_chatService == null) {
      return _errorResponse(503, 'Chat service not available');
    }
    try {
      final body = jsonDecode(await request.readAsString());
      final summary = body['summary']?.toString() ?? '';
      _chatService!.setSummary(summary);
      return shelf.Response.ok(
        jsonEncode({'status': 'ok'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to set summary: $e');
    }
  }

  Future<shelf.Response> _handleSummaryPause(shelf.Request request) async {
    if (_chatService == null) {
      return _errorResponse(503, 'Chat service not available');
    }
    try {
      final body = jsonDecode(await request.readAsString());
      final paused = body['paused'] == true;
      _chatService!.setSummaryPaused(paused);
      return shelf.Response.ok(
        jsonEncode({'status': 'ok', 'paused': paused}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to toggle summary pause: $e');
    }
  }

  Future<shelf.Response> _handleSummaryRegenerate(shelf.Request request) async {
    if (_chatService == null) {
      return _errorResponse(503, 'Chat service not available');
    }
    try {
      await _chatService!.forceSummaryUpdate();
      return shelf.Response.ok(
        jsonEncode({'status': 'ok'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to regenerate summary: $e');
    }
  }

  Future<shelf.Response> _handleChatSelect(shelf.Request request) async {
    if (_chatService == null || _characterRepository == null) {
      return _errorResponse(503, 'Service not available');
    }

    try {
      final body = jsonDecode(await request.readAsString());
      final characterId = body['characterId']?.toString();
      if (characterId == null) {
        return _errorResponse(400, 'characterId is required');
      }

      // Find the character card
      final card = _characterRepository!.characters
          .where((c) => c.dbId == characterId)
          .firstOrNull;
      if (card == null) {
        return _errorResponse(404, 'Character not found');
      }

      await _chatService!.setActiveCharacter(card);

      return shelf.Response.ok(
        jsonEncode({
          'status': 'ok',
          'character': card.name,
          'sessionId': _chatService!.currentSessionId,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to select character: $e');
    }
  }

  Future<shelf.Response> _handleChatSend(shelf.Request request) async {
    if (_chatService == null) {
      return _errorResponse(503, 'Chat service not available');
    }

    try {
      final body = jsonDecode(await request.readAsString());
      final text = body['text']?.toString();
      if (text == null || text.trim().isEmpty) {
        return _errorResponse(400, 'text is required');
      }

      // sendMessage is fire-and-forget — it starts generation async
      _chatService!.sendMessage(text);

      return shelf.Response.ok(
        jsonEncode({'status': 'ok'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to send message: $e');
    }
  }

  Future<shelf.Response> _handleChatStop(shelf.Request request) async {
    if (_chatService == null) {
      return _errorResponse(503, 'Chat service not available');
    }

    _chatService!.stopGeneration();
    return shelf.Response.ok(
      jsonEncode({'status': 'ok'}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<shelf.Response> _handleChatRegenerate(shelf.Request request) async {
    if (_chatService == null) {
      return _errorResponse(503, 'Chat service not available');
    }

    _chatService!.regenerateLastMessage();
    return shelf.Response.ok(
      jsonEncode({'status': 'ok'}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<shelf.Response> _handleChatSession(shelf.Request request) async {
    if (_chatService == null) {
      return _errorResponse(503, 'Chat service not available');
    }

    try {
      final body = jsonDecode(await request.readAsString());
      final sessionId = body['sessionId']?.toString();
      final action = body['action']?.toString();

      if (action == 'new') {
        await _chatService!.startNewChat();
      } else if (sessionId != null) {
        await _chatService!.loadSession(sessionId);
      } else {
        return _errorResponse(400, 'sessionId or action is required');
      }

      return shelf.Response.ok(
        jsonEncode({
          'status': 'ok',
          'sessionId': _chatService!.currentSessionId,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to switch session: $e');
    }
  }

  Future<shelf.Response> _handleChatSwipe(shelf.Request request) async {
    if (_chatService == null) {
      return _errorResponse(503, 'Chat service not available');
    }

    try {
      final body = jsonDecode(await request.readAsString());
      final messageIndex = body['messageIndex'] as int?;
      final direction = body['direction'] as int?;

      if (messageIndex == null || direction == null) {
        return _errorResponse(400, 'messageIndex and direction are required');
      }

      _chatService!.swipeMessage(messageIndex, direction);
      return shelf.Response.ok(
        jsonEncode({'status': 'ok'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to swipe: $e');
    }
  }

  Future<shelf.Response> _handleChatContinue(shelf.Request request) async {
    if (_chatService == null) {
      return _errorResponse(503, 'Chat service not available');
    }

    _chatService!.continueGeneration();
    return shelf.Response.ok(
      jsonEncode({'status': 'ok'}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<shelf.Response> _handleChatEdit(shelf.Request request) async {
    if (_chatService == null) {
      return _errorResponse(503, 'Chat service not available');
    }

    try {
      final body = jsonDecode(await request.readAsString());
      final index = body['index'] as int?;
      final text = body['text']?.toString();

      if (index == null || text == null) {
        return _errorResponse(400, 'index and text are required');
      }

      _chatService!.editMessage(index, text);
      return shelf.Response.ok(
        jsonEncode({'status': 'ok'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to edit message: $e');
    }
  }

  Future<shelf.Response> _handleChatDelete(shelf.Request request) async {
    if (_chatService == null) {
      return _errorResponse(503, 'Chat service not available');
    }

    try {
      final body = jsonDecode(await request.readAsString());
      final index = body['index'] as int?;

      if (index == null) {
        return _errorResponse(400, 'index is required');
      }

      _chatService!.deleteMessage(index);
      return shelf.Response.ok(
        jsonEncode({'status': 'ok'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to delete message: $e');
    }
  }

  Future<shelf.Response> _handleChatImpersonate(shelf.Request request) async {
    if (_chatService == null) {
      return _errorResponse(503, 'Chat service not available');
    }

    try {
      final body = jsonDecode(await request.readAsString());
      final prefix = body['prefix']?.toString() ?? '';
      String result = '';

      await _chatService!.impersonateUser(
        prefix: prefix,
        onToken: (accumulated) {
          result = accumulated;
        },
      );

      return shelf.Response.ok(
        jsonEncode({'status': 'ok', 'text': result}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to impersonate: $e');
    }
  }

  Future<shelf.Response> _handleChatCycleGreeting(shelf.Request request) async {
    if (_chatService == null) {
      return _errorResponse(503, 'Chat service not available');
    }

    try {
      final body = jsonDecode(await request.readAsString());
      final direction = body['direction'] as int? ?? 1;

      await _chatService!.cycleGreeting(direction);
      return shelf.Response.ok(
        jsonEncode({
          'status': 'ok',
          'greetingIndex': _chatService!.greetingIndex,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to cycle greeting: $e');
    }
  }

  Future<shelf.Response> _handleChatFork(shelf.Request request) async {
    if (_chatService == null) {
      return _errorResponse(503, 'Chat service not available');
    }

    try {
      final body = jsonDecode(await request.readAsString());
      final index = body['index'] as int?;

      if (index == null) {
        return _errorResponse(400, 'index is required');
      }

      await _chatService!.forkFromMessage(index);
      return shelf.Response.ok(
        jsonEncode({'status': 'ok'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to fork: $e');
    }
  }

  Future<shelf.Response> _handleDeleteSession(shelf.Request request) async {
    if (_chatService == null || _db == null) {
      return _errorResponse(503, 'Chat service not available');
    }

    try {
      final body = jsonDecode(await request.readAsString());
      final sessionId = body['sessionId'] as String?;

      if (sessionId == null || sessionId.isEmpty) {
        return _errorResponse(400, 'sessionId is required');
      }

      // Delete the session
      await _db!.deleteSessionById(sessionId);

      // If it was the active session, start a new one
      if (_chatService!.currentSessionId == sessionId) {
        await _chatService!.startNewChat();
      }

      return shelf.Response.ok(
        jsonEncode({'status': 'ok'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to delete session: $e');
    }
  }

  /// SSE streaming endpoint — pushes real-time token events to the web client.
  shelf.Response _handleChatStream(shelf.Request request) {
    if (_chatBridge == null) {
      return _errorResponse(503, 'Chat bridge not available');
    }

    final sseStream = _chatBridge!.addClient();

    return shelf.Response.ok(
      sseStream,
      headers: {
        'Content-Type': 'text/event-stream; charset=utf-8',
        'Cache-Control': 'no-cache',
        'Connection': 'keep-alive',
        'Access-Control-Allow-Origin': '*',
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // TTS API
  // ─────────────────────────────────────────────────────────────────────

  Future<shelf.Response> _handleTtsSpeak(shelf.Request request) async {
    if (_ttsService == null) {
      return _errorResponse(503, 'TTS service not available');
    }

    try {
      final body = jsonDecode(await request.readAsString());
      final text = body['text']?.toString();
      String? voiceKey = body['voiceKey']?.toString();

      if (text == null || text.isEmpty) {
        return _errorResponse(400, 'text is required');
      }

      // If no voice key, try to use the active character's TTS voice
      if ((voiceKey == null || voiceKey.isEmpty) && _chatService != null) {
        final sender = body['sender']?.toString();
        if (_chatService!.activeGroup != null && sender != null) {
          final charMatch = _chatService!.groupCharacters
              .where((c) => c.name == sender)
              .firstOrNull;
          voiceKey = charMatch?.ttsVoice;
        } else {
          voiceKey = _chatService!.activeCharacter?.ttsVoice;
        }
      }

      final wavFile = await _ttsService!.generateAudioFile(
        text,
        voiceKey: voiceKey,
      );
      if (wavFile == null) {
        return _errorResponse(
          500,
          'Failed to generate audio. Check TTS configuration.',
        );
      }

      final bytes = await wavFile.readAsBytes();
      // Clean up the temp file after reading
      try {
        await wavFile.delete();
      } catch (_) {}

      return shelf.Response.ok(
        bytes,
        headers: {
          'Content-Type': 'audio/wav',
          'Content-Length': bytes.length.toString(),
        },
      );
    } catch (e) {
      return _errorResponse(500, 'TTS failed: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // Settings API
  // ─────────────────────────────────────────────────────────────────────

  shelf.Response _handleGetSettings(shelf.Request request) {
    try {
      final s = _storageService;
      return shelf.Response.ok(
        jsonEncode({
          // General
          'systemPrompt': s.generationSettings.systemPrompt,
          'textScale': s.uiSettings.textScale,
          // TTS
          'ttsEnabled': s.ttsSettings.ttsEnabled,
          'ttsEngine': s.ttsSettings.ttsEngine,
          'ttsVoice': s.ttsSettings.ttsVoiceModel,
          'ttsSpeechRate': s.ttsSpeechRate,
          'ttsAutoPlay': s.ttsAutoPlay,
          'ttsConcurrency': s.ttsConcurrency,
          'openaiTtsApiKey': s.openaiTtsApiKey.isNotEmpty ? '••••' : '',
          'openaiTtsApiKeySet': s.openaiTtsApiKey.isNotEmpty,
          'openaiTtsModel': s.openaiTtsModel,
          'elevenlabsApiKey': s.elevenlabsApiKey.isNotEmpty ? '••••' : '',
          'elevenlabsApiKeySet': s.elevenlabsApiKey.isNotEmpty,
          'elevenlabsModel': s.elevenlabsModel,
          'elevenlabsStability': s.elevenlabsStability,
          'elevenlabsSimilarity': s.elevenlabsSimilarity,
          'elevenlabsStyle': s.elevenlabsStyle,
          'ttsNarrateQuotedOnly': s.ttsNarrateQuotedOnly,
          'ttsIgnoreAsterisks': s.ttsIgnoreAsterisks,
          'ttsReplaceCurlyQuotes': s.ttsReplaceCurlyQuotes,
          // TTS available voices
          'ttsVoices': _ttsService != null
              ? _ttsService!.activeVoices
                    .map((v) => {'id': v.id, 'name': v.name})
                    .toList()
              : [],
          // Image Gen
          'imageGenEnabled': s.imageGenSettings.imageGenEnabled,
          'imageGenModel': s.imageGenModel,
          'imageGenBackend': s.imageGenBackend,
          'localImageGenUrl': s.localImageGenUrl,
          'imageGenSize': s.imageGenSize,
          'imageGenStyle': s.imageGenStyle,
          'imageGenNegativePrompt': s.imageGenNegativePrompt,
          // Draw Things gRPC specific (for remote/web control)
          'drawThingsGrpcHost': s.drawThingsGrpcHost,
          'drawThingsGrpcPort': s.drawThingsGrpcPort,
          'drawThingsSampler': s.drawThingsSampler,
          'drawThingsShift': s.drawThingsShift,
          'drawThingsStrength': s.drawThingsStrength,
          'drawThingsSeedMode': s.drawThingsSeedMode,
          'drawThingsTeaCache': s.drawThingsTeaCache,
          'drawThingsCfgZeroStar': s.drawThingsCfgZeroStar,
          // Samplers
          'temperature': s.generationSettings.temperature,
          'minP': s.generationSettings.minP,
          'maxTokens': s.generationSettings.maxLength,
          'minTokens': s.generationSettings.minLength,
          'repetitionPenalty': s.generationSettings.repeatPenalty,
          'repeatPenaltyTokens': s.generationSettings.repeatPenaltyTokens,
          'xtcThreshold': s.generationSettings.xtcThreshold,
          'xtcProbability': s.generationSettings.xtcProbability,
          'contextSize': s.backendSettings.contextSize,
          'dynamicTempEnabled': s.generationSettings.dynamicTempEnabled,
          'dynamicTempRange': s.generationSettings.dynamicTempRange,
          'stopSequences': s.generationSettings.stopSequences,
          // Backend / API — prefer runtime values from LLMProvider
          'activeBackend': s.backendSettings.backendType,
          'apiKey': s.backendSettings.remoteApiKey.isNotEmpty
              ? '••••${s.backendSettings.remoteApiKey.length > 4 ? s.backendSettings.remoteApiKey.substring(s.backendSettings.remoteApiKey.length - 4) : ''}'
              : '',
          'apiKeySet': s.backendSettings.remoteApiKey.isNotEmpty,
          'apiModel':
              _llmProvider?.openRouterService.modelName.isNotEmpty == true
              ? _llmProvider!.openRouterService.modelName
              : s.backendSettings.remoteModelName,
          'apiUrl': s.backendSettings.remoteApiUrl,
          // Reasoning
          'reasoningEnabled': s.backendSettings.reasoningEnabled,
          'reasoningEffort': s.reasoningEffort,
          // Web server
          'webServerPort': s.webServerSettings.webServerPort,
          'webServerEnabled': s.webServerSettings.webServerEnabled,
          'webServerPin': s.webServerSettings.webServerPin,
          // Backend runtime state
          'koboldRunning': _llmProvider?.koboldService.isRunning ?? false,
          'koboldReady': _llmProvider?.koboldService.isReady ?? false,
          'isIntelMac': _checkIsIntelMac(),
          // RAG / Memory
          'ragEnabled': s.ragEnabled,
          'ragRetrievalCount': s.ragRetrievalCount,
          'ragWindowSize': s.ragWindowSize,
          // Auto-persona
          'autoPersonaEnabled': s.autoPersonaEnabled,
          'autoPersonaInterval': s.autoPersonaInterval,
          // Character evolution
          'characterEvolutionEnabled': s.characterEvolutionEnabled,
          'evolutionInterval': s.evolutionInterval,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to fetch settings: $e');
    }
  }

  shelf.Response _handleBackendStatus(shelf.Request request) {
    try {
      final kobold = _llmProvider?.koboldService;
      return shelf.Response.ok(
        jsonEncode({
          'running': kobold?.isRunning ?? false,
          'ready': kobold?.isReady ?? false,
          'modelReady': kobold?.modelReady ?? false,
          'loadingStatus': kobold?.modelLoadingStatus ?? '',
          'activeBackend': _storageService.backendType,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to check backend status: $e');
    }
  }

  /// GET /api/backend/local-models — List .gguf model files.
  shelf.Response _handleListLocalModels(shelf.Request request) {
    try {
      final modelsDir = _storageService.modelsDir;
      final lastUsed = _storageService.lastUsedModelPath ?? '';
      if (!modelsDir.existsSync()) {
        return shelf.Response.ok(
          jsonEncode({
            'models': [],
            'modelsDir': modelsDir.path,
            'lastUsedPath': lastUsed,
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }
      final files =
          modelsDir
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.toLowerCase().endsWith('.gguf'))
              .toList()
            ..sort(
              (a, b) => p
                  .basename(a.path)
                  .toLowerCase()
                  .compareTo(p.basename(b.path).toLowerCase()),
            );

      final models = files.map((f) {
        final sizeBytes = f.lengthSync();
        final sizeGB = (sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1);
        return {
          'path': f.path,
          'name': p.basename(f.path),
          'sizeGB': sizeGB,
          'sizeBytes': sizeBytes,
        };
      }).toList();

      return shelf.Response.ok(
        jsonEncode({
          'models': models,
          'modelsDir': modelsDir.path,
          'lastUsedPath': lastUsed,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to list local models: $e');
    }
  }

  /// POST /api/backend/start — Start KoboldCpp with a local model (non-blocking).
  Future<shelf.Response> _handleStartKobold(shelf.Request request) async {
    if (_llmProvider == null) {
      return _errorResponse(503, 'LLM provider not available');
    }

    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final modelPath = body['modelPath']?.toString() ?? '';
      if (modelPath.isEmpty) {
        return _errorResponse(400, 'modelPath is required');
      }

      final kobold = _llmProvider!.koboldService;
      final s = _storageService;

      // Stop if currently running
      if (kobold.isRunning) {
        await kobold.stopKobold();
        await Future.delayed(const Duration(milliseconds: 500));
      }

      // Find executable
      final binDir = s.binDir;
      String? execPath;
      if (binDir.existsSync()) {
        for (final f in binDir.listSync()) {
          if (f is File &&
              (f.path.contains('koboldcpp') || f.path.contains('KoboldCpp'))) {
            execPath = f.path;
            break;
          }
        }
      }

      if (execPath == null) {
        return _errorResponse(
          404,
          'KoboldCpp executable not found in ${binDir.path}',
        );
      }

      // Start KoboldCpp (non-blocking — returns immediately)
      await kobold.startKobold(
        execPath,
        modelPath,
        kcppsPath: s.backendSettings.activeKcppsPath,
        port: 5001,
        gpuLayers: s.backendSettings.gpuLayers,
        contextSize: s.backendSettings.contextSize,
        useVulkan: s.backendSettings.useVulkan ?? false,
        useCublas: s.backendSettings.useCublas ?? false,
        useMetal: s.backendSettings.useMetal ?? false,
        useRocm: s.backendSettings.useRocm ?? false,
      );

      // Save as last used model
      await s.setLastUsedModelPath(modelPath);

      // Return immediately — client should poll /api/backend/status for readiness
      return shelf.Response.ok(
        jsonEncode({
          'status': 'starting',
          'message':
              'KoboldCpp is starting. Poll /api/backend/status for readiness.',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to start KoboldCpp: $e');
    }
  }

  /// POST /api/backend/stop — Stop KoboldCpp.
  Future<shelf.Response> _handleStopKobold(shelf.Request request) async {
    if (_llmProvider == null) {
      return _errorResponse(503, 'LLM provider not available');
    }

    try {
      final kobold = _llmProvider!.koboldService;
      if (kobold.isRunning) {
        await kobold.stopKobold();
      }
      return shelf.Response.ok(
        jsonEncode({'status': 'stopped'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to stop KoboldCpp: $e');
    }
  }

  Future<shelf.Response> _handleSetSettings(shelf.Request request) async {
    try {
      final body = jsonDecode(await request.readAsString());
      final s = _storageService;

      // General
      if (body.containsKey('systemPrompt')) {
        await s.generationSettings.setSystemPrompt(
          body['systemPrompt'].toString(),
        );
      }
      if (body.containsKey('textScale')) {
        await s.setTextScale((body['textScale'] as num).toDouble());
      }

      // TTS
      if (body.containsKey('ttsEnabled')) {
        await s.ttsSettings.setTtsEnabled(body['ttsEnabled'] as bool);
      }
      if (body.containsKey('ttsEngine')) {
        await s.setTtsEngine(body['ttsEngine'].toString());
      }
      if (body.containsKey('ttsVoice')) {
        await s.setTtsVoiceModel(body['ttsVoice'].toString());
      }
      if (body.containsKey('ttsSpeechRate')) {
        await s.setTtsSpeechRate((body['ttsSpeechRate'] as num).toDouble());
      }
      if (body.containsKey('ttsAutoPlay')) {
        await s.setTtsAutoPlay(body['ttsAutoPlay'] as bool);
      }
      if (body.containsKey('ttsConcurrency')) {
        await s.setTtsConcurrency((body['ttsConcurrency'] as num).toInt());
      }
      if (body.containsKey('openaiTtsApiKey')) {
        await s.setOpenaiTtsApiKey(body['openaiTtsApiKey'].toString());
      }
      if (body.containsKey('openaiTtsModel')) {
        await s.setOpenaiTtsModel(body['openaiTtsModel'].toString());
      }
      if (body.containsKey('elevenlabsApiKey')) {
        await s.setElevenlabsApiKey(body['elevenlabsApiKey'].toString());
      }
      if (body.containsKey('elevenlabsModel')) {
        await s.setElevenlabsModel(body['elevenlabsModel'].toString());
      }
      if (body.containsKey('elevenlabsStability')) {
        await s.setElevenlabsStability(
          (body['elevenlabsStability'] as num).toDouble(),
        );
      }
      if (body.containsKey('elevenlabsSimilarity')) {
        await s.setElevenlabsSimilarity(
          (body['elevenlabsSimilarity'] as num).toDouble(),
        );
      }
      if (body.containsKey('elevenlabsStyle')) {
        await s.setElevenlabsStyle((body['elevenlabsStyle'] as num).toDouble());
      }
      if (body.containsKey('ttsNarrateQuotedOnly')) {
        await s.setTtsNarrateQuotedOnly(body['ttsNarrateQuotedOnly'] as bool);
      }
      if (body.containsKey('ttsIgnoreAsterisks')) {
        await s.setTtsIgnoreAsterisks(body['ttsIgnoreAsterisks'] as bool);
      }
      if (body.containsKey('ttsReplaceCurlyQuotes')) {
        await s.setTtsReplaceCurlyQuotes(body['ttsReplaceCurlyQuotes'] as bool);
      }

      // Image Gen
      // Security: validate/sanitize to mitigate SSRF (arbitrary http targets from web API body) + resource exhaustion/DoS on sidecars (kobold launch, drawthings gRPC, image gen).
      // - Local image urls/hosts: require loopback/localhost variants only (no arbitrary LAN/internet).
      // - Ports: clamp 1024-65535.
      // - Launch numerics (context/gpu/kv/ports/samplers/seedMode etc): strict safe clamps (context 512-32k, gpuLayers 0-99, kv 0-8, draw ports/samplers reasonable, seed -1 or 0-2^31-1 etc).
      // Other samplers/tts/remote urls have similar surface but primary per review was image + kobold launch params (now live via thins).
      // Errors: skip bad value (log); no 4xx here as this is internal control path, but prevents bad side effects.
      if (body.containsKey('imageGenEnabled')) {
        await s.setImageGenEnabled(body['imageGenEnabled'] as bool);
      }
      if (body.containsKey('imageGenModel')) {
        await s.setImageGenModel(body['imageGenModel'].toString());
      }
      if (body.containsKey('imageGenBackend')) {
        await s.setImageGenBackend(body['imageGenBackend'].toString());
      }
      if (body.containsKey('localImageGenUrl')) {
        final u = body['localImageGenUrl'].toString().trim();
        if (u.startsWith('http://127.0.0.1') ||
            u.startsWith('http://localhost') ||
            u.startsWith('http://[::1]')) {
          await s.setLocalImageGenUrl(u);
        } else {
          debugPrint(
            '[WebServer] rejected non-loopback localImageGenUrl for SSRF mitigation',
          );
        }
      }
      if (body.containsKey('drawThingsGrpcHost')) {
        final h = body['drawThingsGrpcHost'].toString().trim();
        if (h == '127.0.0.1' ||
            h == 'localhost' ||
            h == '[::1]' ||
            h == '0.0.0.0') {
          await s.setDrawThingsGrpcHost(h);
        } else {
          debugPrint('[WebServer] rejected non-local drawThingsGrpcHost');
        }
      }
      if (body.containsKey('drawThingsGrpcPort')) {
        final p = (body['drawThingsGrpcPort'] as num).toInt().clamp(
          1024,
          65535,
        );
        await s.setDrawThingsGrpcPort(p);
      }
      if (body.containsKey('drawThingsSampler')) {
        final smp = (body['drawThingsSampler'] as num).toInt().clamp(0, 30);
        await s.setDrawThingsSampler(smp);
      }
      if (body.containsKey('drawThingsShift')) {
        await s.setDrawThingsShift((body['drawThingsShift'] as num).toDouble());
      }
      if (body.containsKey('drawThingsStrength')) {
        final str = (body['drawThingsStrength'] as num).toDouble().clamp(
          0.0,
          1.0,
        );
        await s.setDrawThingsStrength(str);
      }
      if (body.containsKey('drawThingsSeedMode')) {
        final sm = (body['drawThingsSeedMode'] as num).toInt().clamp(0, 3);
        await s.setDrawThingsSeedMode(sm);
      }
      if (body.containsKey('drawThingsTeaCache')) {
        await s.setDrawThingsTeaCache(body['drawThingsTeaCache'] as bool);
      }
      if (body.containsKey('drawThingsCfgZeroStar')) {
        await s.setDrawThingsCfgZeroStar(body['drawThingsCfgZeroStar'] as bool);
      }
      if (body.containsKey('imageGenSize')) {
        await s.setImageGenSize(body['imageGenSize'].toString());
      }
      if (body.containsKey('imageGenStyle')) {
        await s.setImageGenStyle(body['imageGenStyle'].toString());
      }
      if (body.containsKey('imageGenNegativePrompt')) {
        await s.setImageGenNegativePrompt(
          body['imageGenNegativePrompt'].toString(),
        );
      }

      // Samplers
      if (body.containsKey('temperature')) {
        await s.generationSettings.setTemperature(
          (body['temperature'] as num).toDouble(),
        );
      }
      if (body.containsKey('minP')) {
        await s.generationSettings.setMinP((body['minP'] as num).toDouble());
      }
      if (body.containsKey('maxTokens')) {
        await s.setMaxLength((body['maxTokens'] as num).toInt());
      }
      if (body.containsKey('minTokens')) {
        await s.setMinLength((body['minTokens'] as num).toInt());
      }
      if (body.containsKey('repetitionPenalty')) {
        await s.setRepeatPenalty((body['repetitionPenalty'] as num).toDouble());
      }
      if (body.containsKey('repeatPenaltyTokens')) {
        await s.setRepeatPenaltyTokens(
          (body['repeatPenaltyTokens'] as num).toInt(),
        );
      }
      if (body.containsKey('xtcThreshold')) {
        await s.setXtcThreshold((body['xtcThreshold'] as num).toDouble());
      }
      if (body.containsKey('xtcProbability')) {
        await s.setXtcProbability((body['xtcProbability'] as num).toDouble());
      }
      if (body.containsKey('contextSize')) {
        final ctx = (body['contextSize'] as num).toInt().clamp(512, 32768);
        await s.backendSettings.setContextSize(ctx);
      }
      // Extend clamps for remaining launch numerics (gpuLayers 0-99, kv 0-8, blas 1-4096, gpuId 0-8) per re-review security.
      if (body.containsKey('gpuLayers')) {
        final gl = (body['gpuLayers'] as num).toInt().clamp(0, 99);
        await s.backendSettings.setGpuLayers(gl);
      }
      if (body.containsKey('kvQuantizationLevel')) {
        final kv = (body['kvQuantizationLevel'] as num).toInt().clamp(0, 8);
        await s.backendSettings.setKvQuantizationLevel(kv);
      }
      if (body.containsKey('blasBatchSize')) {
        final bs = (body['blasBatchSize'] as num).toInt().clamp(1, 4096);
        await s.backendSettings.setBlasBatchSize(bs);
      }
      if (body.containsKey('gpuId')) {
        final gid = (body['gpuId'] as num).toInt().clamp(0, 8);
        await s.backendSettings.setGpuId(gid);
      }
      if (body.containsKey('dynamicTempEnabled')) {
        await s.setDynamicTempEnabled(body['dynamicTempEnabled'] as bool);
      }
      if (body.containsKey('dynamicTempRange')) {
        await s.setDynamicTempRange(
          (body['dynamicTempRange'] as num).toDouble(),
        );
      }

      // Backend / API
      if (body.containsKey('activeBackend')) {
        await s.setBackendType(body['activeBackend'].toString());
      }
      if (body.containsKey('apiKey')) {
        await s.setRemoteApiKey(body['apiKey'].toString());
      }
      if (body.containsKey('apiModel')) {
        await s.setRemoteModelName(body['apiModel'].toString());
      }
      if (body.containsKey('apiUrl')) {
        await s.setRemoteApiUrl(body['apiUrl'].toString());
      }

      // Reasoning
      if (body.containsKey('reasoningEnabled')) {
        await s.setReasoningEnabled(body['reasoningEnabled'] as bool);
      }
      if (body.containsKey('reasoningEffort')) {
        await s.setReasoningEffort(body['reasoningEffort'].toString());
      }

      // Web Server
      if (body.containsKey('webServerPin')) {
        final newPin = body['webServerPin'].toString().trim();
        if (newPin.length >= 4) {
          await s.setWebServerPin(newPin);
        }
      }

      // RAG / Memory
      if (body.containsKey('ragEnabled')) {
        await s.setRagEnabled(body['ragEnabled'] as bool);
      }
      if (body.containsKey('ragRetrievalCount')) {
        await s.setRagRetrievalCount(
          (body['ragRetrievalCount'] as num).toInt(),
        );
      }
      if (body.containsKey('ragWindowSize')) {
        await s.setRagWindowSize((body['ragWindowSize'] as num).toInt());
      }

      // Auto-persona
      if (body.containsKey('autoPersonaEnabled')) {
        await s.setAutoPersonaEnabled(body['autoPersonaEnabled'] as bool);
      }
      if (body.containsKey('autoPersonaInterval')) {
        await s.setAutoPersonaInterval(
          (body['autoPersonaInterval'] as num).toInt(),
        );
      }

      // Character evolution
      if (body.containsKey('characterEvolutionEnabled')) {
        await s.setCharacterEvolutionEnabled(
          body['characterEvolutionEnabled'] as bool,
        );
      }
      if (body.containsKey('evolutionInterval')) {
        await s.setEvolutionInterval(
          (body['evolutionInterval'] as num).toInt(),
        );
      }

      return shelf.Response.ok(
        jsonEncode({'status': 'ok'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to update settings: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // Model API
  // ─────────────────────────────────────────────────────────────────────

  Future<shelf.Response> _handleGetModelList(shelf.Request request) async {
    if (_llmProvider == null) {
      return _errorResponse(503, 'LLM provider not available');
    }

    try {
      final models = await _llmProvider!.openRouterService
          .fetchAvailableModels();
      final result = models
          .map(
            (m) => ({
              'id': m.id,
              'name': m.name,
              'pricing': m.pricingLabel,
              'isFree': m.isFree,
            }),
          )
          .toList();

      return shelf.Response.ok(
        jsonEncode(result),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to fetch models: $e');
    }
  }

  Future<shelf.Response> _handleTestConnection(shelf.Request request) async {
    if (_llmProvider == null) {
      return _errorResponse(503, 'LLM provider not available');
    }

    try {
      final message = await _llmProvider!.openRouterService.testConnection();
      return shelf.Response.ok(
        jsonEncode({'message': message}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Connection test failed: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // Persona API
  // ─────────────────────────────────────────────────────────────────────

  Future<shelf.Response> _handleGetPersonas(shelf.Request request) async {
    if (_db == null) return _errorResponse(503, 'Database not available');

    try {
      final personas = await _db!.getAllPersonas();
      final result = personas.map((p) {
        List<String> facts = [];
        try {
          facts = List<String>.from(jsonDecode(p.learnedFacts));
        } catch (_) {}
        return {
          'id': p.id,
          'title': p.title,
          'name': p.name,
          'persona': p.persona,
          'isActive': p.isActive,
          'learnedFacts': facts,
        };
      }).toList();

      return shelf.Response.ok(
        jsonEncode(result),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to fetch personas: $e');
    }
  }

  Future<shelf.Response> _handleSetActivePersona(shelf.Request request) async {
    if (_db == null) return _errorResponse(503, 'Database not available');

    try {
      final body = jsonDecode(await request.readAsString());
      final personaId = body['id']?.toString();
      if (personaId == null) return _errorResponse(400, 'id is required');

      await _db!.setActivePersona(personaId);
      return shelf.Response.ok(
        jsonEncode({'status': 'ok'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to set active persona: $e');
    }
  }

  Future<shelf.Response> _handleCreatePersona(shelf.Request request) async {
    if (_db == null) return _errorResponse(503, 'Database not available');

    try {
      final body = jsonDecode(await request.readAsString());
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      final companion = PersonasCompanion.insert(
        id: id,
        title: Value(body['title']?.toString() ?? ''),
        name: Value(body['name']?.toString() ?? 'User'),
        persona: Value(body['persona']?.toString() ?? ''),
      );
      await _db!.insertPersona(companion);
      return shelf.Response.ok(
        jsonEncode({'status': 'ok', 'id': id}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to create persona: $e');
    }
  }

  Future<shelf.Response> _handleDeletePersona(shelf.Request request) async {
    if (_db == null) return _errorResponse(503, 'Database not available');

    try {
      final body = jsonDecode(await request.readAsString());
      final id = body['id']?.toString();
      if (id == null) return _errorResponse(400, 'id is required');
      await _db!.deletePersonaById(id);
      return shelf.Response.ok(
        jsonEncode({'status': 'ok'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to delete persona: $e');
    }
  }

  Future<shelf.Response> _handleUpdatePersona(shelf.Request request) async {
    if (_db == null) return _errorResponse(503, 'Database not available');

    try {
      final body = jsonDecode(await request.readAsString());
      final id = body['id']?.toString();
      if (id == null) return _errorResponse(400, 'id is required');

      // Fetch the existing persona to get all current values
      final personas = await _db!.getAllPersonas();
      final existing = personas.firstWhere((p) => p.id == id);

      // Handle learnedFacts if provided
      final String learnedFactsJson = body.containsKey('learnedFacts')
          ? jsonEncode(body['learnedFacts'])
          : existing.learnedFacts;

      final companion = PersonasCompanion(
        id: Value(existing.id),
        title: Value(body['title']?.toString() ?? existing.title),
        name: Value(body['name']?.toString() ?? existing.name),
        persona: Value(body['persona']?.toString() ?? existing.persona),
        avatarPath: Value(existing.avatarPath),
        isActive: Value(existing.isActive),
        learnedFacts: Value(learnedFactsJson),
        updatedAt: Value(DateTime.now()),
      );

      await _db!.updatePersona(companion);
      return shelf.Response.ok(
        jsonEncode({'status': 'ok'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to update persona: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // Worlds API
  // ─────────────────────────────────────────────────────────────────────

  Future<shelf.Response> _handleGetWorlds(shelf.Request request) async {
    if (_db == null) return _errorResponse(503, 'Database not available');

    try {
      final worlds = await _db!.getAllWorlds();
      final list = worlds.map((w) {
        Map<String, dynamic>? lorebook;
        if (w.lorebook != null) {
          try {
            lorebook = jsonDecode(w.lorebook!);
          } catch (_) {}
        }
        return {
          'id': w.id,
          'name': w.name,
          'description': w.description,
          'lorebook': lorebook,
          'linkedCharacterName': w.linkedCharacterName,
        };
      }).toList();

      return shelf.Response.ok(
        jsonEncode(list),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to get worlds: $e');
    }
  }

  Future<shelf.Response> _handleCreateWorld(shelf.Request request) async {
    if (_db == null) return _errorResponse(503, 'Database not available');

    try {
      final body = jsonDecode(await request.readAsString());
      final name = body['name']?.toString() ?? '';
      if (name.isEmpty) return _errorResponse(400, 'name is required');

      final id = await _db!.insertWorld(
        WorldsCompanion.insert(
          id: const Uuid().v4(),
          name: name,
          description: Value(body['description']?.toString() ?? ''),
          lorebook: Value(
            body.containsKey('lorebook') ? jsonEncode(body['lorebook']) : null,
          ),
        ),
      );

      return shelf.Response.ok(
        jsonEncode({'status': 'ok', 'id': id}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to create world: $e');
    }
  }

  Future<shelf.Response> _handleUpdateWorld(shelf.Request request) async {
    if (_db == null) return _errorResponse(503, 'Database not available');

    try {
      final body = jsonDecode(await request.readAsString());
      final id = body['id']?.toString();
      if (id == null) return _errorResponse(400, 'id is required');

      // Get existing world
      final worlds = await _db!.getAllWorlds();
      final existing = worlds.firstWhere((w) => w.id == id);

      final companion = WorldsCompanion(
        id: Value(existing.id),
        name: Value(body['name']?.toString() ?? existing.name),
        description: Value(
          body['description']?.toString() ?? existing.description,
        ),
        lorebook: Value(
          body.containsKey('lorebook')
              ? jsonEncode(body['lorebook'])
              : existing.lorebook,
        ),
        linkedCharacterName: Value(existing.linkedCharacterName),
        updatedAt: Value(DateTime.now()),
      );

      await _db!.updateWorld(companion);
      return shelf.Response.ok(
        jsonEncode({'status': 'ok'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to update world: $e');
    }
  }

  Future<shelf.Response> _handleDeleteWorld(shelf.Request request) async {
    if (_db == null) return _errorResponse(503, 'Database not available');

    try {
      final body = jsonDecode(await request.readAsString());
      final id = body['id']?.toString();
      if (id == null) return _errorResponse(400, 'id is required');
      await _db!.deleteWorldById(id);
      return shelf.Response.ok(
        jsonEncode({'status': 'ok'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to delete world: $e');
    }
  }

  Future<shelf.Response> _handleCreateCharacter(shelf.Request request) async {
    if (_db == null) return _errorResponse(503, 'Database not available');

    try {
      final body = jsonDecode(await request.readAsString());
      final name = body['name']?.toString() ?? '';
      if (name.isEmpty) {
        return _errorResponse(400, 'Character name is required');
      }

      final description = body['description']?.toString() ?? '';
      final personality = body['personality']?.toString() ?? '';
      final scenario = body['scenario']?.toString() ?? '';
      final firstMessage = body['firstMessage']?.toString() ?? '';
      final tagsRaw = body['tags'];
      final tags = tagsRaw is List ? jsonEncode(tagsRaw) : '[]';

      final dbId = await _db!.insertCharacterReturningId(
        CharactersCompanion(
          name: Value(name),
          description: Value(description),
          personality: Value(personality),
          scenario: Value(scenario),
          firstMessage: Value(firstMessage),
          mesExample: const Value(''),
          systemPrompt: const Value(''),
          postHistoryInstructions: const Value(''),
          alternateGreetings: const Value('[]'),
          tags: Value(tags),
          imagePath: const Value(null),
          ttsVoice: const Value(null),
          lorebook: const Value(null),
          worldNames: const Value('[]'),
        ),
      );

      // Refresh character list so new char appears
      _characterRepository?.loadCharacters();

      return shelf.Response.ok(
        jsonEncode({'status': 'ok', 'id': dbId}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to create character: $e');
    }
  }

  Future<shelf.Response> _handleUpdateEvolution(
    shelf.Request request,
    String id,
  ) async {
    if (_chatService == null) {
      return _errorResponse(503, 'Chat service not available');
    }

    try {
      final bodyStr = await request.readAsString();
      final body = jsonDecode(bodyStr) as Map<String, dynamic>;

      final evolvedPersonality = body['evolvedPersonality']?.toString();
      final evolvedScenario = body['evolvedScenario']?.toString();

      // Route through the session-aware service methods so evolution is
      // stored on the current session, not the character row.
      if (evolvedPersonality != null) {
        await _chatService!.updateEvolvedPersonality(evolvedPersonality);
      }
      if (evolvedScenario != null) {
        await _chatService!.updateEvolvedScenario(evolvedScenario);
      }

      return shelf.Response.ok(
        jsonEncode({'success': true}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to update evolution: $e');
    }
  }

  Future<shelf.Response> _handleDeleteCharacter(
    shelf.Request request,
    String id,
  ) async {
    if (_characterRepository == null) {
      return _errorResponse(503, 'Character repository not available');
    }

    try {
      final dbId = int.tryParse(id);
      if (dbId == null) return _errorResponse(400, 'Invalid character ID');

      // Find the character in the repository
      final character = _characterRepository!.characters.firstWhere(
        (c) => c.dbId == id,
        orElse: () => throw Exception('Character not found'),
      );

      await _characterRepository!.deleteCharacter(
        character,
        chatsDir: _storageService.chatsDir,
        cloudSyncService:
            _cloudSyncService, // enables soft-delete flag + reconcile-driven remote cleanup
      );

      return shelf.Response.ok(
        jsonEncode({'status': 'ok'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to delete character: $e');
    }
  }

  /// GET /api/characters/:id/export.png — Export character as PNG with embedded card data.
  /// Uses the proper CharacterCard model so that baked-in lorebooks (character_book),
  /// V2.5 extensions, and all fields are serialized in standard portable form.
  Future<shelf.Response> _handleExportCharacterPng(
    shelf.Request request,
    String id,
  ) async {
    if (_db == null) return _errorResponse(503, 'Database not available');
    try {
      // Prefer the repository path — this guarantees correct V2 shape + lorebook export
      CharacterCard? card;
      if (_characterRepository != null) {
        card = await _characterRepository!.getCharacterCardById(id);
      }

      // Fallback to raw DB row only if repository is unavailable (still better than 500)
      final dbCharacter = card == null ? await _db!.getCharacterById(id) : null;

      // Build V2 character card JSON in the canonical portable shape
      final Map<String, dynamic> data = card != null
          ? card.toJson()
          : dbCharacter!.toJson(); // raw shape is wrong but keeps server alive

      final v2Card = {
        'spec': 'chara_card_v2',
        'spec_version': '2.0',
        'data': data,
      };
      final charaJson = jsonEncode(v2Card);
      final charaB64 = base64Encode(utf8.encode(charaJson));

      // Load avatar PNG or create placeholder (use whichever source we have)
      final String displayName = card?.name ?? dbCharacter!.name;
      final String? imagePath = card?.imagePath ?? dbCharacter!.imagePath;

      Uint8List pngBytes;
      if (imagePath != null && imagePath.isNotEmpty) {
        final imgBasename = p.basename(imagePath);
        final imgFullPath = p.join(
          _storageService.charactersDir.path,
          imgBasename,
        );
        final file = File(imgFullPath);
        if (file.existsSync()) {
          pngBytes = file.readAsBytesSync();
        } else {
          pngBytes = _createPlaceholderPng(displayName);
        }
      } else {
        pngBytes = _createPlaceholderPng(displayName);
      }

      // Embed character data as tEXt chunk
      final resultPng = _embedPngTextChunk(pngBytes, 'chara', charaB64);
      final safeName = displayName.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');

      return shelf.Response.ok(
        resultPng,
        headers: {
          'Content-Type': 'image/png',
          'Content-Disposition': 'attachment; filename="$safeName.png"',
        },
      );
    } catch (e) {
      return _errorResponse(500, 'Export failed: $e');
    }
  }

  /// Create a minimal 1x1 white PNG for characters without avatars.
  Uint8List _createPlaceholderPng(String name) {
    // Minimal valid 1x1 white PNG
    return Uint8List.fromList([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
      0x00, 0x00, 0x00, 0x0D, // IHDR length
      0x49, 0x48, 0x44, 0x52, // IHDR type
      0x00, 0x00, 0x00, 0x01, // width=1
      0x00, 0x00, 0x00, 0x01, // height=1
      0x08, 0x02, // 8bit RGB
      0x00, 0x00, 0x00, // compression, filter, interlace
      0x90, 0x77, 0x53, 0xDE, // CRC
      0x00, 0x00, 0x00, 0x0C, // IDAT length
      0x49, 0x44, 0x41, 0x54, // IDAT type
      0x08,
      0xD7,
      0x63,
      0xF8,
      0xCF,
      0xC0,
      0x00,
      0x00,
      0x00,
      0x02,
      0x00,
      0x01, // compressed pixel
      0xE2, 0x21, 0xBC, 0x33, // CRC
      0x00, 0x00, 0x00, 0x00, // IEND length
      0x49, 0x45, 0x4E, 0x44, // IEND type
      0xAE, 0x42, 0x60, 0x82, // CRC
    ]);
  }

  /// Embed a tEXt chunk into a PNG before the IEND chunk.
  Uint8List _embedPngTextChunk(
    Uint8List pngBytes,
    String keyword,
    String text,
  ) {
    // Find IEND offset
    int iendPos = -1;
    for (int i = pngBytes.length - 12; i >= 8; i--) {
      if (pngBytes[i + 4] == 0x49 &&
          pngBytes[i + 5] == 0x45 &&
          pngBytes[i + 6] == 0x4E &&
          pngBytes[i + 7] == 0x44) {
        iendPos = i;
        break;
      }
    }
    if (iendPos < 0) return pngBytes;

    // Build tEXt chunk data: keyword + null + text
    final keyBytes = utf8.encode(keyword);
    final textBytes = utf8.encode(text);
    final chunkData = Uint8List(keyBytes.length + 1 + textBytes.length);
    chunkData.setRange(0, keyBytes.length, keyBytes);
    chunkData[keyBytes.length] = 0;
    chunkData.setRange(keyBytes.length + 1, chunkData.length, textBytes);

    // Chunk type
    final chunkType = utf8.encode('tEXt');

    // CRC32 over type + data
    final crcInput = Uint8List(4 + chunkData.length);
    crcInput.setRange(0, 4, chunkType);
    crcInput.setRange(4, crcInput.length, chunkData);
    final crc = _crc32(crcInput);

    // Build full chunk: length(4) + type(4) + data + crc(4)
    final chunkLen = chunkData.length;
    final chunk = Uint8List(4 + 4 + chunkData.length + 4);
    chunk[0] = (chunkLen >> 24) & 0xFF;
    chunk[1] = (chunkLen >> 16) & 0xFF;
    chunk[2] = (chunkLen >> 8) & 0xFF;
    chunk[3] = chunkLen & 0xFF;
    chunk.setRange(4, 8, chunkType);
    chunk.setRange(8, 8 + chunkData.length, chunkData);
    chunk[chunk.length - 4] = (crc >> 24) & 0xFF;
    chunk[chunk.length - 3] = (crc >> 16) & 0xFF;
    chunk[chunk.length - 2] = (crc >> 8) & 0xFF;
    chunk[chunk.length - 1] = crc & 0xFF;

    // Insert before IEND
    final result = Uint8List(pngBytes.length + chunk.length);
    result.setRange(0, iendPos, pngBytes);
    result.setRange(iendPos, iendPos + chunk.length, chunk);
    result.setRange(
      iendPos + chunk.length,
      result.length,
      pngBytes.sublist(iendPos),
    );
    return result;
  }

  /// Standard CRC32 for PNG chunks.
  int _crc32(Uint8List bytes) {
    int crc = 0xFFFFFFFF;
    for (int i = 0; i < bytes.length; i++) {
      crc ^= bytes[i];
      for (int j = 0; j < 8; j++) {
        crc = (crc >> 1) ^ (crc & 1 == 1 ? 0xEDB88320 : 0);
      }
    }
    return crc ^ 0xFFFFFFFF;
  }

  /// Normalize lorebook data from frontend format (key string, name) to DB format (keys array, comment).
  String _normalizeLorebookForDb(dynamic lorebookData) {
    if (lorebookData is! Map<String, dynamic>) return jsonEncode(lorebookData);
    final entries = lorebookData['entries'];
    if (entries is! List) return jsonEncode(lorebookData);

    final normalized = entries.map((e) {
      if (e is! Map<String, dynamic>) return e;
      // Convert 'key' (string) → 'keys' (array) and 'name' → 'comment'
      final keyStr = e['key']?.toString() ?? '';
      final keys = keyStr.isNotEmpty
          ? keyStr
                .split(',')
                .map((k) => k.trim())
                .where((k) => k.isNotEmpty)
                .toList()
          : (e['keys'] is List ? e['keys'] : <String>[]);
      return {
        'keys': keys,
        'content': e['content']?.toString() ?? '',
        'comment': e['name']?.toString() ?? e['comment']?.toString() ?? '',
        'enabled': e['enabled'] ?? true,
        'constant': e['constant'] ?? false,
        'sticky_depth':
            e['stickyDepth'] ?? e['sticky_depth'] ?? e['insertion_order'] ?? 4,
        'insertion_order': e['insertion_order'] ?? 0,
      };
    }).toList();

    return jsonEncode({'entries': normalized});
  }

  Future<shelf.Response> _handleImportCharacter(shelf.Request request) async {
    if (_characterRepository == null || _db == null) {
      return _errorResponse(503, 'Character repository not available');
    }

    try {
      final body = jsonDecode(await request.readAsString());
      final filename = body['filename']?.toString() ?? '';
      final dataBase64 = body['data']?.toString() ?? '';

      if (filename.isEmpty || dataBase64.isEmpty) {
        return _errorResponse(400, 'Filename and data are required');
      }

      final bytes = base64Decode(dataBase64);
      final ext = p.extension(filename).toLowerCase();

      // Write to temp file
      final tempDir = await Directory.systemTemp.createTemp('fpai_import_');
      final tempFile = File('${tempDir.path}/$filename');
      await tempFile.writeAsBytes(bytes);

      try {
        if (ext == '.byaf') {
          // Handle .byaf import
          final byafService = ByafService();
          final preview = await byafService.parseByaf(tempFile.path);
          final card = byafService.toCharacterCard(preview);
          final savedPath = await byafService.saveCharacterPng(
            card,
            charactersDirPath: _storageService.charactersDir.path,
          );
          card.imagePath = savedPath;

          // Insert into database
          final dbId = await _db!.insertCharacterReturningId(
            CharactersCompanion(
              name: Value(card.name),
              description: Value(card.description),
              personality: Value(card.personality),
              scenario: Value(card.scenario),
              firstMessage: Value(card.firstMessage),
              mesExample: Value(card.mesExample),
              systemPrompt: Value(card.systemPrompt),
              postHistoryInstructions: Value(card.postHistoryInstructions),
              alternateGreetings: Value(jsonEncode(card.alternateGreetings)),
              tags: Value(jsonEncode(card.tags)),
              imagePath: Value(
                card.imagePath != null ? p.basename(card.imagePath!) : null,
              ),
              ttsVoice: Value(card.ttsVoice),
              lorebook: Value(
                card.lorebook != null
                    ? jsonEncode(card.lorebook!.toJson())
                    : null,
              ),
              worldNames: Value(jsonEncode(card.worldNames)),
            ),
          );
          card.dbId = dbId;

          // Import chat history if available
          if (preview.messages.isNotEmpty) {
            await byafService.importChatHistory(_db!, preview, card);
          }

          _characterRepository!.addCharacter(card);

          return shelf.Response.ok(
            jsonEncode({'status': 'ok', 'name': card.name, 'id': dbId}),
            headers: {'Content-Type': 'application/json'},
          );
        } else {
          // Handle PNG V2 card import
          final card = await _characterRepository!.importCharacter(tempFile);

          if (card == null) {
            return _errorResponse(400, 'Failed to parse character from file');
          }

          return shelf.Response.ok(
            jsonEncode({'status': 'ok', 'name': card.name, 'id': card.dbId}),
            headers: {'Content-Type': 'application/json'},
          );
        }
      } finally {
        // Clean up temp directory
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
    } catch (e) {
      return _errorResponse(500, 'Failed to import character: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // Group Chat API
  // ─────────────────────────────────────────────────────────────────────

  Future<shelf.Response> _handleGetGroups(shelf.Request request) async {
    if (_groupChatRepository == null) {
      return _errorResponse(503, 'Group chat not available');
    }
    try {
      final groups = _groupChatRepository!.groups
          .map((g) => g.toJson())
          .toList();
      return shelf.Response.ok(
        jsonEncode(groups),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to fetch groups: $e');
    }
  }

  Future<shelf.Response> _handleCreateGroup(shelf.Request request) async {
    if (_groupChatRepository == null) {
      return _errorResponse(503, 'Group chat not available');
    }
    try {
      final body = jsonDecode(await request.readAsString());
      final group = GroupChat(
        id: 'group_${DateTime.now().millisecondsSinceEpoch}',
        name: body['name']?.toString() ?? 'Group Chat',
        // character_ids from API ignored (clean-break decoupling; members live in group_members).
        // External tools will be notified post-completion. New groups via API start memberless
        // until dedicated member endpoints or UI flows are used.
        turnOrder: TurnOrder.values.firstWhere(
          (e) => e.name == (body['turn_order'] ?? 'roundRobin'),
          orElse: () => TurnOrder.roundRobin,
        ),
        autoAdvance: body['auto_advance'] ?? false,
        directorMode: body['director_mode'] ?? false,
        firstMessage: body['first_message']?.toString() ?? '',
        scenario: body['scenario']?.toString() ?? '',
        systemPrompt: body['system_prompt']?.toString() ?? '',
        // v31 columns — web API creations start clean.
        baselineRealismState: '{}',
      );
      await _groupChatRepository!.save(group);
      return shelf.Response.ok(
        jsonEncode({'status': 'ok', 'id': group.id, 'name': group.name}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to create group: $e');
    }
  }

  Future<shelf.Response> _handleUpdateGroup(shelf.Request request) async {
    if (_groupChatRepository == null) {
      return _errorResponse(503, 'Group chat not available');
    }
    try {
      final body = jsonDecode(await request.readAsString());
      final id = body['id']?.toString() ?? '';
      if (id.isEmpty) return _errorResponse(400, 'Group id is required');
      final existing = _groupChatRepository!.getById(id);
      if (existing == null) return _errorResponse(404, 'Group not found');

      existing.name = body['name']?.toString() ?? existing.name;
      // character_ids updates from API ignored (decoupled; no legacy field on GroupChat).
      if (body['turn_order'] != null) {
        existing.turnOrder = TurnOrder.values.firstWhere(
          (e) => e.name == body['turn_order'],
          orElse: () => existing.turnOrder,
        );
      }
      if (body['auto_advance'] != null) {
        existing.autoAdvance = body['auto_advance'];
      }
      if (body['director_mode'] != null) {
        existing.directorMode = body['director_mode'];
      }
      if (body['first_message'] != null) {
        existing.firstMessage = body['first_message'].toString();
      }
      if (body['scenario'] != null) {
        existing.scenario = body['scenario'].toString();
      }
      if (body['system_prompt'] != null) {
        existing.systemPrompt = body['system_prompt'].toString();
      }

      await _groupChatRepository!.save(existing);
      return shelf.Response.ok(
        jsonEncode({'status': 'ok'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to update group: $e');
    }
  }

  Future<shelf.Response> _handleDeleteGroup(shelf.Request request) async {
    if (_groupChatRepository == null) {
      return _errorResponse(503, 'Group chat not available');
    }
    try {
      final body = jsonDecode(await request.readAsString());
      final id = body['id']?.toString() ?? '';
      if (id.isEmpty) return _errorResponse(400, 'Group id is required');
      await _groupChatRepository!.delete(
        id,
        cloudSyncService: _cloudSyncService,
      ); // enables deletion propagation via soft flag + reconcile
      return shelf.Response.ok(
        jsonEncode({'status': 'ok'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to delete group: $e');
    }
  }

  Future<shelf.Response> _handleSelectGroup(shelf.Request request) async {
    if (_groupChatRepository == null || _chatService == null) {
      return _errorResponse(503, 'Group chat not available');
    }
    try {
      final body = jsonDecode(await request.readAsString());
      final id = body['id']?.toString() ?? '';
      if (id.isEmpty) return _errorResponse(400, 'Group id is required');
      final group = _groupChatRepository!.getById(id);
      if (group == null) return _errorResponse(404, 'Group not found');

      await _chatService!.setActiveGroup(group);

      return shelf.Response.ok(
        jsonEncode({'status': 'ok', 'name': group.name}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to select group: $e');
    }
  }

  /// POST /api/groups/fork — Fork the current 1:1 chat into a new group.
  /// Body: { character_ids: [...], group_name?, scenario?, turn_order? }
  Future<shelf.Response> _handleForkToGroup(shelf.Request request) async {
    if (_chatService == null ||
        _groupChatRepository == null ||
        _characterRepository == null) {
      return _errorResponse(503, 'Services not available');
    }
    try {
      final body = jsonDecode(await request.readAsString());
      final charIds = List<String>.from(body['character_ids'] ?? []);
      if (charIds.isEmpty) return _errorResponse(400, 'character_ids required');

      // Resolve character cards from IDs
      final additionalChars = <CharacterCard>[];
      for (final cid in charIds) {
        final match = _characterRepository!.characters.where((c) {
          final id = c.imagePath != null
              ? p.basenameWithoutExtension(c.imagePath!)
              : c.name.replaceAll(RegExp(r'[^\w\s]'), '').replaceAll(' ', '_');
          return id == cid;
        }).firstOrNull;
        if (match != null) additionalChars.add(match);
      }

      if (additionalChars.isEmpty) {
        return _errorResponse(400, 'No valid characters found');
      }

      final turnOrder = TurnOrder.values.firstWhere(
        (e) => e.name == (body['turn_order'] ?? 'roundRobin'),
        orElse: () => TurnOrder.roundRobin,
      );

      final group = await _chatService!.forkToGroupChat(
        additionalChars,
        _groupChatRepository!,
        groupName: body['group_name']?.toString(),
        scenario: body['scenario']?.toString(),
        turnOrder: turnOrder,
      );

      // Post-fork private materialization for the additional members (extends this handler).
      // Uses real group.id from fork result + generalized duplicate + row insert. Functional decoupled fork.
      if (group != null) {
        final db = await AppDatabase.instance();
        for (final ch in additionalChars) {
          final mid = const Uuid().v4();
          final avDir = Directory(
            p.join(_storageService.groupsDir.path, group.id, 'avatars'),
          );
          await avDir.create(recursive: true);
          await _characterRepository!.duplicateCharacter(
            ch,
            targetDirOverride: avDir.path,
            forcedBasename: mid,
            skipLibraryInsert: true,
          );
          await db.insertGroupMember(
            GroupMembersCompanion(
              id: Value(mid),
              groupId: Value(group.id),
              name: Value(ch.name),
              description: Value(ch.description),
              personality: Value(ch.personality),
              scenario: Value(ch.scenario),
              firstMessage: Value(ch.firstMessage),
              mesExample: Value(ch.mesExample),
              systemPrompt: Value(ch.systemPrompt),
              postHistoryInstructions: Value(ch.postHistoryInstructions),
              alternateGreetings: Value(jsonEncode(ch.alternateGreetings)),
              tags: Value(jsonEncode(ch.tags)),
              avatarFilename: Value('$mid.png'),
              ttsVoice: Value(ch.ttsVoice),
              lorebook: Value(
                ch.lorebook != null ? jsonEncode(ch.lorebook!.toJson()) : null,
              ),
              worldNames: Value(jsonEncode(ch.worldNames)),
              frontPorchExtensions: Value(
                ch.frontPorchExtensions != null
                    ? jsonEncode(ch.frontPorchExtensions!.toJson())
                    : null,
              ),
              rawExtensions: Value(
                ch.rawExtensions != null ? jsonEncode(ch.rawExtensions!) : null,
              ),
              memberState: Value('{}'),
            ),
          );
        }
      }

      if (group == null) return _errorResponse(500, 'Fork failed');

      return shelf.Response.ok(
        jsonEncode({'status': 'ok', 'id': group.id, 'name': group.name}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to fork to group: $e');
    }
  }

  /// POST /api/groups/add-character — Add a character to the active group.
  /// Body: { character_id: "..." }
  Future<shelf.Response> _handleGroupAddCharacter(shelf.Request request) async {
    if (_chatService == null ||
        _groupChatRepository == null ||
        _characterRepository == null) {
      return _errorResponse(503, 'Services not available');
    }
    try {
      final body = jsonDecode(await request.readAsString());
      final charId = body['character_id']?.toString() ?? '';
      if (charId.isEmpty) return _errorResponse(400, 'character_id required');

      final match = _characterRepository!.characters.where((c) {
        final id = c.imagePath != null
            ? p.basenameWithoutExtension(c.imagePath!)
            : c.name.replaceAll(RegExp(r'[^\w\s]'), '').replaceAll(' ', '_');
        return id == charId;
      }).firstOrNull;

      if (match == null) return _errorResponse(404, 'Character not found');

      final ok = await _chatService!.addCharacterToGroup(
        match,
        _groupChatRepository!,
      );
      if (!ok) {
        return _errorResponse(
          400,
          'Could not add character (already in group or not in group mode)',
        );
      }

      return shelf.Response.ok(
        jsonEncode({'status': 'ok'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to add character: $e');
    }
  }

  /// POST /api/groups/remove-character — Remove a character from the active group.
  /// Body: { character_id: "..." }
  Future<shelf.Response> _handleGroupRemoveCharacter(
    shelf.Request request,
  ) async {
    if (_chatService == null ||
        _groupChatRepository == null ||
        _characterRepository == null) {
      return _errorResponse(503, 'Services not available');
    }
    try {
      final body = jsonDecode(await request.readAsString());
      final charId = body['character_id']?.toString() ?? '';
      if (charId.isEmpty) return _errorResponse(400, 'character_id required');

      final match = _characterRepository!.characters.where((c) {
        final id = c.imagePath != null
            ? p.basenameWithoutExtension(c.imagePath!)
            : c.name.replaceAll(RegExp(r'[^\w\s]'), '').replaceAll(' ', '_');
        return id == charId;
      }).firstOrNull;

      if (match == null) return _errorResponse(404, 'Character not found');

      final ok = await _chatService!.removeCharacterFromGroup(
        match,
        _groupChatRepository!,
      );
      if (!ok) {
        return _errorResponse(
          400,
          'Could not remove character (min 2 required or not in group mode)',
        );
      }

      return shelf.Response.ok(
        jsonEncode({'status': 'ok'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to remove character: $e');
    }
  }

  /// POST /api/groups/set-next — Set the next character to speak in a group.
  /// Body: { character_name: "..." }
  Future<shelf.Response> _handleGroupSetNext(shelf.Request request) async {
    if (_chatService == null) {
      return _errorResponse(503, 'Chat service not available');
    }
    try {
      final body = jsonDecode(await request.readAsString());
      final name = body['character_name']?.toString() ?? '';
      if (name.isEmpty) return _errorResponse(400, 'character_name required');

      final match = _chatService!.groupCharacters
          .where((c) => c.name == name)
          .firstOrNull;

      if (match == null) {
        return _errorResponse(404, 'Character not found in group');
      }

      _chatService!.setNextCharacter(match);

      return shelf.Response.ok(
        jsonEncode({'status': 'ok', 'next': name}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to set next character: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // AI Text Generation (for group scenario / first message)
  // ─────────────────────────────────────────────────────────────────────

  Future<shelf.Response> _handleGenerate(shelf.Request request) async {
    if (_llmProvider == null) {
      return _errorResponse(503, 'LLM provider not available');
    }
    final service = _llmProvider!.activeService;
    if (!service.isReady) {
      return _errorResponse(503, 'LLM backend is not ready');
    }

    try {
      final body = jsonDecode(await request.readAsString());
      final prompt = body['prompt']?.toString() ?? '';
      if (prompt.isEmpty) return _errorResponse(400, 'Prompt is required');

      final maxLength = body['maxLength'] as int? ?? 500;
      final temperature = (body['temperature'] as num?)?.toDouble() ?? 0.9;
      final stopSeqs = body['stopSequences'] != null
          ? List<String>.from(body['stopSequences'])
          : <String>[];

      final params = GenerationParams(
        prompt: prompt,
        maxLength: maxLength,
        temperature: temperature,
        stopSequences: stopSeqs.isNotEmpty ? stopSeqs : null,
      );

      final buffer = StringBuffer();
      await for (final token in service.generateStream(params)) {
        buffer.write(token);
      }

      return shelf.Response.ok(
        jsonEncode({'status': 'ok', 'text': buffer.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Generation failed: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // Folder API
  // ─────────────────────────────────────────────────────────────────────

  Future<shelf.Response> _handleGetFolders(shelf.Request request) async {
    if (_folderService == null) {
      return _errorResponse(503, 'Folder service not available');
    }

    try {
      final folders = _folderService!.folders;

      final result = folders
          .map(
            (f) => ({
              'id': f.id,
              'name': f.name,
              'parentId': f.parentId,
              'characterCount': f.characterPaths.length,
            }),
          )
          .toList();

      return shelf.Response.ok(
        jsonEncode(result),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to fetch folders: $e');
    }
  }

  Future<shelf.Response> _handleCreateFolder(shelf.Request request) async {
    if (_folderService == null) {
      return _errorResponse(503, 'Folder service not available');
    }
    try {
      final body = jsonDecode(await request.readAsString());
      final name = body['name']?.toString() ?? '';
      if (name.isEmpty) return _errorResponse(400, 'Folder name is required');
      final parentId = body['parentId']?.toString();
      final folder = await _folderService!.createFolder(
        name,
        parentId: parentId,
      );
      return shelf.Response.ok(
        jsonEncode({'status': 'ok', 'id': folder.id, 'name': folder.name}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to create folder: $e');
    }
  }

  Future<shelf.Response> _handleRenameFolder(shelf.Request request) async {
    if (_folderService == null) {
      return _errorResponse(503, 'Folder service not available');
    }
    try {
      final body = jsonDecode(await request.readAsString());
      final id = body['id']?.toString() ?? '';
      final name = body['name']?.toString() ?? '';
      if (id.isEmpty || name.isEmpty) {
        return _errorResponse(400, 'Folder id and name are required');
      }
      await _folderService!.renameFolder(id, name);
      return shelf.Response.ok(
        jsonEncode({'status': 'ok'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to rename folder: $e');
    }
  }

  Future<shelf.Response> _handleDeleteFolder(shelf.Request request) async {
    if (_folderService == null) {
      return _errorResponse(503, 'Folder service not available');
    }
    try {
      final body = jsonDecode(await request.readAsString());
      final id = body['id']?.toString() ?? '';
      if (id.isEmpty) return _errorResponse(400, 'Folder id is required');
      await _folderService!.deleteFolder(id);
      return shelf.Response.ok(
        jsonEncode({'status': 'ok'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to delete folder: $e');
    }
  }

  Future<shelf.Response> _handleAddCharToFolder(shelf.Request request) async {
    if (_folderService == null) {
      return _errorResponse(503, 'Folder service not available');
    }
    try {
      final body = jsonDecode(await request.readAsString());
      final folderId = body['folderId']?.toString() ?? '';
      final characterPath = body['characterPath']?.toString() ?? '';
      if (folderId.isEmpty || characterPath.isEmpty) {
        return _errorResponse(400, 'folderId and characterPath required');
      }
      await _folderService!.addToFolder(folderId, characterPath);
      return shelf.Response.ok(
        jsonEncode({'status': 'ok'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to add character to folder: $e');
    }
  }

  Future<shelf.Response> _handleRemoveCharFromFolder(
    shelf.Request request,
  ) async {
    if (_folderService == null) {
      return _errorResponse(503, 'Folder service not available');
    }
    try {
      final body = jsonDecode(await request.readAsString());
      final folderId = body['folderId']?.toString() ?? '';
      final characterPath = body['characterPath']?.toString() ?? '';
      if (folderId.isEmpty || characterPath.isEmpty) {
        return _errorResponse(400, 'folderId and characterPath required');
      }
      await _folderService!.removeFromFolder(folderId, characterPath);
      return shelf.Response.ok(
        jsonEncode({'status': 'ok'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to remove character from folder: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // Image Cache Proxy
  // ─────────────────────────────────────────────────────────────────────

  /// Returns the image_cache directory path.
  Future<Directory> _getImageCacheDir() async {
    final root =
        _storageService.rootPath ??
        (await getApplicationDocumentsDirectory()).path;
    final dir = Directory(p.join(root, 'system', 'image_cache'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Compute cache filename for a URL — same scheme as Flutter app.
  String _imageCacheFilename(String url) {
    final hash = url.hashCode.toRadixString(16);
    final uri = Uri.tryParse(url);
    String ext = '.png';
    if (uri != null && uri.pathSegments.isNotEmpty) {
      final seg = uri.pathSegments.last.split('.').last.split('?').first;
      if ([
        'png',
        'jpg',
        'jpeg',
        'gif',
        'webp',
        'svg',
      ].contains(seg.toLowerCase())) {
        ext = '.$seg';
      }
    }
    return '$hash$ext';
  }

  // ─────────────────────────────────────────────────────────────────────
  // RAG Sidecar
  // ─────────────────────────────────────────────────────────────────────

  /// GET /api/rag/status — Returns embedding sidecar state.
  Future<shelf.Response> _handleRagStatus(shelf.Request request) async {
    final sidecar = _embeddingSidecar;
    if (sidecar == null) {
      return shelf.Response.ok(
        jsonEncode({
          'available': false,
          'running': false,
          'modelReady': false,
          'error': 'Sidecar not configured',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
    return shelf.Response.ok(
      jsonEncode({
        'available': sidecar.isUsable,
        'running': sidecar.isRunning,
        'modelReady': sidecar.modelReady,
        'statusMessage': sidecar.statusMessage,
        'downloadProgress': sidecar.downloadProgress,
        'error': sidecar.error,
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }

  /// POST /api/rag/setup — Start the embedding sidecar (consent acknowledged).
  Future<shelf.Response> _handleRagSetup(shelf.Request request) async {
    final sidecar = _embeddingSidecar;
    if (sidecar == null) {
      return _errorResponse(503, 'Embedding sidecar not available');
    }
    if (sidecar.isRunning && sidecar.modelReady) {
      return shelf.Response.ok(
        jsonEncode({'status': 'already_ready'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
    // Start asynchronously — client polls /api/rag/status for progress
    sidecar.ensureRunning();
    return shelf.Response.ok(
      jsonEncode({'status': 'starting'}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  /// GET `/api/image-cache/check?url=<encoded_url>`
  /// Returns `{ cached: bool }` — checks if URL is already in local image cache.
  Future<shelf.Response> _handleImageCacheCheck(shelf.Request request) async {
    final url = request.url.queryParameters['url'];
    if (url == null || url.isEmpty) {
      return _errorResponse(400, 'url parameter required');
    }
    try {
      final dir = await _getImageCacheDir();
      final filename = _imageCacheFilename(url);
      final file = File('${dir.path}/$filename');
      return shelf.Response.ok(
        jsonEncode({'cached': await file.exists()}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Cache check failed: $e');
    }
  }

  /// GET `/api/image-cache/serve?url=<encoded_url>`
  /// Serves image from cache, downloading and caching first if needed.
  Future<shelf.Response> _handleImageCacheServe(shelf.Request request) async {
    final url = request.url.queryParameters['url'];
    if (url == null || url.isEmpty) {
      return _errorResponse(400, 'url parameter required');
    }
    try {
      final dir = await _getImageCacheDir();
      final filename = _imageCacheFilename(url);
      final file = File('${dir.path}/$filename');

      // Serve from cache if available
      if (await file.exists()) {
        final ext = filename.split('.').last.toLowerCase();
        final mime =
            {
              'png': 'image/png',
              'jpg': 'image/jpeg',
              'jpeg': 'image/jpeg',
              'gif': 'image/gif',
              'webp': 'image/webp',
              'svg': 'image/svg+xml',
            }[ext] ??
            'image/png';
        return shelf.Response.ok(
          await file.readAsBytes(),
          headers: {
            'Content-Type': mime,
            'Cache-Control': 'public, max-age=86400',
          },
        );
      }

      // Download and cache
      final httpClient = HttpClient();
      try {
        final req = await httpClient.getUrl(Uri.parse(url));
        final response = await req.close();
        if (response.statusCode != 200) {
          return _errorResponse(
            502,
            'Upstream returned ${response.statusCode}',
          );
        }
        final bytes = await consolidateHttpClientResponseBytes(response);
        await file.writeAsBytes(bytes);

        final contentType = response.headers.contentType;
        final mime = contentType != null
            ? '${contentType.primaryType}/${contentType.subType}'
            : 'image/png';
        return shelf.Response.ok(
          bytes,
          headers: {
            'Content-Type': mime,
            'Cache-Control': 'public, max-age=86400',
          },
        );
      } finally {
        httpClient.close();
      }
    } catch (e) {
      return _errorResponse(500, 'Image proxy failed: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // Cloud Sync API
  // ─────────────────────────────────────────────────────────────────────

  /// Ensure the cloud provider is connected using stored credentials.
  /// For WebDAV, creates a fresh provider and connects.
  /// For Google Drive, tries to restore saved credentials (no interactive OAuth).
  Future<CloudStorageProvider?> _ensureSyncProvider() async {
    final provider = _storageService.cloudSyncProvider;
    if (_cloudSyncService == null) return null;
    if (_cloudSyncService!.isConnected) return _cloudSyncService!.provider;

    CloudStorageProvider p;
    switch (provider) {
      case 'webdav':
        p = WebDavProvider();
        break;
      case 'gdrive':
        p = GoogleDriveProvider();
        break;
      default:
        return null;
    }
    try {
      await p.connect({
        'url': _storageService.cloudSyncUrl,
        'username': _storageService.cloudSyncUsername,
        'password': _storageService.cloudSyncPassword,
      });
      _cloudSyncService!.setProvider(p);
      return p;
    } catch (e) {
      debugPrint('[WebServer] Cloud provider connect failed: $e');
      return null;
    }
  }

  shelf.Response _handleGetSyncStatus(shelf.Request request) {
    final s = _storageService;
    final syncService = _cloudSyncService;
    return shelf.Response.ok(
      jsonEncode({
        'enabled': s.cloudSyncEnabled,
        'provider': s.cloudSyncProvider,
        'url': s.cloudSyncUrl,
        'username': s.cloudSyncUsername,
        'passwordSet': s.cloudSyncPassword.isNotEmpty,
        'lastSyncTime': s.cloudSyncLastTime,
        'status': syncService?.status.name ?? 'idle',
        'progress': syncService?.progress ?? 0.0,
        'syncedFiles': syncService?.syncedFiles ?? 0,
        'isConnected': syncService?.isConnected ?? false,
        'lastError': syncService?.lastError,
        'providerName': syncService?.providerName,
        'isPreRelease': isPreRelease,
        'stableVersionBase': stableVersionBase,
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<shelf.Response> _handleSetSyncConfig(shelf.Request request) async {
    if (isPreRelease) {
      return _errorResponse(
        403,
        'Cloud Sync is disabled in pre-release builds to prevent database incompatibility with the stable release.',
      );
    }
    try {
      final body = jsonDecode(await request.readAsString());
      final s = _storageService;

      if (body.containsKey('enabled')) {
        await s.setCloudSyncEnabled(body['enabled'] as bool);
      }
      if (body.containsKey('provider')) {
        await s.setCloudSyncProvider(body['provider'].toString());
      }
      if (body.containsKey('url')) {
        await s.setCloudSyncUrl(body['url'].toString());
      }
      if (body.containsKey('username')) {
        await s.setCloudSyncUsername(body['username'].toString());
      }
      if (body.containsKey('password')) {
        await s.setCloudSyncPassword(body['password'].toString());
      }

      return shelf.Response.ok(
        jsonEncode({'status': 'ok'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to save sync config: $e');
    }
  }

  Future<shelf.Response> _handleSyncTestConnection(
    shelf.Request request,
  ) async {
    if (isPreRelease) {
      return _errorResponse(
        403,
        'Cloud Sync is disabled in pre-release builds.',
      );
    }
    if (_cloudSyncService == null) {
      return _errorResponse(503, 'Cloud sync service not available');
    }

    try {
      final provider = await _ensureSyncProvider();
      if (provider == null) {
        return shelf.Response.ok(
          jsonEncode({
            'ok': false,
            'error': 'Could not connect to provider. Check credentials.',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final ok = await _cloudSyncService!.testConnection();
      return shelf.Response.ok(
        jsonEncode({
          'ok': ok,
          'error': ok
              ? null
              : (_cloudSyncService!.lastError ?? 'Connection test failed'),
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return shelf.Response.ok(
        jsonEncode({'ok': false, 'error': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Future<shelf.Response> _handleSyncNow(shelf.Request request) async {
    if (isPreRelease) {
      return _errorResponse(
        403,
        'Cloud Sync is disabled in pre-release builds.',
      );
    }
    if (_cloudSyncService == null) {
      return _errorResponse(503, 'Cloud sync service not available');
    }

    try {
      final provider = await _ensureSyncProvider();
      if (provider == null) {
        return _errorResponse(400, 'Could not connect to cloud provider');
      }

      final chatsPath = _storageService.chatsDir.path;
      final rootPath = _storageService.rootPath ?? chatsPath;
      final charactersPath =
          '$rootPath${Platform.pathSeparator}KoboldManager${Platform.pathSeparator}Characters';

      // Fire-and-forget — client polls /api/sync/status for progress
      _cloudSyncService!.fullSync(chatsPath, charactersPath).then((_) async {
        if (_cloudSyncService!.status == SyncStatus.success) {
          await _storageService.setCloudSyncLastTime(
            DateTime.now().toIso8601String(),
          );
          // Reload characters so newly downloaded PNGs appear
          await _characterRepository?.loadCharacters();
        }
      });

      return shelf.Response.ok(
        jsonEncode({'status': 'syncing'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to start sync: $e');
    }
  }

  Future<shelf.Response> _handleSyncForceUpload(shelf.Request request) async {
    if (isPreRelease) {
      return _errorResponse(
        403,
        'Cloud Sync is disabled in pre-release builds.',
      );
    }
    if (_cloudSyncService == null) {
      return _errorResponse(503, 'Cloud sync service not available');
    }

    try {
      final provider = await _ensureSyncProvider();
      if (provider == null) {
        return _errorResponse(400, 'Could not connect to cloud provider');
      }

      await _cloudSyncService!.forceUploadDatabase();
      await _storageService.setCloudSyncLastTime(
        DateTime.now().toIso8601String(),
      );

      return shelf.Response.ok(
        jsonEncode({'status': 'ok'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Force upload failed: $e');
    }
  }

  Future<shelf.Response> _handleSyncPurge(shelf.Request request) async {
    if (isPreRelease) {
      return _errorResponse(
        403,
        'Cloud Sync is disabled in pre-release builds.',
      );
    }
    if (_cloudSyncService == null) {
      return _errorResponse(503, 'Cloud sync service not available');
    }

    try {
      final provider = await _ensureSyncProvider();
      if (provider == null) {
        return _errorResponse(400, 'Could not connect to cloud provider');
      }

      await _cloudSyncService!.purgeCloudData();

      return shelf.Response.ok(
        jsonEncode({'status': 'ok'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Purge failed: $e');
    }
  }

  Future<shelf.Response> _handleListCloudCharacters(
    shelf.Request request,
  ) async {
    if (_cloudSyncService == null) {
      return _errorResponse(503, 'Cloud sync service not available');
    }

    try {
      final provider = await _ensureSyncProvider();
      if (provider == null) {
        return _errorResponse(400, 'Could not connect to cloud provider');
      }

      final rootPath =
          _storageService.rootPath ?? _storageService.chatsDir.path;
      final charactersPath =
          '$rootPath${Platform.pathSeparator}KoboldManager${Platform.pathSeparator}Characters';

      final chars = await _cloudSyncService!.listAllRemoteCharacters(
        charactersPath,
      );
      final result = chars
          .map((c) => {'name': c.name, 'existsLocally': c.existsLocally})
          .toList();

      return shelf.Response.ok(
        jsonEncode(result),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to list cloud characters: $e');
    }
  }

  Future<shelf.Response> _handleDownloadCloudCharacters(
    shelf.Request request,
  ) async {
    if (_cloudSyncService == null) {
      return _errorResponse(503, 'Cloud sync service not available');
    }

    try {
      final body = jsonDecode(await request.readAsString());
      final filenames = List<String>.from(body['filenames'] ?? []);
      if (filenames.isEmpty) {
        return _errorResponse(400, 'No filenames provided');
      }

      final provider = await _ensureSyncProvider();
      if (provider == null) {
        return _errorResponse(400, 'Could not connect to cloud provider');
      }

      final rootPath =
          _storageService.rootPath ?? _storageService.chatsDir.path;
      final charactersPath =
          '$rootPath${Platform.pathSeparator}KoboldManager${Platform.pathSeparator}Characters';

      final downloaded = await _cloudSyncService!.downloadCharacters(
        charactersPath,
        filenames,
      );

      // Reload characters so new PNGs appear in the UI
      await _characterRepository?.loadCharacters();

      return shelf.Response.ok(
        jsonEncode({'downloaded': downloaded}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to download characters: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // Backup API
  // ─────────────────────────────────────────────────────────────────────

  Future<shelf.Response> _handleGetBackups(shelf.Request request) async {
    if (isPreRelease) {
      return _errorResponse(403, 'Backups are disabled in pre-release builds.');
    }
    try {
      final backups = await BackupService.listBackups();
      final result = backups.map((f) {
        final stat = f.statSync();
        return {
          'path': f.path,
          'name': p.basename(f.path),
          'sizeMb': (stat.size / (1024 * 1024)).toStringAsFixed(1),
          'sizeBytes': stat.size,
          'modified': stat.modified.toIso8601String(),
        };
      }).toList();

      return shelf.Response.ok(
        jsonEncode(result),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to list backups: $e');
    }
  }

  Future<shelf.Response> _handleCreateBackup(shelf.Request request) async {
    if (isPreRelease) {
      return _errorResponse(403, 'Backups are disabled in pre-release builds.');
    }
    try {
      final backupPath = await BackupService.createBackup();
      return shelf.Response.ok(
        jsonEncode({
          'status': backupPath != null ? 'ok' : 'no_db',
          'path': backupPath,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to create backup: $e');
    }
  }

  Future<shelf.Response> _handleRestoreBackup(shelf.Request request) async {
    if (isPreRelease) {
      return _errorResponse(403, 'Backups are disabled in pre-release builds.');
    }
    try {
      final body = jsonDecode(await request.readAsString());
      final backupPath = body['path']?.toString();
      if (backupPath == null || backupPath.isEmpty) {
        return _errorResponse(400, 'path is required');
      }

      await BackupService.restoreBackup(backupPath);

      return shelf.Response.ok(
        jsonEncode({
          'status': 'ok',
          'message': 'Backup restored. App may need restart.',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to restore backup: $e');
    }
  }

  Future<shelf.Response> _handleDeleteBackup(shelf.Request request) async {
    if (isPreRelease) {
      return _errorResponse(403, 'Backups are disabled in pre-release builds.');
    }
    try {
      final body = jsonDecode(await request.readAsString());
      final backupPath = body['path']?.toString();
      if (backupPath == null || backupPath.isEmpty) {
        return _errorResponse(400, 'path is required');
      }

      final file = File(backupPath);
      if (await file.exists()) {
        await file.delete();
      }

      return shelf.Response.ok(
        jsonEncode({'status': 'ok'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to delete backup: $e');
    }
  }

  // _serveWebAsset + _resolveWebAssetPath + client tracker remnant + _parseUserAgent excised (Stage 6; deletion part of task + security hardening in web_asset_server lift). See prior deletion comments for auth/middleware. Live helpers (_errorResponse, _tryParseJsonList, _basename, disconnectClient, stop, broadcasts) remain below for the not-yet-lifted route groups.

  // _corsMiddleware + _corsHeaders extracted to middleware/cors_middleware.dart (Stage 6; deletion part of task). Old body removed; wired via CorsMiddleware().middleware in start().

  // ─────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────

  shelf.Response _errorResponse(int status, String message) {
    return shelf.Response(
      status,
      body: jsonEncode({'error': message}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  List<dynamic> _tryParseJsonList(String jsonStr) {
    try {
      return jsonDecode(jsonStr) as List<dynamic>;
    } catch (_) {
      return [];
    }
  }

  /// Extract filename from a path (matches FolderService._normalize).
  String _basename(String path) {
    final parts = path.split(RegExp(r'[/\\]'));
    return parts.last;
  }

  void disconnectClient() {
    _hasActiveClient = false;
    _connectedClientIp = null;
    _connectedClientInfo = null;
    _activeSessions.clear();
    debugPrint('[WebServer] Remote client disconnected');
    notifyListeners();
  }

  Future<void> stop() async {
    if (!_isRunning) return;
    await _server?.close(force: true);
    _server = null;
    _isRunning = false;
    _hasActiveClient = false;
    _connectedClientIp = null;
    _connectedClientInfo = null;
    _activeSessions.clear();
    debugPrint('[WebServer] Server stopped');
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────
  // Character Generator (AI Creator) API
  // ─────────────────────────────────────────────────────────────────────

  /// Send an SSE event to all chargen clients.
  void _chargenBroadcast(Map<String, dynamic> eventData) {
    // Also store state for polling fallback
    final eventType = eventData['event']?.toString() ?? '';
    if (eventType == 'status') {
      _chargenStatus = eventData['text']?.toString() ?? '';
    }
    if (eventType == 'preview') {
      _chargenPreview = eventData['text']?.toString() ?? '';
    }
    if (eventType == 'complete') {
      _chargenCompletedCard = eventData['card'] as Map<String, dynamic>?;
      _chargenError = null;
    }
    if (eventType == 'error') {
      _chargenError = eventData['text']?.toString() ?? 'Unknown error';
    }

    _chargenSseClients.removeWhere((c) => c.isClosed);
    if (_chargenSseClients.isEmpty) {
      debugPrint(
        '[SSE] No chargen clients connected, dropping $eventType event',
      );
      return;
    }
    int sent = 0;
    for (final client in _chargenSseClients) {
      try {
        final jsonStr = jsonEncode(eventData);
        client.add(utf8.encode('data: $jsonStr\n\n'));
        sent++;
      } catch (e) {
        debugPrint('[SSE] Failed to send $eventType to client: $e');
      }
    }
    if (eventType != 'preview') {
      debugPrint(
        '[SSE] Broadcast $eventType to $sent/${_chargenSseClients.length} clients',
      );
    }
  }

  /// GET /api/chargen/status — Polling fallback for generation progress.
  Future<shelf.Response> _handleChargenStatus(shelf.Request request) async {
    final result = <String, dynamic>{
      'isGenerating': _isChargenRunning,
      'status': _chargenStatus,
      'preview': _chargenPreview,
    };
    if (_chargenCompletedCard != null) {
      result['complete'] = true;
      result['card'] = _chargenCompletedCard;
    }
    if (_chargenError != null) {
      result['error'] = _chargenError;
    }
    return shelf.Response.ok(
      jsonEncode(result),
      headers: {'Content-Type': 'application/json'},
    );
  }

  /// GET /api/chargen/stream — SSE endpoint for generation progress.
  Future<shelf.Response> _handleChargenStream(shelf.Request request) async {
    final controller = StreamController<List<int>>();
    _chargenSseClients.add(controller);
    debugPrint(
      '[WebServer] Chargen SSE client connected (${_chargenSseClients.length} total)',
    );

    // Send initial state
    try {
      final jsonStr = jsonEncode({
        'event': 'connected',
        'isGenerating': _isChargenRunning,
      });
      controller.add(utf8.encode('data: $jsonStr\n\n'));
    } catch (_) {}

    controller.onCancel = () {
      _chargenSseClients.remove(controller);
      debugPrint(
        '[WebServer] Chargen SSE client disconnected (${_chargenSseClients.length} remaining)',
      );
    };

    return shelf.Response.ok(
      controller.stream,
      headers: {
        'Content-Type': 'text/event-stream',
        'Cache-Control': 'no-cache',
        'Connection': 'keep-alive',
        'Access-Control-Allow-Origin': '*',
      },
    );
  }

  /// Helper to create an SSE streaming response from an LLM generation.
  /// Sends 'token' events in real-time and a 'done' event with the parsed result.
  shelf.Response _streamingLlmResponse(
    LLMService llmService,
    GenerationParams params,
    String resultKey, // 'name' or 'concept'
    Duration timeout,
  ) {
    final controller = StreamController<List<int>>();

    void sse(String event, String data) {
      if (!controller.isClosed) {
        controller.add(utf8.encode('event: $event\ndata: $data\n\n'));
      }
    }

    () async {
      String accumulated = '';
      bool inThinking = false;
      try {
        await for (final token
            in llmService.generateStream(params).timeout(timeout)) {
          accumulated += token;
          // Filter thinking tokens
          if (token.contains('<think>')) {
            inThinking = true;
            continue;
          }
          if (token.contains('</think>')) {
            inThinking = false;
            continue;
          }
          if (inThinking) continue;
          sse('token', token);
        }

        // Parse JSON and extract result
        String cleaned = accumulated
            .replaceAll(
              RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false),
              '',
            )
            .replaceAll(RegExp(r'<think>[\s\S]*$', caseSensitive: false), '')
            .trim();

        // Strip markdown code fences (common with local models)
        cleaned = cleaned
            .replaceAll(RegExp(r'^```(?:json)?\s*', multiLine: true), '')
            .replaceAll(RegExp(r'^```\s*$', multiLine: true), '')
            .trim();

        final jsonStart = cleaned.indexOf('{');
        final jsonEnd = cleaned.lastIndexOf('}');
        String result = accumulated.trim();
        if (jsonStart >= 0 && jsonEnd > jsonStart) {
          final jsonStr = cleaned.substring(jsonStart, jsonEnd + 1);
          // Strategy 1: Direct parse
          bool parsed = false;
          try {
            final data = jsonDecode(jsonStr) as Map<String, dynamic>;
            result = data[resultKey]?.toString() ?? result;
            parsed = true;
          } catch (_) {}

          // Strategy 2: Fix literal newlines inside JSON strings
          if (!parsed) {
            try {
              String fixed = jsonStr
                  .replaceAll('\r\n', '\\n')
                  .replaceAll('\r', '\\n');
              final sb = StringBuffer();
              bool inStr = false;
              bool esc = false;
              for (int i = 0; i < fixed.length; i++) {
                final ch = fixed[i];
                if (esc) {
                  sb.write(ch);
                  esc = false;
                  continue;
                }
                if (ch == '\\') {
                  sb.write(ch);
                  esc = true;
                  continue;
                }
                if (ch == '"') {
                  inStr = !inStr;
                  sb.write(ch);
                  continue;
                }
                if (ch == '\n' && inStr) {
                  sb.write('\\n');
                  continue;
                }
                sb.write(ch);
              }
              fixed = sb
                  .toString()
                  .replaceAll(RegExp(r',\s*}'), '}')
                  .replaceAll(RegExp(r',\s*]'), ']');
              final data = jsonDecode(fixed) as Map<String, dynamic>;
              result = data[resultKey]?.toString() ?? result;
              parsed = true;
            } catch (_) {}
          }

          // Strategy 3: Regex fallback
          if (!parsed) {
            final pattern = RegExp(
              '"$resultKey"\\s*:\\s*"',
              caseSensitive: false,
            );
            final match = pattern.firstMatch(jsonStr);
            if (match != null) {
              final valueStart = match.end;
              bool esc = false;
              for (int i = valueStart; i < jsonStr.length; i++) {
                final ch = jsonStr[i];
                if (esc) {
                  esc = false;
                  continue;
                }
                if (ch == '\\') {
                  esc = true;
                  continue;
                }
                if (ch == '"') {
                  result = jsonStr
                      .substring(valueStart, i)
                      .replaceAll('\\n', '\n')
                      .replaceAll('\\t', '\t')
                      .replaceAll('\\"', '"');
                  break;
                }
              }
            }
          }
        }
        sse('done', jsonEncode({resultKey: result}));
      } catch (e) {
        debugPrint('Chargen streaming error: $e');
        sse('error', jsonEncode({'error': '$e'}));
      }
      await controller.close();
    }();

    return shelf.Response.ok(
      controller.stream,
      headers: {
        'Content-Type': 'text/event-stream',
        'Cache-Control': 'no-cache',
        'Connection': 'keep-alive',
      },
    );
  }

  /// Resolve the LLM service for chargen, creating a fresh OpenRouterService
  /// when a specific modelId is provided.
  LLMService? _resolveChargenLlm(String modelId, String debugLabel) {
    if (modelId.isNotEmpty) {
      debugPrint(
        '$debugLabel: Using model=$modelId via ${_storageService.remoteApiUrl}',
      );
      return OpenRouterService(
        apiUrl: _storageService.remoteApiUrl,
        apiKey: _storageService.remoteApiKey,
        modelName: modelId,
      );
    } else {
      debugPrint(
        '$debugLabel: Using active service: ${_llmProvider!.activeService.runtimeType}',
      );
      return _llmProvider!.activeService;
    }
  }

  /// POST /api/chargen/randomname — Stream a random character name generation.
  Future<shelf.Response> _handleChargenRandomName(shelf.Request request) async {
    if (_llmProvider == null) {
      return _errorResponse(503, 'LLM provider not available');
    }
    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final archetype = body['selectedArchetype']?.toString() ?? '';
      final modelId = body['modelId']?.toString() ?? '';

      final llmService = _resolveChargenLlm(modelId, 'ChargenRandomName');
      if (llmService == null || !llmService.isReady) {
        return _errorResponse(
          503,
          'LLM service is not ready. Select a model first.',
        );
      }

      final archetypeHint = archetype.isNotEmpty
          ? ' The name should suit a "$archetype" character.'
          : '';

      return _streamingLlmResponse(
        llmService,
        GenerationParams(
          prompt:
              'Generate ONE unique, creative character name for a roleplay character.$archetypeHint Output ONLY a JSON object with exactly one key: "name". No markdown, no explanation, just the JSON:',
          maxLength: 128,
          minLength: 16,
          temperature: 1.2,
          repeatPenalty: 1.1,
          minP: 0.05,
          reasoningEnabled: false,
          stopSequences: ['<END>'],
        ),
        'name',
        const Duration(seconds: 90),
      );
    } catch (e) {
      debugPrint('ChargenRandomName: Error: $e');
      return _errorResponse(500, 'Name generation failed: $e');
    }
  }

  /// POST /api/chargen/describe — Stream a character description generation.
  Future<shelf.Response> _handleChargenDescribe(shelf.Request request) async {
    if (_llmProvider == null) {
      return _errorResponse(503, 'LLM provider not available');
    }
    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;

      // Build context from all selections (mirrors Flutter _randomizeConcept)
      final contextParts = <String>[];
      final archetype = body['selectedArchetype']?.toString() ?? '';
      if (archetype.isNotEmpty) contextParts.add('Archetype: $archetype');
      final name = body['name']?.toString() ?? '';
      if (name.isNotEmpty) contextParts.add('Name: $name');
      final keywords = body['keywords']?.toString() ?? '';
      if (keywords.isNotEmpty) contextParts.add('Personality: $keywords');
      final age = body['age']?.toString() ?? '';
      if (age.isNotEmpty) contextParts.add('Age: $age');
      final sex = body['sex']?.toString() ?? '';
      if (sex.isNotEmpty) contextParts.add('Sex: $sex');
      final customRace = body['customRace']?.toString() ?? '';
      final race = customRace.isNotEmpty
          ? customRace
          : (body['race']?.toString() ?? '');
      if (race.isNotEmpty) contextParts.add('Race/species: $race');
      final bodyType = body['bodyType']?.toString() ?? '';
      if (bodyType.isNotEmpty) contextParts.add('Body type: $bodyType');
      final hairLen = body['hairLength']?.toString() ?? '';
      final hairSty = body['hairStyle']?.toString() ?? '';
      if (hairLen.isNotEmpty || hairSty.isNotEmpty) {
        contextParts.add(
          'Hair: ${[if (hairLen.isNotEmpty) hairLen, if (hairSty.isNotEmpty) hairSty].join(", ")}',
        );
      }
      final skinTone = body['skinTone']?.toString() ?? '';
      if (skinTone.isNotEmpty) contextParts.add('Skin tone: $skinTone');
      final features = (body['notableFeatures'] as List?)?.cast<String>() ?? [];
      if (features.isNotEmpty) {
        contextParts.add('Notable features: ${features.join(", ")}');
      }
      final relationship = body['relationship']?.toString() ?? '';
      if (relationship.isNotEmpty) {
        contextParts.add('Relationship to user: $relationship');
      }
      final bsOrigin = body['backstoryOrigin']?.toString() ?? '';
      if (bsOrigin.isNotEmpty) contextParts.add('Backstory origin: $bsOrigin');
      final bsTone = body['backstoryTone']?.toString() ?? '';
      if (bsTone.isNotEmpty) contextParts.add('Backstory tone: $bsTone');
      final bsEra = body['backstoryEra']?.toString() ?? '';
      if (bsEra.isNotEmpty) contextParts.add('Era/setting: $bsEra');
      final bsNotes = body['backstoryNotes']?.toString() ?? '';
      if (bsNotes.isNotEmpty) contextParts.add('Backstory notes: $bsNotes');
      final nsfw = body['nsfwEnabled'] == true;
      if (nsfw) {
        final exp = body['experience']?.toString() ?? '';
        if (exp.isNotEmpty) contextParts.add('Experience: $exp');
        final dom = body['dominance']?.toString() ?? '';
        if (dom.isNotEmpty) contextParts.add('Dominance: $dom');
        final kinks = (body['kinks'] as List?)?.cast<String>() ?? [];
        if (kinks.isNotEmpty) contextParts.add('Kinks: ${kinks.join(", ")}');
        final outfit = body['outfitVibe']?.toString() ?? '';
        if (outfit.isNotEmpty) contextParts.add('Outfit vibe: $outfit');
      }

      final contextStr = contextParts.isNotEmpty
          ? ' Use these character details as inspiration: ${contextParts.join("; ")}.'
          : '';

      final detailMap = {
        'Brief': '1 short paragraph',
        'Standard': '2-3 paragraphs',
        'Detailed': '3-4 rich paragraphs',
        'Comprehensive': '5-6 detailed paragraphs with extensive backstory',
      };
      final maxTokenMap = {
        'Brief': 256,
        'Standard': 512,
        'Detailed': 1024,
        'Comprehensive': 2048,
      };
      final detail = body['generationDetail']?.toString() ?? 'Standard';
      final descLength = detailMap[detail] ?? '2-3 paragraphs';
      final maxTokens = maxTokenMap[detail] ?? 512;

      final modelId = body['modelId']?.toString() ?? '';
      final llmService = _resolveChargenLlm(modelId, 'ChargenDescribe');
      if (llmService == null || !llmService.isReady) {
        return _errorResponse(
          503,
          'LLM service is not ready. Select a model first.',
        );
      }

      final prompt =
          'Generate a creative character description ($descLength) for a roleplay character.$contextStr Write in third person. Include physical appearance, personality hints, and backstory elements. Output ONLY a JSON object with exactly one key: "concept". Be vivid and detailed. No markdown, no explanation, just the JSON:';

      return _streamingLlmResponse(
        llmService,
        GenerationParams(
          prompt: prompt,
          maxLength: maxTokens,
          minLength: 32,
          temperature: 1.2,
          repeatPenalty: 1.1,
          minP: 0.05,
          reasoningEnabled: false,
          stopSequences: ['<END>'],
        ),
        'concept',
        const Duration(seconds: 120),
      );
    } catch (e) {
      return _errorResponse(500, 'Description generation failed: $e');
    }
  }

  /// POST /api/chargen/expand — Stream a guided narrative expansion.
  /// Gathers all guided-mode field values and asks the LLM to weave them
  /// into a cohesive 2-3 paragraph character description (mirrors Flutter
  /// _expandNarrative).
  Future<shelf.Response> _handleChargenExpand(shelf.Request request) async {
    if (_llmProvider == null) {
      return _errorResponse(503, 'LLM provider not available');
    }
    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final modelId = body['modelId']?.toString() ?? '';

      final llmService = _resolveChargenLlm(modelId, 'ChargenExpand');
      if (llmService == null || !llmService.isReady) {
        return _errorResponse(
          503,
          'LLM service is not ready. Select a model first.',
        );
      }

      // Gather all filled-in fields (mirrors Flutter _expandNarrative)
      final details = <String>[];
      void addIfPresent(String key, String label) {
        final v = body[key]?.toString() ?? '';
        if (v.isNotEmpty) details.add('$label: $v');
      }

      addIfPresent('name', 'Name');
      addIfPresent('age', 'Age');
      addIfPresent('sex', 'Sex');
      addIfPresent('guidedAppearance', 'Build/Body');
      addIfPresent('guidedHair', 'Hair');
      addIfPresent('guidedFeatures', 'Features');
      addIfPresent('guidedRace', 'Race/Species');
      addIfPresent('guidedPersonality', 'Personality');
      addIfPresent('guidedSpeech', 'Speech style');
      addIfPresent('guidedSecret', 'Hidden depth');
      addIfPresent('guidedOrigin', 'Background');
      addIfPresent('guidedSetting', 'Setting');
      addIfPresent('guidedTone', 'Tone');
      addIfPresent('guidedRelDynamic', 'Relationship to {{user}}');
      addIfPresent('guidedRelScenario', 'Opening scenario');
      final nsfw = body['nsfwEnabled'] == true;
      if (nsfw) {
        addIfPresent('guidedNsfwBody', 'Intimate body');
        addIfPresent('guidedNsfwExp', 'Experience');
        addIfPresent('guidedNsfwDom', 'Dominance');
        addIfPresent('guidedNsfwKinks', 'Kinks');
        addIfPresent('guidedNsfwClothing', 'Clothing');
        addIfPresent('guidedNsfwPersonality', 'Sexual personality');
      }

      final userVision = body['guidedVision']?.toString() ?? '';
      if (details.length <= 1 && userVision.isEmpty) {
        return _errorResponse(
          400,
          'Please fill in at least a few fields before generating.',
        );
      }

      final detailsBlock = details.join('\n');
      final visionBlock = userVision.isNotEmpty
          ? '\n\nUser\'s additional notes/vision:\n"$userVision"'
          : '';

      final prompt =
          'A user is creating a roleplay character using a guided form. They filled in '
          'various fields with details about the character. Generate a vivid, cohesive character '
          'description that weaves ALL of these details together into 2-3 flowing paragraphs. '
          'PRESERVE the user\'s creative intent — do not override their ideas with generic tropes. '
          'If they provided NSFW details, include them tastefully in the description.\n\n'
          'Character details from form:\n$detailsBlock$visionBlock\n\n'
          'Output ONLY a JSON object with exactly one key: "expanded". The value should be '
          'the complete character description in third person. No markdown, no explanation, just the JSON:';

      return _streamingLlmResponse(
        llmService,
        GenerationParams(
          prompt: prompt,
          maxLength: 1024,
          minLength: 64,
          temperature: 1.0,
          repeatPenalty: 1.1,
          minP: 0.05,
          reasoningEnabled: false,
          stopSequences: ['<END>'],
        ),
        'expanded',
        const Duration(seconds: 120),
      );
    } catch (e) {
      return _errorResponse(500, 'Narrative expansion failed: $e');
    }
  }

  /// POST /api/chargen/generate — Start multi-step character generation.
  Future<shelf.Response> _handleChargenGenerate(shelf.Request request) async {
    if (_llmProvider == null) {
      return _errorResponse(503, 'LLM provider not available');
    }
    if (_isChargenRunning) {
      return _errorResponse(409, 'Generation already in progress');
    }

    try {
      final body = jsonDecode(await request.readAsString());
      final name = body['name']?.toString() ?? '';
      if (name.isEmpty) {
        return _errorResponse(400, 'Character name is required');
      }

      final concept = body['concept']?.toString() ?? '';
      final keywords = body['keywords']?.toString() ?? '';
      final age = body['age']?.toString() ?? '';
      final sex = body['sex']?.toString() ?? '';
      final relationship = body['relationship']?.toString() ?? '';
      final greetingLength =
          body['greetingLength']?.toString() ?? 'Medium (2-4 paragraphs)';
      final altGreetingCount = body['altGreetingCount'] as int? ?? 2;
      final greetingTones = List<String>.from(
        body['greetingTones'] ?? ['Neutral'],
      );
      final generateLorebook = body['generateLorebook'] as bool? ?? true;
      final loreCategories = List<String>.from(body['loreCategories'] ?? []);
      final loreDepth = body['loreDepth']?.toString() ?? 'Standard';
      final nsfwEnabled = body['nsfwEnabled'] as bool? ?? false;
      final generationDetail =
          body['generationDetail']?.toString() ?? 'Standard';
      final backstoryNotes = body['backstoryNotes']?.toString() ?? '';
      final artStyle = body['artStyle']?.toString() ?? 'Anime';
      final selectedPersonaId = body['personaId']?.toString() ?? '';
      final modelId = body['modelId']?.toString() ?? '';

      // Build description detail from generationDetail
      String descriptionDetail;
      switch (generationDetail) {
        case 'Brief':
          descriptionDetail = '1 short paragraph';
          break;
        case 'Detailed':
          descriptionDetail = '3-4 rich paragraphs';
          break;
        case 'Comprehensive':
          descriptionDetail =
              '5-6 detailed paragraphs with extensive backstory';
          break;
        default:
          descriptionDetail = '2-3 paragraphs';
      }

      // Build character context from appearance + NSFW + backstory
      final contextParts = <String>[];

      // Appearance
      final race = body['race']?.toString() ?? '';
      final customRace = body['customRace']?.toString() ?? '';
      final bodyType = body['bodyType']?.toString() ?? '';
      final hairLength = body['hairLength']?.toString() ?? '';
      final hairStyle = body['hairStyle']?.toString() ?? '';
      final skinTone = body['skinTone']?.toString() ?? '';
      final notableFeatures = List<String>.from(body['notableFeatures'] ?? []);
      final absCore = body['absCore']?.toString() ?? '';
      final thighs = body['thighs']?.toString() ?? '';
      final hips = body['hips']?.toString() ?? '';
      final shoulders = body['shoulders']?.toString() ?? '';
      final waist = body['waist']?.toString() ?? '';

      final effectiveRace = customRace.isNotEmpty ? customRace : race;
      if (effectiveRace.isNotEmpty) {
        contextParts.add('Race/Species: $effectiveRace');
      }
      if (bodyType.isNotEmpty) contextParts.add('Body type: $bodyType');
      if (hairLength.isNotEmpty || hairStyle.isNotEmpty) {
        final hair = [
          hairLength,
          hairStyle,
        ].where((s) => s.isNotEmpty).join(' ');
        contextParts.add('Hair: $hair');
      }
      if (skinTone.isNotEmpty) contextParts.add('Skin: $skinTone');
      if (notableFeatures.isNotEmpty) {
        contextParts.add('Notable features: ${notableFeatures.join(", ")}');
      }
      final bodyParts = <String>[];
      if (absCore.isNotEmpty) bodyParts.add('abs/core: $absCore');
      if (thighs.isNotEmpty) bodyParts.add('thighs: $thighs');
      if (hips.isNotEmpty) bodyParts.add('hips: $hips');
      if (shoulders.isNotEmpty) bodyParts.add('shoulders: $shoulders');
      if (waist.isNotEmpty) bodyParts.add('waist: $waist');
      if (bodyParts.isNotEmpty) {
        contextParts.add('Build: ${bodyParts.join(", ")}');
      }

      // NSFW appearance
      if (nsfwEnabled) {
        final chestSize = body['chestSize']?.toString() ?? '';
        final buttSize = body['buttSize']?.toString() ?? '';
        final experience = body['experience']?.toString() ?? '';
        final dominance = body['dominance']?.toString() ?? '';
        final kinks = List<String>.from(body['kinks'] ?? []);
        final customKinks = body['customKinks']?.toString() ?? '';
        final outfitVibe = body['outfitVibe']?.toString() ?? '';

        if (chestSize.isNotEmpty) contextParts.add('Chest: $chestSize');
        if (buttSize.isNotEmpty) contextParts.add('Butt: $buttSize');
        if (experience.isNotEmpty) {
          contextParts.add('Experience level: $experience');
        }
        if (dominance.isNotEmpty) contextParts.add('Dominance: $dominance');
        final allKinks = [...kinks];
        if (customKinks.isNotEmpty) allKinks.add(customKinks);
        if (allKinks.isNotEmpty) {
          contextParts.add('Kinks: ${allKinks.join(", ")}');
        }
        if (outfitVibe.isNotEmpty) contextParts.add('Outfit vibe: $outfitVibe');
      }

      // Backstory
      final backstoryOrigin = body['backstoryOrigin']?.toString() ?? '';
      final backstoryTone = body['backstoryTone']?.toString() ?? '';
      final backstoryEra = body['backstoryEra']?.toString() ?? '';
      final backstoryParts = <String>[];
      if (backstoryOrigin.isNotEmpty) {
        backstoryParts.add('Origin: $backstoryOrigin');
      }
      if (backstoryTone.isNotEmpty) backstoryParts.add('Tone: $backstoryTone');
      if (backstoryEra.isNotEmpty) backstoryParts.add('Era: $backstoryEra');
      if (backstoryNotes.isNotEmpty) backstoryParts.add(backstoryNotes);
      final backstory = backstoryParts.join('. ');

      final characterContext = contextParts.join('\n');

      // Build user persona context
      String userPersonaContext = '';
      if (selectedPersonaId.isNotEmpty && _userPersonaService != null) {
        final persona = _userPersonaService!.persona;
        if (persona.name.isNotEmpty) {
          userPersonaContext = 'Name: ${persona.name}';
          if (persona.persona.isNotEmpty) {
            userPersonaContext += '\n${persona.persona}';
          }
        }
      }

      // Return immediately, run generation in background
      _isChargenRunning = true;
      _chargenCompletedCard = null;
      _chargenError = null;
      _chargenStatus = 'Starting generation...';
      _chargenPreview = '';
      _chargenBroadcast({'event': 'started'});

      // Resolve LLM service — use model override if provided
      final genLlmService = _resolveChargenLlm(modelId, 'ChargenGenerate');
      if (genLlmService == null || !genLlmService.isReady) {
        _isChargenRunning = false;
        return _errorResponse(503, 'LLM backend is not ready');
      }

      // Create CharacterGenService with resolved LLM
      final genService = CharacterGenService(genLlmService);

      // Run generation asynchronously
      _runChargenAsync(
        genService: genService,
        name: name,
        concept: concept,
        keywords: keywords,
        age: age,
        sex: sex,
        relationship: relationship,
        greetingLength: greetingLength,
        altGreetingCount: altGreetingCount,
        greetingTones: greetingTones,
        generateLorebook: generateLorebook,
        loreCategories: loreCategories,
        loreDepth: loreDepth,
        descriptionDetail: descriptionDetail,
        backstory: backstory,
        characterContext: characterContext,
        userPersonaContext: userPersonaContext,
        artStyle: artStyle,
      );

      return shelf.Response.ok(
        jsonEncode({'status': 'started'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      _isChargenRunning = false;
      return _errorResponse(500, 'Failed to start generation: $e');
    }
  }

  /// Run the multi-step character generation in the background.
  Future<void> _runChargenAsync({
    required CharacterGenService genService,
    required String name,
    required String concept,
    required String keywords,
    required String age,
    required String sex,
    required String relationship,
    required String greetingLength,
    required int altGreetingCount,
    required List<String> greetingTones,
    required bool generateLorebook,
    required List<String> loreCategories,
    required String loreDepth,
    required String descriptionDetail,
    required String backstory,
    required String characterContext,
    required String userPersonaContext,
    required String artStyle,
  }) async {
    try {
      final card = await genService.generateCharacter(
        name: name,
        concept: concept,
        personalityKeywords: keywords,
        artStyle: artStyle,
        greetingLength: greetingLength,
        altGreetingCount: altGreetingCount,
        greetingTones: greetingTones,
        generateLorebook: generateLorebook,
        loreCategories: loreCategories,
        loreDepth: loreDepth,
        age: age,
        sex: sex,
        relationship: relationship,
        descriptionDetail: descriptionDetail,
        backstory: backstory,
        characterContext: characterContext,
        userPersonaContext: userPersonaContext,
        onProgress: (accumulated) {
          _chargenBroadcast({'event': 'preview', 'text': accumulated});
        },
        onStatus: (status) {
          _chargenBroadcast({'event': 'status', 'text': status});
        },
        onError: (error) {
          _chargenBroadcast({'event': 'error', 'text': error});
        },
      );

      if (card == null) {
        _chargenBroadcast({
          'event': 'error',
          'text': 'Generation failed — LLM did not produce valid output.',
        });
        _isChargenRunning = false;
        return;
      }

      // Completion pass on greetings (check for truncation)
      final allGreetings = <String>[
        card.firstMessage,
        ...card.alternateGreetings,
      ];
      for (int gi = 0; gi < allGreetings.length; gi++) {
        String greeting = allGreetings[gi];
        final label = gi == 0 ? 'first message' : 'alt greeting $gi';
        _chargenBroadcast({
          'event': 'status',
          'text': 'Checking $label for truncation...',
        });
        final completed = await genService.editorCompletionPass(
          greeting,
          onProgress: (p) {
            _chargenBroadcast({'event': 'preview', 'text': p});
          },
        );
        if (completed != null) greeting = completed;
        allGreetings[gi] = greeting;
      }

      // Apply edited greetings back to card
      card.firstMessage = allGreetings[0];
      if (allGreetings.length > 1) {
        card.alternateGreetings = allGreetings.sublist(1);
      }

      // The LLM prompt doesn't generate a 'description' key — the user's
      // concept from Step 2 IS the description (matches Flutter app behavior).
      if (card.description.isEmpty && concept.isNotEmpty) {
        card.description = concept;
      }

      // Extract image prompt from the generation service (matches Flutter app)
      String imagePrompt = genService.generatedImagePrompt ?? '';

      if (imagePrompt.isEmpty && card.description.isNotEmpty) {
        // Fallback: build from description
        final desc = card.description.length > 400
            ? card.description.substring(0, 400)
            : card.description;
        imagePrompt = 'character portrait, $artStyle style, $desc';
      }

      // Build complete result
      final result = {
        'name': card.name,
        'description': card.description,
        'personality': card.personality,
        'scenario': card.scenario,
        'firstMessage': card.firstMessage,
        'mesExample': card.mesExample,
        'systemPrompt': card.systemPrompt,
        'alternateGreetings': card.alternateGreetings,
        'tags': card.tags,
        'imagePrompt': imagePrompt,
      };

      // Add lorebook if present
      if (card.lorebook != null) {
        result['lorebook'] = card.lorebook!.entries
            .map(
              (e) => {
                'name': e.name,
                'key': e.key,
                'content': e.content,
                'enabled': e.enabled,
              },
            )
            .toList();
      }

      _chargenBroadcast({'event': 'complete', 'card': result});
      _isChargenRunning = false;
    } catch (e) {
      debugPrint('[WebServer] Chargen error: $e');
      _chargenBroadcast({'event': 'error', 'text': 'Generation failed: $e'});
      _isChargenRunning = false;
    }
  }

  /// POST /api/chargen/avatar — Generate avatar image from prompt.
  Future<shelf.Response> _handleChargenAvatar(shelf.Request request) async {
    if (_imageGenService == null) {
      return _errorResponse(503, 'Image generation service not available');
    }
    if (!_imageGenService!.isConfigured) {
      return _errorResponse(
        503,
        'Image generation not configured — set API key and image model in Settings',
      );
    }

    try {
      final body = jsonDecode(await request.readAsString());
      final prompt = body['prompt']?.toString() ?? '';
      if (prompt.isEmpty) return _errorResponse(400, 'Prompt is required');

      final imageBytes = await _imageGenService!.generateImage(
        prompt: prompt,
        size: '512x512',
        isPortrait: true,
      );

      if (imageBytes == null) {
        return _errorResponse(
          500,
          'Image generation failed: ${_imageGenService!.statusMessage}',
        );
      }

      return shelf.Response.ok(
        jsonEncode({'status': 'ok', 'image': base64Encode(imageBytes)}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Avatar generation failed: $e');
    }
  }

  /// POST /api/chargen/save — Save generated character to database.
  Future<shelf.Response> _handleChargenSave(shelf.Request request) async {
    if (_db == null || _characterRepository == null) {
      return _errorResponse(503, 'Database not available');
    }

    try {
      final body = jsonDecode(await request.readAsString());
      final name = body['name']?.toString() ?? '';
      if (name.isEmpty) {
        return _errorResponse(400, 'Character name is required');
      }

      final description = body['description']?.toString() ?? '';
      final personality = body['personality']?.toString() ?? '';
      final scenario = body['scenario']?.toString() ?? '';
      final firstMessage = body['firstMessage']?.toString() ?? '';
      final mesExample = body['mesExample']?.toString() ?? '';
      final systemPrompt = body['systemPrompt']?.toString() ?? '';
      final altGreetings = List<String>.from(body['alternateGreetings'] ?? []);
      final tags = List<String>.from(body['tags'] ?? []);
      final avatarBase64 = body['avatar']?.toString() ?? '';

      // Parse lorebook
      String? lorebookJson;
      final lorebookData = body['lorebook'];
      if (lorebookData != null &&
          lorebookData is List &&
          lorebookData.isNotEmpty) {
        final entries = <Map<String, dynamic>>[];
        for (final entry in lorebookData) {
          if (entry is Map<String, dynamic>) {
            final enabled = entry['enabled'] as bool? ?? true;
            if (enabled) {
              entries.add({
                'keys': (entry['key']?.toString() ?? '')
                    .split(',')
                    .map((k) => k.trim())
                    .where((k) => k.isNotEmpty)
                    .toList(),
                'content': entry['content']?.toString() ?? '',
                'comment': entry['name']?.toString() ?? '',
                'enabled': true,
                'insertion_order': entries.length,
              });
            }
          }
        }
        if (entries.isNotEmpty) {
          lorebookJson = jsonEncode({'entries': entries});
        }
      }

      // Save avatar to disk
      String? imagePath;
      if (avatarBase64.isNotEmpty) {
        try {
          final avatarBytes = base64Decode(avatarBase64);
          final rootPath = _storageService.rootPath ?? '.';
          final charDir = Directory(p.join(rootPath, 'characters'));
          if (!charDir.existsSync()) charDir.createSync(recursive: true);

          final epoch = DateTime.now().millisecondsSinceEpoch;
          final safeName = name
              .replaceAll(RegExp(r'[^\w\s]'), '')
              .replaceAll(' ', '_');
          imagePath = p.join(charDir.path, '${safeName}_$epoch.png');
          await File(imagePath).writeAsBytes(avatarBytes);
        } catch (e) {
          debugPrint('[WebServer] Failed to save avatar: $e');
          // Continue without avatar
        }
      }

      final dbId = await _db!.insertCharacterReturningId(
        CharactersCompanion(
          name: Value(name),
          description: Value(description),
          personality: Value(personality),
          scenario: Value(scenario),
          firstMessage: Value(firstMessage),
          mesExample: Value(mesExample),
          systemPrompt: Value(systemPrompt),
          postHistoryInstructions: const Value(''),
          alternateGreetings: Value(jsonEncode(altGreetings)),
          tags: Value(jsonEncode(tags)),
          imagePath: Value(imagePath != null ? p.basename(imagePath) : null),
          ttsVoice: const Value(null),
          lorebook: Value(lorebookJson),
          worldNames: const Value('[]'),
        ),
      );

      // Refresh character list
      _characterRepository?.loadCharacters();

      return shelf.Response.ok(
        jsonEncode({'status': 'ok', 'id': dbId}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to save character: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // Image Gen proxy routes
  // ══════════════════════════════════════════════════════════════════════

  /// POST /api/image-gen/test-connection — Test a local SD server connection.
  Future<shelf.Response> _handleImgenTestConnection(
    shelf.Request request,
  ) async {
    if (_imageGenService == null) {
      return _errorResponse(503, 'Image gen service not available');
    }
    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final url = body['url']?.toString() ?? '';
      if (url.isEmpty) return _errorResponse(400, 'url is required');
      if (url.isNotEmpty &&
          !url.startsWith('http://127.0.0.1') &&
          !url.startsWith('http://localhost') &&
          !url.startsWith('http://[::1]')) {
        debugPrint(
          '[WebServer] rejected non-local url in _handleImgenTestConnection',
        );
        return _errorResponse(400, 'local urls only (127.0.0.1/localhost)');
      }
      final ok = await _imageGenService!.testLocalConnection(url);
      return shelf.Response.ok(
        jsonEncode({'ok': ok}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Connection test failed: $e');
    }
  }

  /// GET /api/image-gen/local-models?url=... — Fetch checkpoint list from local SD.
  Future<shelf.Response> _handleImgenLocalModels(shelf.Request request) async {
    if (_imageGenService == null) {
      return _errorResponse(503, 'Image gen service not available');
    }
    try {
      final url = request.url.queryParameters['url'] ?? '';
      final backend = request.url.queryParameters['backend'] ?? '';
      if (url.isEmpty) {
        return _errorResponse(400, 'url query param is required');
      }
      if (url.isNotEmpty &&
          !url.startsWith('http://127.0.0.1') &&
          !url.startsWith('http://localhost') &&
          !url.startsWith('http://[::1]')) {
        debugPrint(
          '[WebServer] rejected non-local url in _handleImgenLocalModels',
        );
        return _errorResponse(400, 'local urls only (127.0.0.1/localhost)');
      }

      final List<String> models;
      if (backend == 'drawthings') {
        models = await _imageGenService!.fetchDrawThingsModels(url);
      } else {
        models = await _imageGenService!.fetchA1111Models(url);
      }
      return shelf.Response.ok(
        jsonEncode({'models': models}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to fetch models: $e');
    }
  }

  /// GET /api/image-gen/loras?url=... — Fetch LoRA list from A1111/Forge/SDNext.
  Future<shelf.Response> _handleImgenLoras(shelf.Request request) async {
    if (_imageGenService == null) {
      return _errorResponse(503, 'Image gen service not available');
    }
    try {
      final url = request.url.queryParameters['url'] ?? '';
      if (url.isEmpty) {
        return _errorResponse(400, 'url query param is required');
      }
      if (url.isNotEmpty &&
          !url.startsWith('http://127.0.0.1') &&
          !url.startsWith('http://localhost') &&
          !url.startsWith('http://[::1]')) {
        debugPrint('[WebServer] rejected non-local url in _handleImgenLoras');
        return _errorResponse(400, 'local urls only (127.0.0.1/localhost)');
      }
      final loras = await _imageGenService!.fetchA1111Loras(url);
      return shelf.Response.ok(
        jsonEncode({'loras': loras}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to fetch LoRAs: $e');
    }
  }

  /// POST /api/image-gen/unload-model — Unload the current model from memory.
  Future<shelf.Response> _handleImgenUnloadModel(shelf.Request request) async {
    if (_imageGenService == null) {
      return _errorResponse(503, 'Image gen service not available');
    }
    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final url = body['url']?.toString() ?? '';
      if (url.isEmpty) return _errorResponse(400, 'url is required');
      if (url.isNotEmpty &&
          !url.startsWith('http://127.0.0.1') &&
          !url.startsWith('http://localhost') &&
          !url.startsWith('http://[::1]')) {
        debugPrint(
          '[WebServer] rejected non-local url in _handleImgenUnloadModel',
        );
        return _errorResponse(400, 'local urls only (127.0.0.1/localhost)');
      }
      final ok = await _imageGenService!.unloadLocalModel(url);
      return shelf.Response.ok(
        jsonEncode({
          'ok': ok,
          'message': ok ? 'Model unloaded' : 'Unload not supported by server',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Unload failed: $e');
    }
  }

  /// POST /api/image-gen/switch-model — Unload current model then load a new one.
  Future<shelf.Response> _handleImgenSwitchModel(shelf.Request request) async {
    if (_imageGenService == null) {
      return _errorResponse(503, 'Image gen service not available');
    }
    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final url = body['url']?.toString() ?? '';
      final model = body['model']?.toString() ?? '';
      if (url.isEmpty) return _errorResponse(400, 'url is required');
      if (model.isEmpty) return _errorResponse(400, 'model is required');
      if (url.isNotEmpty &&
          !url.startsWith('http://127.0.0.1') &&
          !url.startsWith('http://localhost') &&
          !url.startsWith('http://[::1]')) {
        debugPrint(
          '[WebServer] rejected non-local url in _handleImgenSwitchModel',
        );
        return _errorResponse(400, 'local urls only (127.0.0.1/localhost)');
      }
      final ok = await _imageGenService!.switchLocalModel(url, model);
      return shelf.Response.ok(
        jsonEncode({
          'ok': ok,
          'message': ok ? 'Switched to $model' : 'Switch failed',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Switch failed: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // Porch Stories handlers
  // ══════════════════════════════════════════════════════════════════════

  /// Broadcast an SSE event to all connected story pipeline clients.
  void _storyBroadcast(Map<String, dynamic> eventData) {
    final eventType = eventData['event']?.toString() ?? 'message';
    if (eventType == 'status') {
      _storyStatus = eventData['text']?.toString() ?? '';
    }
    if (eventType == 'token') {
      _storyStreamingText += eventData['text']?.toString() ?? '';
    }
    if (eventType == 'complete' || eventType == 'error') {
      _storyPipelineRunning = false;
    }

    _storySseClients.removeWhere((c) => c.isClosed);
    if (_storySseClients.isEmpty) return;
    final encoded = utf8.encode('data: ${jsonEncode(eventData)}\n\n');
    for (final client in _storySseClients) {
      if (!client.isClosed) client.add(encoded);
    }
  }

  /// GET /api/stories — List all story projects (summary only).
  Future<shelf.Response> _handleGetStories(shelf.Request request) async {
    if (_storyRepository == null) {
      return _errorResponse(503, 'Story service not available');
    }
    try {
      await _storyRepository!.loadProjects();
      final list = _storyRepository!.projects
          .map(
            (p) => {
              'id': p.dbId,
              'title': p.title,
              'concept': p.concept.length > 120
                  ? '${p.concept.substring(0, 120)}...'
                  : p.concept,
              'actCount': p.actCount,
              'updatedAt': p.updatedAt.toIso8601String(),
              'wordCount': _countWords(p),
            },
          )
          .toList();
      return shelf.Response.ok(
        jsonEncode(list),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to list stories: $e');
    }
  }

  int _countWords(story_model.StoryProject p) {
    int count = 0;
    for (final bp in p.prose.values) {
      final text = bp.final_ ?? bp.draft ?? '';
      if (text.isNotEmpty) count += text.split(RegExp(r'\s+')).length;
    }
    return count;
  }

  /// POST /api/stories/create — Create a new empty story project.
  Future<shelf.Response> _handleCreateStory(shelf.Request request) async {
    if (_storyRepository == null) {
      return _errorResponse(503, 'Story service not available');
    }
    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final title = body['title']?.toString() ?? 'Untitled Story';
      final project = await _storyRepository!.createProject(title: title);
      // Apply any additional fields from body
      if (body.containsKey('concept')) {
        project.concept = body['concept'].toString();
      }
      if (body['actCount'] != null) {
        project.actCount = (body['actCount'] as num).toInt();
      }
      if (body['pov'] != null) project.pov = body['pov'].toString();
      if (body['maturityRating'] != null) {
        project.maturityRating = body['maturityRating'].toString();
      }
      if (body['proseLength'] != null) {
        project.proseLength = body['proseLength'].toString();
      }
      if (body['narrativePace'] != null) {
        project.narrativePace = body['narrativePace'].toString();
      }
      if (body['dialogueDensity'] != null) {
        project.dialogueDensity = body['dialogueDensity'].toString();
      }
      if (body['writingStyle'] != null) {
        project.writingStyle = body['writingStyle'].toString();
      }
      if (body['selectedGenres'] != null) {
        project.selectedGenres = List<String>.from(
          body['selectedGenres'] as List,
        );
      }
      if (body['selectedMoods'] != null) {
        project.selectedMoods = List<String>.from(
          body['selectedMoods'] as List,
        );
      }
      if (body['characterCardSnapshots'] != null) {
        project.characterCardSnapshots =
            (body['characterCardSnapshots'] as List)
                .map(
                  (e) => (e as Map<String, dynamic>).map(
                    (k, v) => MapEntry(k, v.toString()),
                  ),
                )
                .toList();
      }
      await _storyRepository!.saveProject(project);
      return shelf.Response.ok(
        jsonEncode({'id': project.dbId, 'project': project.toJson()}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to create story: $e');
    }
  }

  /// POST /api/stories/update — Update an existing story project (full overwrite).
  Future<shelf.Response> _handleUpdateStory(shelf.Request request) async {
    if (_storyRepository == null) {
      return _errorResponse(503, 'Story service not available');
    }
    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final id = body['id']?.toString() ?? '';
      if (id.isEmpty) return _errorResponse(400, 'id is required');
      await _storyRepository!.loadProjects();
      final existing = _storyRepository!.getById(id);
      if (existing == null) return _errorResponse(404, 'Story not found');
      // Deserialize the incoming project JSON
      final updated = story_model.StoryProject.fromJson(
        body['project'] as Map<String, dynamic>,
      );
      updated.dbId = id;
      await _storyRepository!.saveProject(updated);
      return shelf.Response.ok(
        jsonEncode({'status': 'ok'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to update story: $e');
    }
  }

  /// POST /api/stories/delete — Delete a story project.
  Future<shelf.Response> _handleDeleteStory(shelf.Request request) async {
    if (_storyRepository == null) {
      return _errorResponse(503, 'Story service not available');
    }
    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final id = body['id']?.toString() ?? '';
      if (id.isEmpty) return _errorResponse(400, 'id is required');
      await _storyRepository!.deleteProject(id);
      return shelf.Response.ok(
        jsonEncode({'status': 'ok'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to delete story: $e');
    }
  }

  /// GET `/api/stories/<id>` — Get a full story project.
  Future<shelf.Response> _handleGetStory(
    shelf.Request request,
    String id,
  ) async {
    if (_storyRepository == null) {
      return _errorResponse(503, 'Story service not available');
    }
    try {
      await _storyRepository!.loadProjects();
      final project = _storyRepository!.getById(id);
      if (project == null) return _errorResponse(404, 'Story not found');
      return shelf.Response.ok(
        jsonEncode(project.toJson()..['id'] = id),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to get story: $e');
    }
  }

  /// GET `/api/stories/<id>/pipeline/stream` — SSE stream for pipeline progress.
  Future<shelf.Response> _handlePipelineStream(
    shelf.Request request,
    String id,
  ) async {
    final controller = StreamController<List<int>>();
    _storySseClients.add(controller);
    debugPrint(
      '[WebServer] Story SSE client connected (${_storySseClients.length} total)',
    );

    controller.onCancel = () {
      _storySseClients.remove(controller);
      debugPrint('[WebServer] Story SSE client disconnected');
    };

    return shelf.Response.ok(
      controller.stream,
      headers: {
        'Content-Type': 'text/event-stream',
        'Cache-Control': 'no-cache',
        'Connection': 'keep-alive',
        'Access-Control-Allow-Origin': '*',
      },
    );
  }

  /// GET `/api/stories/<id>/pipeline/status` — Polling fallback for pipeline state.
  Future<shelf.Response> _handlePipelineStatus(
    shelf.Request request,
    String id,
  ) async {
    return shelf.Response.ok(
      jsonEncode({
        'running': _storyPipelineRunning,
        'status': _storyStatus,
        'streamingText': _storyStreamingText,
        'currentId': _storyCurrentId,
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }

  /// POST `/api/stories/<id>/pipeline/run` — Start an async pipeline stage.
  Future<shelf.Response> _handleRunPipelineStage(
    shelf.Request request,
    String id,
  ) async {
    if (_storyRepository == null || _storyPipelineService == null) {
      return _errorResponse(503, 'Story service not available');
    }
    if (_storyPipelineRunning) {
      return _errorResponse(409, 'Pipeline already running');
    }

    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final stage = body['stage']?.toString() ?? '';
      if (stage.isEmpty) return _errorResponse(400, 'stage is required');

      await _storyRepository!.loadProjects();
      final project = _storyRepository!.getById(id);
      if (project == null) return _errorResponse(404, 'Story not found');

      _storyPipelineRunning = true;
      _storyCurrentId = id;
      _storyStatus = 'Starting $stage...';
      _storyStreamingText = '';

      // Patch the pipeline service's streaming text to broadcast tokens
      _storyPipelineService!.addListener(_onStoryPipelineUpdate);

      // Run asynchronously
      () async {
        try {
          final actIdx = (body['actIdx'] as num?)?.toInt() ?? 0;
          final sceneIdx = (body['sceneIdx'] as num?)?.toInt() ?? 0;
          final beatIdx = (body['beatIdx'] as num?)?.toInt() ?? 0;

          switch (stage) {
            case 'architect':
              await _storyPipelineService!.runStoryArchitect(project);
              break;
            case 'structure':
              await _storyPipelineService!.runActStructurer(project);
              break;
            case 'scenes':
              await _storyPipelineService!.runSceneWeaver(project, actIdx);
              break;
            case 'beats':
              await _storyPipelineService!.runBeatDirector(
                project,
                actIdx,
                sceneIdx,
              );
              break;
            case 'prose':
              await _storyPipelineService!.runDraftAndEdit(
                project,
                actIdx,
                sceneIdx,
                beatIdx,
              );
              break;
            case 'archivist':
              await _storyPipelineService!.runArchivist(
                project,
                actIdx,
                sceneIdx,
              );
              break;
            default:
              throw Exception('Unknown stage: $stage');
          }
          // Reload project from repo after pipeline updates it
          await _storyRepository!.loadProjects();
          final updated = _storyRepository!.getById(id);
          final projectJson = updated?.toJson() ?? {};
          projectJson['id'] = id;
          _storyBroadcast({'event': 'complete', 'project': projectJson});
        } catch (e) {
          debugPrint('[WebServer] Story pipeline error: $e');
          _storyBroadcast({'event': 'error', 'text': 'Pipeline failed: $e'});
        } finally {
          _storyPipelineService!.removeListener(_onStoryPipelineUpdate);
          _storyPipelineRunning = false;
        }
      }();

      return shelf.Response.ok(
        jsonEncode({'status': 'started', 'stage': stage}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      _storyPipelineRunning = false;
      return _errorResponse(500, 'Failed to start pipeline: $e');
    }
  }

  void _onStoryPipelineUpdate() {
    if (_storyPipelineService == null) return;
    final svc = _storyPipelineService!;
    _storyStatus = svc.statusMessage;
    // Forward streaming tokens
    if (svc.streamingText.isNotEmpty) {
      _storyBroadcast({
        'event': 'token',
        'text': svc.streamingText,
        'status': svc.statusMessage,
      });
    } else {
      _storyBroadcast({'event': 'status', 'text': svc.statusMessage});
    }
  }

  /// POST `/api/stories/<id>/prose/edit` — Save hand-edited prose for a beat.
  Future<shelf.Response> _handleProseEdit(
    shelf.Request request,
    String id,
  ) async {
    if (_storyRepository == null) {
      return _errorResponse(503, 'Story service not available');
    }
    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final actIdx = (body['actIdx'] as num?)?.toInt() ?? 0;
      final sceneIdx = (body['sceneIdx'] as num?)?.toInt() ?? 0;
      final beatIdx = (body['beatIdx'] as num?)?.toInt() ?? 0;
      final prose = body['prose']?.toString() ?? '';
      final key = '$actIdx-$sceneIdx-$beatIdx';

      await _storyRepository!.loadProjects();
      final project = _storyRepository!.getById(id);
      if (project == null) return _errorResponse(404, 'Story not found');

      final existing = project.prose[key] ?? story_model.BeatProse();
      project.prose[key] = story_model.BeatProse(
        draft: existing.draft,
        final_: prose,
      );
      await _storyRepository!.saveProject(project);

      return shelf.Response.ok(
        jsonEncode({'status': 'ok', 'key': key}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Failed to save prose: $e');
    }
  }

  /// POST `/api/stories/<id>/distill` — Run the chat history distiller.
  Future<shelf.Response> _handleDistillChatHistory(
    shelf.Request request,
    String id,
  ) async {
    if (_storyRepository == null || _storyPipelineService == null) {
      return _errorResponse(503, 'Story service not available');
    }
    if (_storyPipelineRunning) {
      return _errorResponse(409, 'Pipeline already running');
    }

    try {
      await _storyRepository!.loadProjects();
      final project = _storyRepository!.getById(id);
      if (project == null) return _errorResponse(404, 'Story not found');

      _storyPipelineRunning = true;
      _storyCurrentId = id;
      _storyPipelineService!.addListener(_onStoryPipelineUpdate);

      () async {
        try {
          await _storyPipelineService!.runChatDistiller(project);
          final pj = project.toJson();
          pj['id'] = id;
          _storyBroadcast({'event': 'complete', 'project': pj});
        } catch (e) {
          _storyBroadcast({
            'event': 'error',
            'text': 'Distillation failed: $e',
          });
        } finally {
          _storyPipelineService!.removeListener(_onStoryPipelineUpdate);
          _storyPipelineRunning = false;
        }
      }();

      return shelf.Response.ok(
        jsonEncode({'status': 'started'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      _storyPipelineRunning = false;
      return _errorResponse(500, 'Failed to start distillation: $e');
    }
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
