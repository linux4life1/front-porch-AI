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
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:provider/provider.dart';

import 'package:window_manager/window_manager.dart';
import 'package:front_porch_ai/providers/app_state.dart';
import 'package:front_porch_ai/ui/layout/main_layout.dart'; // Keep original import for MainLayout
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/open_router_service.dart';
import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/backend_manager.dart';
import 'package:front_porch_ai/services/model_manager.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/hardware_service.dart';
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/services/world_repository.dart';
import 'package:front_porch_ai/services/setup_service.dart';
import 'package:front_porch_ai/services/folder_service.dart';
import 'package:front_porch_ai/services/update_service.dart';
import 'package:front_porch_ai/services/group_chat_repository.dart';
import 'package:front_porch_ai/services/voice_manager.dart';
import 'package:front_porch_ai/services/tts_service.dart';
import 'package:front_porch_ai/services/stt_service.dart';
import 'package:front_porch_ai/services/cloud_sync_service.dart';
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/cloud_providers/webdav_provider.dart';
import 'package:front_porch_ai/services/cloud_providers/google_drive_provider.dart';
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/database/data_migration_service.dart';
import 'package:front_porch_ai/services/backup_service.dart';
import 'package:front_porch_ai/services/db_reunification_service.dart';
import 'package:front_porch_ai/services/embedding_service.dart';
import 'package:front_porch_ai/services/embedding_sidecar.dart';
import 'package:front_porch_ai/services/memory_service.dart';
import 'package:front_porch_ai/services/story_repository.dart';
import 'package:front_porch_ai/services/story_pipeline_service.dart';
import 'package:front_porch_ai/services/audiobook_generator_service.dart';
import 'package:front_porch_ai/services/file_consolidation_service.dart';

import 'package:front_porch_ai/ui/widgets/setup_overlay.dart';
import 'package:front_porch_ai/ui/widgets/remote_lock_overlay.dart';
import 'package:front_porch_ai/ui/dialogs/update_dialog.dart';
import 'package:front_porch_ai/services/web_server_service.dart';
import 'package:front_porch_ai/services/web_chat_bridge.dart';
import 'package:front_porch_ai/app_version.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  // Intercept SIGINT (Ctrl+C) and SIGTERM on Linux/macOS to prevent
  // the Flutter engine from doing an unclean teardown that triggers:
  //   "FlutterEngineRemoveView returned kInvalidArguments"
  //   "Segmentation fault (core dumped)"
  if (!Platform.isWindows) {
    ProcessSignal.sigint.watch().listen((_) {
      debugPrint('Caught SIGINT — exiting immediately.');
      exit(0);
    });
    ProcessSignal.sigterm.watch().listen((_) {
      debugPrint('Caught SIGTERM — exiting immediately.');
      exit(0);
    });
  }

  // Consolidate files BEFORE loading database or any configs.
  try {
    await FileConsolidationService.consolidate();
  } catch (e) {
    debugPrint('Fatal error during file consolidation: $e');
  }

  // Initialize database
  final db = await AppDatabase.instance();
  final needsMigration = !await DataMigrationService.isMigrated();

  // Run integrity check before anything else touches the DB
  final dbHealthy = await db.integrityCheck();
  _MyAppState._dbHealthy = dbHealthy;

  // Purge rows that were soft-deleted more than 30 days ago
  try {
    await db.purgeSoftDeletes();
  } catch (_) {}

  // Clean up legacy JSON files from pre-0.8.0 (idempotent, safe to run every startup)
  try {
    await DataMigrationService.cleanupLegacyFiles();
  } catch (_) {}

  WindowOptions windowOptions = const WindowOptions(
    size: Size(1280, 720),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
    await windowManager.setPreventClose(true);
  });
  runApp(
    MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: db),
        Provider<bool>.value(value: needsMigration), // migration flag
        ChangeNotifierProvider(create: (_) => AppState()),
        ChangeNotifierProvider(create: (_) => StorageService()),
        ChangeNotifierProxyProvider<StorageService, KoboldService>(
          create: (context) => KoboldService(
            Provider.of<StorageService>(context, listen: false),
          ),
          update: (context, storage, previous) =>
              previous ?? KoboldService(storage),
        ),
        ChangeNotifierProvider(create: (_) => HardwareService()),
        ChangeNotifierProxyProvider<StorageService, CharacterRepository>(
          create: (context) => CharacterRepository(
            db,
            Provider.of<StorageService>(context, listen: false),
          ),
          update: (context, storage, previous) =>
              previous ?? CharacterRepository(db, storage),
        ),
        ChangeNotifierProvider(create: (context) => UserPersonaService(db)),
        ChangeNotifierProvider(create: (context) => FolderService(db)),
        ChangeNotifierProxyProvider2<
          CharacterRepository,
          StorageService,
          WorldRepository
        >(
          create: (context) {
            final repo = WorldRepository(
              Provider.of<StorageService>(context, listen: false),
              db,
            );
            // Wire CharacterRepository for avatar path resolution
            repo.setCharacterRepository(
              Provider.of<CharacterRepository>(context, listen: false),
            );
            return repo;
          },
          update: (context, charRepo, storage, previous) {
            final newRepo = previous ?? WorldRepository(storage, db);
            // Re-wire CharacterRepository if changed
            newRepo.setCharacterRepository(charRepo);
            return newRepo;
          },
        ),
        ChangeNotifierProvider(create: (_) => EmbeddingSidecar()),
        ChangeNotifierProvider<EmbeddingService>(
          create: (context) => EmbeddingService(
            Provider.of<EmbeddingSidecar>(context, listen: false),
          ),
        ),
        ChangeNotifierProxyProvider<StorageService, BackendManager>(
          create: (context) => BackendManager(
            Provider.of<StorageService>(context, listen: false),
          ),
          update: (context, storage, previous) =>
              previous ?? BackendManager(storage),
        ),
        ChangeNotifierProxyProvider<StorageService, ModelManager>(
          create: (context) =>
              ModelManager(Provider.of<StorageService>(context, listen: false)),
          update: (context, storage, previous) =>
              previous ?? ModelManager(storage),
        ),
        ChangeNotifierProvider(create: (_) => OpenRouterService()),
        ChangeNotifierProxyProvider3<
          KoboldService,
          OpenRouterService,
          StorageService,
          LLMProvider
        >(
          create: (context) => LLMProvider(
            Provider.of<KoboldService>(context, listen: false),
            Provider.of<OpenRouterService>(context, listen: false),
            Provider.of<StorageService>(context, listen: false),
          ),
          update: (context, kobold, openRouter, storage, previous) =>
              previous ?? LLMProvider(kobold, openRouter, storage),
        ),
        ChangeNotifierProxyProvider4<
          KoboldService,
          UserPersonaService,
          StorageService,
          WorldRepository,
          ChatService
        >(
          create: (context) {
            final chatService = ChatService(
              Provider.of<KoboldService>(context, listen: false),
              Provider.of<UserPersonaService>(context, listen: false),
              Provider.of<StorageService>(context, listen: false),
              Provider.of<WorldRepository>(context, listen: false),
            );
            // Wire LLMProvider and CharacterRepository immediately at creation time
            chatService.setDatabase(db);
            chatService.setLLMProvider(
              Provider.of<LLMProvider>(context, listen: false),
            );
            chatService.setCharacterRepository(
              Provider.of<CharacterRepository>(context, listen: false),
            );
            // Wire MemoryService for RAG
            try {
              final sidecar = Provider.of<EmbeddingSidecar>(
                context,
                listen: false,
              );
              final embeddingService = EmbeddingService(sidecar);
              final memoryService = MemoryService(
                embeddingService,
                Provider.of<StorageService>(context, listen: false),
                db,
              );
              chatService.setMemoryService(memoryService);
            } catch (_) {}
            return chatService;
          },
          update: (context, kobold, persona, storage, worldRepo, previous) {
            if (previous != null) {
              // Re-wire dependencies on every update to stay in sync
              previous.setLLMProvider(
                Provider.of<LLMProvider>(context, listen: false),
              );
              previous.setCharacterRepository(
                Provider.of<CharacterRepository>(context, listen: false),
              );
              // Wire TtsService if available (it's registered later in the tree)
              try {
                previous.setTtsService(
                  Provider.of<TtsService>(context, listen: false),
                );
              } catch (_) {}
              return previous;
            }
            final chatService = ChatService(
              kobold,
              persona,
              storage,
              worldRepo,
            );
            chatService.setDatabase(db);
            chatService.setLLMProvider(
              Provider.of<LLMProvider>(context, listen: false),
            );
            chatService.setCharacterRepository(
              Provider.of<CharacterRepository>(context, listen: false),
            );
            return chatService;
          },
        ),
        ChangeNotifierProxyProvider<StorageService, GroupChatRepository>(
          create: (context) => GroupChatRepository(
            Provider.of<StorageService>(context, listen: false),
            db,
          ),
          update: (context, storage, previous) =>
              previous ?? GroupChatRepository(storage, db),
        ),
        ChangeNotifierProxyProvider3<
          StorageService,
          BackendManager,
          KoboldService,
          SetupService
        >(
          create: (context) => SetupService(
            Provider.of<StorageService>(context, listen: false),
            Provider.of<BackendManager>(context, listen: false),
            Provider.of<KoboldService>(context, listen: false),
          ),
          update: (context, storage, backend, kobold, previous) =>
              previous ?? SetupService(storage, backend, kobold),
        ),
        ChangeNotifierProvider(create: (_) => UpdateService()),
        ChangeNotifierProxyProvider<StorageService, VoiceManager>(
          create: (context) =>
              VoiceManager(Provider.of<StorageService>(context, listen: false)),
          update: (context, storage, previous) =>
              previous ?? VoiceManager(storage),
        ),
        ChangeNotifierProxyProvider2<StorageService, VoiceManager, TtsService>(
          create: (context) => TtsService(
            Provider.of<StorageService>(context, listen: false),
            Provider.of<VoiceManager>(context, listen: false),
          ),
          update: (context, storage, voiceManager, previous) =>
              previous ?? TtsService(storage, voiceManager),
        ),
        ChangeNotifierProxyProvider2<
          TtsService,
          StorageService,
          AudiobookGeneratorService
        >(
          create: (context) => AudiobookGeneratorService(
            Provider.of<TtsService>(context, listen: false),
            Provider.of<StorageService>(context, listen: false),
          ),
          update: (context, tts, storage, previous) =>
              previous ?? AudiobookGeneratorService(tts, storage),
        ),
        ChangeNotifierProxyProvider<StorageService, SttService>(
          create: (context) =>
              SttService(Provider.of<StorageService>(context, listen: false)),
          update: (context, storage, previous) {
            if (previous != null) {
              try {
                previous.setTtsService(
                  Provider.of<TtsService>(context, listen: false),
                );
              } catch (_) {}
            }
            return previous ?? SttService(storage);
          },
        ),
        ChangeNotifierProvider(create: (_) => CloudSyncService()),
        ChangeNotifierProxyProvider<StorageService, ImageGenService>(
          create: (context) {
            return ImageGenService(
              Provider.of<StorageService>(context, listen: false),
            );
          },
          update: (context, storage, previous) {
            return previous ?? ImageGenService(storage);
          },
        ),
        // Porch Stories: repository + pipeline must be above WebServerService
        ChangeNotifierProvider(
          create: (context) {
            final repo = StoryRepository(db);
            repo.loadProjects();
            return repo;
          },
        ),
        ChangeNotifierProxyProvider2<
          LLMProvider,
          StorageService,
          StoryPipelineService
        >(
          create: (context) {
            final llmProvider = Provider.of<LLMProvider>(
              context,
              listen: false,
            );
            final sidecar = Provider.of<EmbeddingSidecar>(
              context,
              listen: false,
            );
            final storage = Provider.of<StorageService>(context, listen: false);
            final embeddingService = EmbeddingService(sidecar);
            final memoryService = MemoryService(embeddingService, storage, db);
            final repo = Provider.of<StoryRepository>(context, listen: false);
            return StoryPipelineService(
              repo,
              llmProvider.activeService,
              memoryService,
              db,
            );
          },
          update: (context, llmProvider, storage, previous) {
            final sidecar = Provider.of<EmbeddingSidecar>(
              context,
              listen: false,
            );
            final embeddingService = EmbeddingService(sidecar);
            final memoryService = MemoryService(embeddingService, storage, db);
            final repo = Provider.of<StoryRepository>(context, listen: false);
            return StoryPipelineService(
              repo,
              llmProvider.activeService,
              memoryService,
              db,
            );
          },
        ),
        ChangeNotifierProxyProvider<StorageService, WebServerService>(
          create: (context) {
            final chatService = Provider.of<ChatService>(
              context,
              listen: false,
            );
            final ws = WebServerService(
              Provider.of<StorageService>(context, listen: false),
            );
            ws.setDatabase(db);
            ws.setCharacterRepository(
              Provider.of<CharacterRepository>(context, listen: false),
            );
            ws.setChatService(chatService);
            ws.setChatBridge(WebChatBridge(chatService));
            ws.setLLMProvider(Provider.of<LLMProvider>(context, listen: false));
            ws.setFolderService(
              Provider.of<FolderService>(context, listen: false),
            );
            ws.setTtsService(Provider.of<TtsService>(context, listen: false));
            ws.setUserPersonaService(
              Provider.of<UserPersonaService>(context, listen: false),
            );
            ws.setGroupChatRepository(
              Provider.of<GroupChatRepository>(context, listen: false),
            );
            ws.setCloudSyncService(
              Provider.of<CloudSyncService>(context, listen: false),
            );
            ws.setImageGenService(
              Provider.of<ImageGenService>(context, listen: false),
            );
            ws.setEmbeddingSidecar(
              Provider.of<EmbeddingSidecar>(context, listen: false),
            );
            ws.setStoryRepository(
              Provider.of<StoryRepository>(context, listen: false),
            );
            ws.setStoryPipelineService(
              Provider.of<StoryPipelineService>(context, listen: false),
            );
            return ws;
          },
          update: (context, storage, previous) {
            if (previous != null) {
              final chatService = Provider.of<ChatService>(
                context,
                listen: false,
              );
              previous.setChatService(chatService);
              previous.setCharacterRepository(
                Provider.of<CharacterRepository>(context, listen: false),
              );
              previous.setLLMProvider(
                Provider.of<LLMProvider>(context, listen: false),
              );
              previous.setFolderService(
                Provider.of<FolderService>(context, listen: false),
              );
              previous.setTtsService(
                Provider.of<TtsService>(context, listen: false),
              );
              previous.setUserPersonaService(
                Provider.of<UserPersonaService>(context, listen: false),
              );
              previous.setGroupChatRepository(
                Provider.of<GroupChatRepository>(context, listen: false),
              );
              previous.setCloudSyncService(
                Provider.of<CloudSyncService>(context, listen: false),
              );
              previous.setImageGenService(
                Provider.of<ImageGenService>(context, listen: false),
              );
              previous.setEmbeddingSidecar(
                Provider.of<EmbeddingSidecar>(context, listen: false),
              );
              previous.setStoryRepository(
                Provider.of<StoryRepository>(context, listen: false),
              );
              previous.setStoryPipelineService(
                Provider.of<StoryPipelineService>(context, listen: false),
              );
              return previous;
            }
            final chatService = Provider.of<ChatService>(
              context,
              listen: false,
            );
            final ws = WebServerService(storage);
            ws.setDatabase(db);
            ws.setCharacterRepository(
              Provider.of<CharacterRepository>(context, listen: false),
            );
            ws.setChatService(chatService);
            ws.setChatBridge(WebChatBridge(chatService));
            ws.setLLMProvider(Provider.of<LLMProvider>(context, listen: false));
            ws.setFolderService(
              Provider.of<FolderService>(context, listen: false),
            );
            ws.setTtsService(Provider.of<TtsService>(context, listen: false));
            ws.setUserPersonaService(
              Provider.of<UserPersonaService>(context, listen: false),
            );
            ws.setGroupChatRepository(
              Provider.of<GroupChatRepository>(context, listen: false),
            );
            ws.setCloudSyncService(
              Provider.of<CloudSyncService>(context, listen: false),
            );
            ws.setImageGenService(
              Provider.of<ImageGenService>(context, listen: false),
            );
            ws.setEmbeddingSidecar(
              Provider.of<EmbeddingSidecar>(context, listen: false),
            );
            ws.setStoryRepository(
              Provider.of<StoryRepository>(context, listen: false),
            );
            ws.setStoryPipelineService(
              Provider.of<StoryPipelineService>(context, listen: false),
            );
            return ws;
          },
        ),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WindowListener {
  static bool _dbHealthy = true; // set from main() before runApp
  bool _updateChecked = false;
  bool _isMigrating = false;
  bool _isDbCorrupt = false;
  List<File> _availableBackups = [];
  String _migrationStep = '';
  int _migrationCurrent = 0;
  int _migrationTotal = 1;

  // Reunification overlay state
  bool _isReunifying = false;
  String _reunifyStep = '';
  int _reunifyCurrent = 0;
  final int _reunifyTotal = 5;
  // Inline import choice (replaces showDialog to avoid MaterialLocalizations issue)
  Completer<bool>? _importChoiceCompleter;
  List<String> _importItems = [];

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    // Run migration after first frame, then reunification if needed
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _checkDbHealth();
      await _runMigrationIfNeeded();
      await _runReunificationIfNeeded();
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() async {
    // Stop KoboldCPP backend BEFORE destroying the window.
    // This prevents orphaned processes when the app closes.
    try {
      final koboldService = Provider.of<KoboldService>(context, listen: false);
      if (koboldService.isRunning) {
        await koboldService.stopKobold();
      }
    } catch (e) {
      debugPrint('AG_DEBUG: Error stopping Kobold on window close: $e');
    }

    // Run pending installer if user deferred the update
    if (UpdateService.isSupported) {
      final updateService = Provider.of<UpdateService>(context, listen: false);
      if (updateService.hasPendingInstaller) {
        await updateService.installOnClose();
      }
    }

    // Stop web server
    try {
      final webServer = Provider.of<WebServerService>(context, listen: false);
      if (webServer.isRunning) {
        await webServer.stop();
      }
    } catch (e) {
      debugPrint('AG_DEBUG: Error stopping web server on close: $e');
    }

    // Stop embedding sidecar
    try {
      final sidecar = Provider.of<EmbeddingSidecar>(context, listen: false);
      if (sidecar.isRunning) {
        await sidecar.stopServer();
      }
    } catch (e) {
      debugPrint('AG_DEBUG: Error stopping embedding sidecar on close: $e');
    }

    // On Linux and Windows, windowManager.destroy() can trigger a Flutter engine bug:
    //   "FlutterEngineRemoveView returned kInvalidArguments"
    //   "Segmentation fault (core dumped)" or a native crash popup on Windows 11.
    // Workaround: exit(0) after cleanup to bypass the buggy view teardown.
    if (Platform.isLinux || Platform.isWindows) {
      exit(0);
    } else {
      await windowManager.destroy();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        return MaterialApp(
          title: 'Front Porch AI',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: appState.darkMode ? Brightness.dark : Brightness.light,
            primarySwatch: Colors.blue,
            scaffoldBackgroundColor: appState.darkMode
                ? const Color(0xFF0F172A)
                : const Color(0xFFF3F4F6),
            cardColor: appState.darkMode
                ? const Color(0xFF1E293B)
                : Colors.white,
            textTheme: GoogleFonts.interTextTheme(Theme.of(context).textTheme)
                .apply(
                  bodyColor: appState.darkMode ? Colors.white : Colors.black87,
                  displayColor: appState.darkMode
                      ? Colors.white
                      : Colors.black87,
                ),
            useMaterial3: true,
          ),
          home: Builder(
            builder: (context) {
              // Trigger update check once after first build
              if (!_updateChecked) {
                _updateChecked = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _checkForUpdates(context);
                  _runCloudSync(context);
                  _autoStartWebServer(context);
                  // Start auto-backup (always on, every 10 minutes)
                  BackupService.startAutoBackup();
                  // Wire TtsService into ChatService (can't be done during provider
                  // creation because TtsService is registered later in the tree)
                  try {
                    final chatService = Provider.of<ChatService>(
                      context,
                      listen: false,
                    );
                    final tts = Provider.of<TtsService>(context, listen: false);
                    chatService.setTtsService(tts);
                  } catch (_) {}
                  // Wire UpdateService shutdown callback so child processes
                  // (KoboldCPP, web server, embedding sidecar) are stopped
                  // before exit(0) in installNow(), which bypasses onWindowClose.
                  try {
                    final updateService = Provider.of<UpdateService>(
                      context,
                      listen: false,
                    );
                    updateService.setShutdownCallback(() async {
                      try {
                        final kobold = Provider.of<KoboldService>(
                          context,
                          listen: false,
                        );
                        if (kobold.isRunning) await kobold.stopKobold();
                      } catch (_) {}
                      try {
                        final webServer = Provider.of<WebServerService>(
                          context,
                          listen: false,
                        );
                        if (webServer.isRunning) await webServer.stop();
                      } catch (_) {}
                      try {
                        final sidecar = Provider.of<EmbeddingSidecar>(
                          context,
                          listen: false,
                        );
                        if (sidecar.isRunning) await sidecar.stopServer();
                      } catch (_) {}
                    });
                  } catch (_) {}
                });
              }

              final storage = Provider.of<StorageService>(context);
              final width = MediaQuery.of(context).size.width;

              // Scale text relative to base design width of 1280px
              // Clamp responsive base between 0.85 and 1.5
              final responsiveScale = (width / 1280).clamp(0.85, 1.5);

              // Combine with user preference
              final effectiveScale = responsiveScale * storage.textScale;

              return MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(effectiveScale)),
                child: Stack(
                  children: [
                    const MainLayout(),
                    const SetupOverlay(),
                    const RemoteLockOverlay(),
                    if (_isDbCorrupt) _buildCorruptionOverlay(),
                    if (_isMigrating) _buildMigrationOverlay(),
                    if (_isReunifying) _buildReunificationOverlay(),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  // ── DB Health Check ─────────────────────────────────────────────────

  Future<void> _checkDbHealth() async {
    if (_dbHealthy) return;

    // DB is corrupt — load available backups and show overlay
    final backups = await BackupService.listBackups();
    if (mounted) {
      setState(() {
        _isDbCorrupt = true;
        _availableBackups = backups;
      });
    }
  }

  Widget _buildCorruptionOverlay() {
    return Positioned.fill(
      child: Material(
        color: const Color(0xFF0F172A),
        child: Center(
          child: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Warning icon
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.red.shade700, Colors.orange.shade600],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withValues(alpha: 0.3),
                        blurRadius: 24,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    size: 40,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 32),
                const Text(
                  'Database Issue Detected',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'An integrity check found possible corruption.\n'
                  'This can happen after a power failure or crash.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                if (_availableBackups.isNotEmpty) ...[
                  Container(
                    constraints: const BoxConstraints(maxHeight: 220),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Available Backups',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Flexible(
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: _availableBackups.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 4),
                            itemBuilder: (context, index) {
                              final backup = _availableBackups[index];
                              final stat = backup.statSync();
                              final age = DateTime.now().difference(
                                stat.modified,
                              );
                              final sizeKb = (stat.size / 1024).toStringAsFixed(
                                0,
                              );
                              String ageStr;
                              if (age.inDays > 0) {
                                ageStr = '${age.inDays}d ago';
                              } else if (age.inHours > 0) {
                                ageStr = '${age.inHours}h ago';
                              } else {
                                ageStr = '${age.inMinutes}m ago';
                              }
                              return InkWell(
                                onTap: () => _restoreBackup(backup),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.03),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.restore,
                                        size: 18,
                                        color: Colors.blueAccent.shade100,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          ageStr,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        '$sizeKb KB',
                                        style: TextStyle(
                                          color: Colors.white.withValues(
                                            alpha: 0.4,
                                          ),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.orange.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 18,
                          color: Colors.orange.shade300,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'No backups available to restore from.',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                // Continue anyway
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () {
                      if (mounted) setState(() => _isDbCorrupt = false);
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      foregroundColor: Colors.white.withValues(alpha: 0.6),
                    ),
                    child: const Text('Continue Without Restoring'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _restoreBackup(File backup) async {
    if (mounted) {
      setState(() {
        _isDbCorrupt = false;
        _isMigrating = true;
        _migrationStep = 'Restoring backup...';
        _migrationCurrent = 1;
        _migrationTotal = 2;
      });
    }

    try {
      await BackupService.restoreBackup(backup.path);

      if (mounted) {
        setState(() {
          _migrationStep = 'Reopening database...';
          _migrationCurrent = 2;
        });
      }

      // Re-open the database
      await AppDatabase.instance();

      if (mounted) {
        setState(() => _isMigrating = false);
      }

      debugPrint('[DB] Backup restored successfully from: ${backup.path}');
    } catch (e) {
      debugPrint('[DB] Backup restore failed: $e');
      if (mounted) {
        setState(() => _isMigrating = false);
      }
    }
  }

  // ── Data Migration ──────────────────────────────────────────────────

  Future<void> _runMigrationIfNeeded() async {
    final needsMigration = Provider.of<bool>(context, listen: false);
    if (!needsMigration) return;

    setState(() => _isMigrating = true);

    final db = Provider.of<AppDatabase>(context, listen: false);
    final migration = DataMigrationService(db);
    await migration.migrate(
      onProgress: (step, current, total) {
        if (mounted) {
          setState(() {
            _migrationStep = step;
            _migrationCurrent = current;
            _migrationTotal = total;
          });
        }
        debugPrint('DB Migration [$current/$total]: $step');
      },
    );

    if (mounted) {
      setState(() => _isMigrating = false);
    }
  }

  Widget _buildMigrationOverlay() {
    return Positioned.fill(
      child: Material(
        color: const Color(0xFF0F172A),
        child: Center(
          child: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // App icon
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.blueAccent.shade700, Colors.purpleAccent],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blueAccent.withValues(alpha: 0.3),
                        blurRadius: 24,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.storage_rounded,
                    size: 40,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 32),
                const Text(
                  'Migrating Your Data',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'This only happens once — your data is being\nupgraded to a faster database format.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 32),
                // Step name
                Text(
                  _migrationStep,
                  style: TextStyle(
                    color: Colors.blueAccent.shade100,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 12),
                // Progress bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: _migrationTotal > 0
                        ? _migrationCurrent / _migrationTotal
                        : null,
                    minHeight: 8,
                    backgroundColor: Colors.white.withValues(alpha: 0.1),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Colors.blueAccent.shade200,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Step counter
                Text(
                  'Step $_migrationCurrent of $_migrationTotal',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Reunification ──────────────────────────────────────────────────

  Future<void> _runReunificationIfNeeded() async {
    final dbDir = AppDatabase.dbDirPath;
    if (dbDir == null) return;
    if (await DbReunificationService.isComplete()) return;

    // Check if the stable backup exists (created by database.dart during promoteBetaDb)
    final stableBackupExists = File(
      '$dbDir/front_porch.db.pre-0.9.0-backup',
    ).existsSync();
    if (!stableBackupExists) return;

    setState(() {
      _isReunifying = true;
      _reunifyStep = 'Backing up your databases...';
      _reunifyCurrent = 1;
    });

    try {
      // Step 1: Backups (already done in database.dart, but show the step)
      await Future.wait([
        Future.value(), // backups already created
        Future.delayed(const Duration(seconds: 3)),
      ]);

      // Step 2: Preparing data
      if (mounted) {
        setState(() {
          _reunifyStep = 'Preparing your data...';
          _reunifyCurrent = 2;
        });
      }
      final db = Provider.of<AppDatabase>(context, listen: false);
      await Future.wait([
        BackupService.purgeAllBackups(), // purge old v1/v2 schema backups
        db.purgeDeletedRows(), // hard-delete soft-deleted bloat + VACUUM
        Future.delayed(const Duration(seconds: 3)),
      ]);

      // Step 3: Scanning for unique data
      if (mounted) {
        setState(() {
          _reunifyStep = 'Scanning for unique data...';
          _reunifyCurrent = 3;
        });
      }

      late final ReunificationDiff diff;
      await Future.wait([
        DbReunificationService.diffStableOnly(db, dbDir).then((d) => diff = d),
        Future.delayed(const Duration(seconds: 3)),
      ]);

      if (diff.isEmpty) {
        // Nothing to import — show success and finish
        if (mounted) {
          setState(() {
            _reunifyStep = 'All data accounted for ✅';
            _reunifyCurrent = 5;
          });
        }
        await Future.delayed(const Duration(seconds: 3));
        await DbReunificationService.markComplete();
        if (mounted) setState(() => _isReunifying = false);
        return;
      }

      // Step 4: Show import dialog
      if (mounted) {
        setState(() {
          _reunifyStep = 'Found unique data in your stable install';
          _reunifyCurrent = 4;
        });
      }

      // Build the description of what was found
      final items = <String>[];
      if (diff.characters.isNotEmpty) {
        final names = diff.characters.map((c) => c.name).join(', ');
        final sessions = diff.characters.fold<int>(
          0,
          (sum, c) => sum + c.sessionCount,
        );
        items.add('${diff.characters.length} character(s): $names');
        if (sessions > 0) items.add('$sessions chat session(s)');
      }
      if (diff.groups.isNotEmpty) {
        items.add('${diff.groups.length} group(s): ${diff.groups.join(', ')}');
      }
      if (diff.personas.isNotEmpty) {
        items.add(
          '${diff.personas.length} persona(s): ${diff.personas.join(', ')}',
        );
      }
      if (diff.worlds.isNotEmpty) {
        items.add('${diff.worlds.length} world(s): ${diff.worlds.join(', ')}');
      }

      // Show inline import choice inside the overlay (not showDialog)
      final completer = Completer<bool>();
      if (mounted) {
        setState(() {
          _importItems = items;
          _importChoiceCompleter = completer;
        });
      }
      final shouldImport = await completer.future;

      // Step 5: Import or finish
      // Clear the choice UI first
      if (mounted) {
        setState(() {
          _importChoiceCompleter = null;
          _importItems = [];
        });
      }

      if (shouldImport) {
        if (mounted) {
          final totalItems = diff.totalItems;
          setState(() {
            _reunifyStep = 'Importing $totalItems item(s)...';
            _reunifyCurrent = 5;
          });
        }

        await Future.wait([
          DbReunificationService.importStableItems(db, dbDir, diff),
          Future.delayed(const Duration(seconds: 3)),
        ]);

        // Reload all repositories
        if (mounted) {
          final charRepo = Provider.of<CharacterRepository>(
            context,
            listen: false,
          );
          final folderService = Provider.of<FolderService>(
            context,
            listen: false,
          );
          final personaService = Provider.of<UserPersonaService>(
            context,
            listen: false,
          );
          final groupRepo = Provider.of<GroupChatRepository>(
            context,
            listen: false,
          );
          final worldRepo = Provider.of<WorldRepository>(
            context,
            listen: false,
          );
          final chatService = Provider.of<ChatService>(context, listen: false);
          await charRepo.loadCharacters();
          await charRepo.cleanOrphanedPngs();
          await folderService.reload();
          await personaService.reload();
          await groupRepo.reload();
          await worldRepo.loadWorlds();
          await chatService.reloadCurrentSession();
        }

        if (mounted) {
          setState(() => _reunifyStep = 'Import complete ✅');
        }
        await Future.delayed(const Duration(seconds: 3));
      } else {
        if (mounted) {
          setState(() {
            _reunifyStep = 'Finishing up...';
            _reunifyCurrent = 5;
          });
        }
        await Future.delayed(const Duration(seconds: 2));
      }

      await DbReunificationService.markComplete();
    } catch (e) {
      debugPrint('[Reunification] Error: $e');
      // Mark complete anyway to avoid infinite retry loops
      await DbReunificationService.markComplete();
    } finally {
      if (mounted) setState(() => _isReunifying = false);
    }
  }

  Widget _buildReunificationOverlay() {
    return Positioned.fill(
      child: Material(
        color: const Color(0xFF0F172A),
        child: Center(
          child: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // App icon
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.blueAccent.shade700,
                        Colors.cyanAccent.shade400,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blueAccent.withValues(alpha: 0.3),
                        blurRadius: 24,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.merge_type_rounded,
                    size: 40,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 32),
                const Text(
                  'Upgrading to v0.9.0',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Merging your beta and stable databases\ninto a single unified database.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 32),

                // Inline import choice (shown at step 4)
                if (_importChoiceCompleter != null) ...[
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.blueAccent.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Import Stable Data?',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'We found data in your stable v0.8 install that isn\'t in your v0.9 database:',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ..._importItems.map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '• ',
                                  style: TextStyle(
                                    color: Colors.blueAccent,
                                    fontSize: 13,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    item,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Your v0.9 data is safe regardless of your choice.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.4),
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () =>
                                  _importChoiceCompleter?.complete(false),
                              child: const Text(
                                'Skip',
                                style: TextStyle(color: Colors.white38),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              onPressed: () =>
                                  _importChoiceCompleter?.complete(true),
                              icon: const Icon(
                                Icons.download_rounded,
                                size: 18,
                              ),
                              label: const Text('Import'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blueAccent,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  // Step name
                  Text(
                    _reunifyStep,
                    style: TextStyle(
                      color: Colors.blueAccent.shade100,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Progress bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: _reunifyTotal > 0
                          ? _reunifyCurrent / _reunifyTotal
                          : null,
                      minHeight: 8,
                      backgroundColor: Colors.white.withValues(alpha: 0.1),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Colors.blueAccent.shade200,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Step counter
                  Text(
                    'Step $_reunifyCurrent of $_reunifyTotal',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _checkForUpdates(BuildContext context) async {
    final updateService = Provider.of<UpdateService>(context, listen: false);
    await updateService.initialize();

    // Only check for updates on platforms that support self-update
    if (!UpdateService.isSupported) return;
    if (!updateService.autoCheckEnabled) return;

    final hasUpdate = await updateService.checkForUpdate();
    if (hasUpdate && context.mounted) {
      UpdateDialog.show(context);
    }
  }

  Future<void> _runCloudSync(BuildContext context) async {
    // Wait for reunification to finish before syncing — they share the DB
    while (_isReunifying) {
      await Future.delayed(const Duration(milliseconds: 500));
    }

    // Pre-release builds must not sync to prevent schema version conflicts
    if (isPreRelease) {
      debugPrint(
        '[CloudSync] Skipped — pre-release build uses separate beta DB',
      );
      return;
    }

    final storage = Provider.of<StorageService>(context, listen: false);
    await storage.initialized;
    if (!storage.cloudSyncEnabled || storage.cloudSyncProvider == 'none')
      return;

    final syncService = Provider.of<CloudSyncService>(context, listen: false);

    // Wire cloud sync service into ChatService
    final chatService = Provider.of<ChatService>(context, listen: false);
    chatService.setCloudSyncService(syncService);

    // Create and connect the appropriate provider
    CloudStorageProvider provider;
    switch (storage.cloudSyncProvider) {
      case 'webdav':
        provider = WebDavProvider();
        break;
      case 'gdrive':
        provider = GoogleDriveProvider();
        break;
      default:
        return;
    }

    try {
      await provider.connect({
        'url': storage.cloudSyncUrl,
        'username': storage.cloudSyncUsername,
        'password': storage.cloudSyncPassword,
      });
      syncService.setProvider(provider);

      // Get paths
      final chatsPath = storage.chatsDir.path;
      final rootPath = storage.rootPath ?? chatsPath;
      final charactersPath =
          '$rootPath${Platform.pathSeparator}KoboldManager${Platform.pathSeparator}Characters';

      // Safety net: backup DB before every cloud sync
      await BackupService.createBackup();
      await BackupService.pruneBackups();

      // Purge any accumulated soft-deleted rows before sync
      final db = await AppDatabase.instance();
      await db.purgeDeletedRows();

      await syncService.fullSync(chatsPath, charactersPath);

      // Check for schema version mismatch (e.g. newer UUID schema on another device)
      if (syncService.schemaMismatch) {
        // Disable cloud sync so it doesn't keep failing
        await storage.setCloudSyncEnabled(false);

        if (context.mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              title: const Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.amberAccent,
                    size: 28,
                  ),
                  SizedBox(width: 12),
                  Text(
                    'Database Version Mismatch',
                    style: TextStyle(color: Colors.white),
                  ),
                ],
              ),
              content: Text(
                'The cloud database was created by a newer version of Front Porch AI '
                '(schema v${syncService.remoteSchemaVersion}) and is incompatible with '
                'this version (schema v${syncService.localSchemaVersion}).\n\n'
                'Cloud sync has been disabled to prevent data corruption.\n\n'
                'Please update this app to the latest version, then re-enable cloud sync in Settings.',
                style: const TextStyle(color: Colors.white70, height: 1.5),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text(
                    'OK',
                    style: TextStyle(color: Colors.blueAccent),
                  ),
                ),
              ],
            ),
          );
        }
        return;
      }

      // Check for pending schema upgrade (old cloud DB downloaded and migrated locally)
      if (syncService.pendingSchemaUpgrade) {
        // The DB was downloaded and migrated — reload all repositories
        if (syncService.dbWasDownloaded) {
          debugPrint(
            '[CloudSync] Schema upgrade: reloading all repositories after migration',
          );
          final newDb = await AppDatabase.instance();
          final charRepo = Provider.of<CharacterRepository>(
            context,
            listen: false,
          );
          final folderService = Provider.of<FolderService>(
            context,
            listen: false,
          );
          final personaService = Provider.of<UserPersonaService>(
            context,
            listen: false,
          );
          final groupRepo = Provider.of<GroupChatRepository>(
            context,
            listen: false,
          );
          final worldRepo = Provider.of<WorldRepository>(
            context,
            listen: false,
          );
          charRepo.updateDatabase(newDb);
          folderService.updateDatabase(newDb);
          personaService.updateDatabase(newDb);
          groupRepo.updateDatabase(newDb);
          worldRepo.updateDatabase(newDb);
          chatService.updateDatabase(newDb);
          await charRepo.loadCharacters();
          await charRepo.cleanOrphanedPngs();
          await folderService.reload();
          await personaService.reload();
          await groupRepo.reload();
          await worldRepo.loadWorlds();
          await chatService.reloadCurrentSession();
        }

        // Show confirmation dialog before uploading v3 DB to cloud
        if (context.mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              title: const Row(
                children: [
                  Icon(
                    Icons.upgrade_rounded,
                    color: Colors.amberAccent,
                    size: 28,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Database Upgrade',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
              content: Text(
                'Your cloud database has been migrated from schema v${syncService.remoteSchemaVersion} '
                'to v${syncService.localSchemaVersion} on this device.\n\n'
                'If you upload the upgraded database to the cloud, any other devices running '
                'an older version of this app will no longer be able to sync until they are updated.\n\n'
                'Would you like to upload now?',
                style: const TextStyle(color: Colors.white70, height: 1.5),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text(
                    'Later',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    try {
                      await syncService.forceUploadDatabase();
                      await storage.setCloudSyncLastTime(
                        DateTime.now().toIso8601String(),
                      );
                    } catch (e) {
                      debugPrint('Schema upgrade upload failed: $e');
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amberAccent,
                    foregroundColor: Colors.black87,
                  ),
                  child: const Text('Upload Now'),
                ),
              ],
            ),
          );
        }
        return;
      }

      if (syncService.status == SyncStatus.success) {
        await storage.setCloudSyncLastTime(DateTime.now().toIso8601String());
        // Reload characters so newly downloaded PNGs appear in the UI
        final charRepo = Provider.of<CharacterRepository>(
          context,
          listen: false,
        );
        await charRepo.loadCharacters();
        await charRepo.cleanOrphanedPngs();

        // If a new database was downloaded, update all repo DB references and reload
        if (syncService.dbWasDownloaded) {
          debugPrint(
            '[CloudSync] DB was downloaded — updating all repositories',
          );
          final newDb = await AppDatabase.instance();

          // Push the new DB connection to every repo
          charRepo.updateDatabase(newDb);
          final folderService = Provider.of<FolderService>(
            context,
            listen: false,
          );
          final personaService = Provider.of<UserPersonaService>(
            context,
            listen: false,
          );
          final groupRepo = Provider.of<GroupChatRepository>(
            context,
            listen: false,
          );
          final worldRepo = Provider.of<WorldRepository>(
            context,
            listen: false,
          );
          folderService.updateDatabase(newDb);
          personaService.updateDatabase(newDb);
          groupRepo.updateDatabase(newDb);
          worldRepo.updateDatabase(newDb);
          chatService.updateDatabase(newDb);

          // Now reload all data from the new DB
          await charRepo.loadCharacters();
          await charRepo.cleanOrphanedPngs();
          await folderService.reload();
          await personaService.reload();
          await groupRepo.reload();
          await worldRepo.loadWorlds();
          await chatService.reloadCurrentSession();
        }
      }
    } catch (e) {
      debugPrint('Cloud sync startup error: \$e');
    }
  }

  Future<void> _autoStartWebServer(BuildContext context) async {
    final storage = Provider.of<StorageService>(context, listen: false);
    await storage.initialized;
    if (!storage.webServerEnabled) return;

    final webServer = Provider.of<WebServerService>(context, listen: false);
    await webServer.start(storage.webServerPort);
  }
}
