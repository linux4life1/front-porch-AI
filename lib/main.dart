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
// Hide `Size`: dart:ffi exports a `Size` type that collides with Flutter's
// `Size`. `hide` (not `show`) keeps the `lookupFunction` extension in scope.
import 'dart:ffi' hide Size;
import 'dart:io';
import 'dart:ui' show AppExitResponse;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:provider/provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' as riverpod;

import 'package:window_manager/window_manager.dart';
// screen_retriever is a transitive dep of window_manager (used here to validate
// that restored window bounds are actually visible on a connected display).
// ignore: depend_on_referenced_packages
import 'package:screen_retriever/screen_retriever.dart';
import 'package:front_porch_ai/providers/app_state.dart';
import 'package:front_porch_ai/providers/auth_state.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/services/backporch/backporch.dart';
import 'package:front_porch_ai/ui/layout/main_layout.dart'; // Keep original import for MainLayout
import 'package:front_porch_ai/app_version.dart';
import 'package:front_porch_ai/utils/native_exit.dart';
import 'package:front_porch_ai/database/database.dart';
// ignore: unused_import — used in the commented-out auto-cleanup block below
import 'package:front_porch_ai/database/database_cleanup.dart';
import 'package:front_porch_ai/database/data_migration_service.dart';

// Barrel imports for the most common services and widgets used directly in main.dart
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

// Services and modules not yet in the services barrel (internal, low-frequency, or side-effect heavy)
import 'package:front_porch_ai/services/model_manager.dart';
import 'package:front_porch_ai/services/download_manager.dart';
import 'package:front_porch_ai/services/setup_service.dart';
import 'package:front_porch_ai/services/db_reunification_service.dart';
import 'package:front_porch_ai/services/embedding_service.dart';
import 'package:front_porch_ai/services/memory_service.dart';
import 'package:front_porch_ai/services/audiobook_generator_service.dart';
import 'package:front_porch_ai/services/file_consolidation_service.dart';
import 'package:front_porch_ai/services/web/web_server_host.dart';

// Dialogs and specific widgets used only in main.dart (direct imports are appropriate)
import 'package:front_porch_ai/ui/dialogs/update_dialog.dart';
import 'package:front_porch_ai/ui/dialogs/stable_db_import_dialog.dart';

/// Prefix SharedPreferences keys for beta builds so window state is
/// isolated from the stable installation.  Unchanged for stable builds.
String _k(String key) => isPreRelease ? 'beta_$key' : key;

/// True when a meaningful chunk of the given window rect overlaps at least one
/// connected display's visible area — i.e. the window would actually be
/// reachable on screen if we restored it there.
///
/// This is the guard for GitHub issue #78: on Windows, closing the app while
/// the window is *minimized* makes `getPosition()` return the Win32 minimized
/// sentinel (~ -32000, -32000). Without this check that poisoned coordinate was
/// written to `window_x`/`window_y` and, on the next launch, `setBounds` placed
/// the window far off-screen — it appeared only as an unreachable taskbar icon
/// that WIN+arrow / ALT+Enter could not recover. Because SharedPreferences on
/// Windows lives outside the app's data folders, uninstalling did not clear it,
/// so the break survived a full reinstall. Rejecting off-screen bounds here
/// self-heals those already-affected installs (we fall back to the centered
/// default) as well as any window stranded by a since-disconnected monitor.
Future<bool> _windowBoundsVisible(Rect bounds) async {
  // Cheap, dependency-free rejection of the Win32 minimized sentinel first —
  // this is also the fallback if display enumeration throws below.
  const double kOffscreenSentinel = -30000;
  if (bounds.left <= kOffscreenSentinel || bounds.top <= kOffscreenSentinel) {
    return false;
  }
  try {
    final displays = await screenRetriever.getAllDisplays();
    for (final d in displays) {
      final origin = d.visiblePosition ?? Offset.zero;
      final size = d.visibleSize ?? d.size;
      final screen = Rect.fromLTWH(
        origin.dx,
        origin.dy,
        size.width,
        size.height,
      );
      final overlap = bounds.intersect(screen);
      // Require a grabbable chunk (roughly the title bar + a corner) to be
      // visible, so a 1px sliver peeking onto a screen still counts as lost.
      if (overlap.width > 120 && overlap.height > 60) return true;
    }
    return false;
  } catch (e) {
    // Display enumeration failed (rare, pre-runApp). We already ruled out the
    // sentinel above, so trust the saved bounds rather than fighting the OS.
    debugPrint('Failed to enumerate displays for window restore: $e');
    return true;
  }
}

/// Sets SIGPIPE to SIG_IGN via libc so a write to a closed socket/pipe fails
/// with a normal, catchable `SocketException` instead of silently killing the
/// whole process (SIGPIPE's default disposition). No-op on Windows (no SIGPIPE)
/// and best-effort everywhere else — a lookup failure just leaves the default.
void _ignoreSigpipe() {
  if (Platform.isWindows) return;
  try {
    // int signal(int signum, sighandler_t handler); SIG_IGN == (void*)1,
    // SIGPIPE == 13 on both macOS (Darwin) and Linux.
    final signal = DynamicLibrary.process().lookupFunction<
        Pointer<Void> Function(Int32, Pointer<Void>),
        Pointer<Void> Function(int, Pointer<Void>)>('signal');
    signal(13, Pointer<Void>.fromAddress(1));
  } catch (e) {
    debugPrint('Could not set SIG_IGN for SIGPIPE: $e');
  }
}

/// Last-resort screen shown when the database can't be opened at startup (disk
/// full, no write permission, or another copy of the app holding the file).
/// Deliberately self-contained — it runs before the theme/AppColors exist, so
/// it hardcodes a dark bootstrap palette rather than depend on any provider.
class _DbInitErrorApp extends StatelessWidget {
  const _DbInitErrorApp({required this.details});

  final String details;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.storage_rounded,
                  color: Colors.orangeAccent,
                  size: 48,
                ),
                const SizedBox(height: 16),
                const Text(
                  "Front Porch AI couldn't open its database",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'This is usually a full disk, missing write permission, or '
                  'another copy of Front Porch AI already running. Free up '
                  'space, close any other copies, then reopen the app.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 20),
                Text(
                  details,
                  textAlign: TextAlign.center,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  // Intercept SIGINT (Ctrl+C) and SIGTERM on Linux/macOS to prevent
  // the Flutter engine from doing an unclean teardown that triggers:
  //   "FlutterEngineRemoveView returned kInvalidArguments"
  //   "Segmentation fault (core dumped)"
  // On macOS the exit must also skip C++ finalizers (see
  // exitWithoutNativeFinalizers) or the abort-in-destructor crash fires here
  // too and the signal-quit gets logged as "Abort trap: 6".
  if (!Platform.isWindows) {
    ProcessSignal.sigint.watch().listen((_) {
      debugPrint('Caught SIGINT — exiting immediately.');
      Platform.isMacOS ? exitWithoutNativeFinalizers(0) : exit(0);
    });
    ProcessSignal.sigterm.watch().listen((_) {
      debugPrint('Caught SIGTERM — exiting immediately.');
      Platform.isMacOS ? exitWithoutNativeFinalizers(0) : exit(0);
    });
  }
  // Ignore SIGPIPE at the C level. A write to a socket/pipe whose peer has
  // already closed (a dropped web-server connection, the mDNSResponder/Tailscale
  // sockets used when serving over the LAN or a tailnet, a subprocess stdio pipe)
  // raises SIGPIPE, whose default disposition SILENTLY terminates the whole
  // process with no crash report — the "app just vanishes from the dock when I
  // toggle the web server on" bug in the signed/notarized build. The standalone
  // Dart VM sets SIG_IGN for us (so `flutter run` never showed it), but the
  // Flutter embedder leaves the default in place. dart:io deliberately REFUSES
  // to watch SIGPIPE, so we set the disposition directly via libc.
  _ignoreSigpipe();

  // Consolidate files BEFORE loading database or any configs.
  try {
    await FileConsolidationService.consolidate();
  } catch (e) {
    debugPrint('Fatal error during file consolidation: $e');
  }

  // Initialize database. This is the last thing that can die BEFORE any window
  // exists — a disk-full/permissions failure, or a second copy of the app
  // holding the file (the documented dual-run case), would otherwise exit the
  // process silently ("app won't launch, no message"). Guard it and, on a
  // hard failure, show a minimal error window instead of nothing.
  // (NativeDatabase.createInBackground opens lazily, so a bad/locked file
  // surfaces at the first query — integrityCheck — not at instance().)
  final AppDatabase db;
  final bool needsMigration;
  final bool dbHealthy;
  try {
    db = await AppDatabase.instance();
    needsMigration = !await DataMigrationService.isMigrated();
    dbHealthy = await db.integrityCheck();
  } catch (e, st) {
    debugPrint('[DB] FATAL: could not open the database: $e\n$st');
    runApp(_DbInitErrorApp(details: e.toString()));
    return;
  }
  _MyAppState._dbHealthy = dbHealthy;

  // Purge rows that were soft-deleted more than 30 days ago
  try {
    await db.purgeSoftDeletes();
  } catch (_) {}

  // Clean up legacy JSON files from pre-0.8.0 (idempotent, safe to run every startup)
  try {
    await DataMigrationService.cleanupLegacyFiles();
  } catch (_) {}

  // TODO: Enable after verifying DatabaseCleanup behaves correctly in production
  // try {
  //   final report = await DatabaseCleanup.checkOrphans(db);
  //   if (report.totalOrphans > 0 || report.totalBrokenRefs > 0) {
  //     debugPrint('[DB] Found ${report.totalOrphans + report.totalBrokenRefs}'
  //         ' orphaned records — running cleanup');
  //     await DatabaseCleanup.cleanOrphans(db);
  //   }
  // } catch (e) {
  //   debugPrint('[DB] Orphan cleanup failed: $e (non-fatal)');
  // }

  WindowOptions windowOptions = const WindowOptions(
    size: Size(1280, 720),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
    title: 'Front Porch AI',
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    // Restore saved window state (size, position, maximized)
    try {
      final prefs = await SharedPreferences.getInstance();
      final windowWidth = prefs.getDouble(_k('window_width'));
      final windowHeight = prefs.getDouble(_k('window_height'));
      final windowX = prefs.getDouble(_k('window_x'));
      final windowY = prefs.getDouble(_k('window_y'));
      final windowMaximized = prefs.getBool(_k('window_maximized')) ?? false;

      // NOTE: Users upgrading from builds before PR #53 may have saved
      // full-screen rect values in window_* prefs (old code used
      // unconditional getSize() in onWindowClose regardless of maximize
      // state). setBounds(fullscreen) + maximize() could in theory
      // reproduce ghosting, but setBounds to the already-maximized size
      // is a no-op and the bug doesn't trigger. Even without this defense,
      // the stale values self-heal on the first non-maximized close (which
      // saves correct bounds).
      //
      // Validate the saved rect is actually visible on a connected display
      // before applying it (issue #78 — see _windowBoundsVisible). If it
      // isn't (Win32 minimized sentinel, or a monitor that has since been
      // unplugged), we skip setBounds and fall through to the centered
      // default from WindowOptions instead of stranding the window off-screen.
      Rect? savedBounds;
      if (windowX != null &&
          windowY != null &&
          windowWidth != null &&
          windowHeight != null) {
        final candidate = Rect.fromLTWH(
          windowX,
          windowY,
          windowWidth,
          windowHeight,
        );
        if (await _windowBoundsVisible(candidate)) {
          savedBounds = candidate;
        }
      }

      if (windowMaximized) {
        // Restore the non-maximized bounds first (so the OS remembers
        // the correct "restore down" size), then maximize. This never
        // puts the window at full-screen size in non-maximized state,
        // which was the root cause of the Windows ghost frame issue.
        if (savedBounds != null) {
          await windowManager.setBounds(savedBounds);
        }
        await windowManager.maximize();
      } else if (savedBounds != null) {
        // Restore saved position + size
        await windowManager.setBounds(savedBounds);
      }
    } catch (e) {
      debugPrint('Failed to restore window state: $e');
    }

    await windowManager.show();
    await windowManager.focus();
    await windowManager.setPreventClose(true);
  });
  runApp(
    // ProviderScope: Riverpod root for new-code state (CLAUDE.md Riverpod
    // migration; first consumer: Living Time weather). Wraps the existing
    // Provider tree without touching service init order — legacy providers
    // below are unchanged.
    riverpod.ProviderScope(
      child: MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: db),
        Provider<bool>.value(value: needsMigration), // migration flag
        ChangeNotifierProvider(create: (_) => StorageService()),
        // AppState owns only transient UI state (selected tab index).
        // Theme / dark mode is now driven exclusively by StorageService (single source of truth,
        // persisted, notifies after async prefs load). This eliminates the prior race + glue bugs.
        ChangeNotifierProvider(create: (_) => AppState()),
        // Repository (Backporch) account session. Lazy — constructed + restored
        // only when the Repository page is first opened, so users who never
        // touch the online hub pay nothing and make no network calls.
        ChangeNotifierProvider(create: (_) => AuthState()..init()),
        ChangeNotifierProxyProvider<StorageService, DownloadManager>(
          create: (context) => DownloadManager(
            targetDir: Provider.of<StorageService>(
              context,
              listen: false,
            ).modelsDir.path,
          ),
          // Re-point the target dir on every storage notify (notably the one
          // after async init sets rootPath) so downloads always land in the
          // configured models folder, not a relative path captured at create.
          update: (context, storage, previous) =>
              (previous ?? DownloadManager(targetDir: storage.modelsDir.path))
                ..targetDir = storage.modelsDir.path,
        ),
        ChangeNotifierProxyProvider<StorageService, KoboldService>(
          create: (context) => KoboldService(
            Provider.of<StorageService>(context, listen: false),
          ),
          update: (context, storage, previous) =>
              previous ?? KoboldService(storage),
        ),
        ChangeNotifierProvider(create: (_) => HardwareService()),
        // Anonymous, opt-out app analytics. Lazy like AuthState — only built
        // when the Stoop is first opened (RepositoryPage reads it), so users who
        // never touch the hub make no network calls. It listens to AuthState and
        // pings once per launch when signed in and analytics is enabled.
        Provider<StoopAnalytics>(
          create: (ctx) => StoopAnalytics(
            ctx.read<AuthState>(),
            ctx.read<HardwareService>(),
          ),
          dispose: (_, s) => s.dispose(),
        ),
        ChangeNotifierProxyProvider<StorageService, CharacterRepository>(
          create: (context) => CharacterRepository(
            db,
            Provider.of<StorageService>(context, listen: false),
          ),
          update: (context, storage, previous) =>
              previous ?? CharacterRepository(db, storage),
        ),
        ChangeNotifierProvider(create: (context) => UserPersonaService(db)),
        // GroupChatRepository early (before ChatService) so the DI wiring in ChatService
        // create/update can successfully Provider.of it. Critical for the decoupled
        // member loading fallback in setActiveGroup.
        ChangeNotifierProxyProvider<StorageService, GroupChatRepository>(
          create: (context) => GroupChatRepository(
            Provider.of<StorageService>(context, listen: false),
            db,
          ),
          update: (context, storage, previous) =>
              previous ?? GroupChatRepository(storage, db),
        ),
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
        ChangeNotifierProvider<EmbeddingService>(
          create: (context) => EmbeddingService(
            Provider.of<StorageService>(context, listen: false),
          ),
        ),
        ChangeNotifierProxyProvider<StorageService, BackendManager>(
          create: (context) => BackendManager(
            Provider.of<StorageService>(context, listen: false),
          ),
          update: (context, storage, previous) =>
              previous ?? BackendManager(storage),
        ),
        ChangeNotifierProxyProvider2<
          StorageService,
          DownloadManager,
          ModelManager
        >(
          create: (context) => ModelManager(
            Provider.of<StorageService>(context, listen: false),
            Provider.of<DownloadManager>(context, listen: false),
          ),
          update: (context, storage, downloadManager, previous) =>
              previous ?? ModelManager(storage, downloadManager),
        ),
        ChangeNotifierProvider(create: (_) => OpenRouterService()),
        ChangeNotifierProxyProvider4<
          KoboldService,
          OpenRouterService,
          StorageService,
          BackendManager,
          LLMProvider
        >(
          create: (context) => LLMProvider(
            Provider.of<KoboldService>(context, listen: false),
            Provider.of<OpenRouterService>(context, listen: false),
            Provider.of<StorageService>(context, listen: false),
            Provider.of<BackendManager>(context, listen: false),
          ),
          update: (context, kobold, openRouter, storage, backend, previous) =>
              previous ?? LLMProvider(kobold, openRouter, storage, backend),
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
            final llmProviderForChat = Provider.of<LLMProvider>(
              context,
              listen: false,
            );
            chatService.setLLMProvider(llmProviderForChat);
            // Lets the live-status sources (oMLX poller) gate their polling
            // on an actual generation being in flight.
            llmProviderForChat.isGenerationActive = () =>
                chatService.isGenerating;
            chatService.setCharacterRepository(
              Provider.of<CharacterRepository>(context, listen: false),
            );
            // Wire GroupChatRepository for decoupled group member loading
            chatService.setGroupChatRepository(
              Provider.of<GroupChatRepository>(context, listen: false),
            );
            // Wire MemoryService for RAG
            try {
              final storage = Provider.of<StorageService>(
                context,
                listen: false,
              );
              final memoryService = MemoryService(
                EmbeddingService(storage),
                storage,
                db,
              );
              chatService.setMemoryService(memoryService);
            } catch (_) {}
            return chatService;
          },
          update: (context, kobold, persona, storage, worldRepo, previous) {
            if (previous != null) {
              final llmProviderForChat = Provider.of<LLMProvider>(
                context,
                listen: false,
              );
              previous.setLLMProvider(llmProviderForChat);
              llmProviderForChat.isGenerationActive = () =>
                  previous.isGenerating;
              previous.setCharacterRepository(
                Provider.of<CharacterRepository>(context, listen: false),
              );
              previous.setGroupChatRepository(
                Provider.of<GroupChatRepository>(context, listen: false),
              );
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
            final llmProviderLate = Provider.of<LLMProvider>(
              context,
              listen: false,
            );
            chatService.setLLMProvider(llmProviderLate);
            llmProviderLate.isGenerationActive = () =>
                chatService.isGenerating;
            chatService.setCharacterRepository(
              Provider.of<CharacterRepository>(context, listen: false),
            );
            chatService.setGroupChatRepository(
              Provider.of<GroupChatRepository>(context, listen: false),
            );
            return chatService;
          },
        ),
        ChangeNotifierProxyProvider<
          StorageService,
          ExpressionClassifierService
        >(
          create: (context) => ExpressionClassifierService(
            Provider.of<StorageService>(context, listen: false),
          ),
          update: (context, storage, previous) =>
              previous ?? ExpressionClassifierService(storage),
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
            // Call-mode TTS awareness is wired by the call overlay itself
            // (CallSession.attachTtsBusyProbe) — no TTS ref needed here.
            return previous ?? SttService(storage);
          },
        ),
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
        // Porch Stories: repository + pipeline must be above WebServerHost
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
            final storage = Provider.of<StorageService>(context, listen: false);
            final memoryService = MemoryService(
              EmbeddingService(storage),
              storage,
              db,
            );
            final repo = Provider.of<StoryRepository>(context, listen: false);
            return StoryPipelineService(
              repo,
              llmProvider.activeService,
              memoryService,
              db,
            );
          },
          update: (context, llmProvider, storage, previous) {
            final memoryService = MemoryService(
              EmbeddingService(storage),
              storage,
              db,
            );
            final repo = Provider.of<StoryRepository>(context, listen: false);
            return StoryPipelineService(
              repo,
              llmProvider.activeService,
              memoryService,
              db,
            );
          },
        ),
        // Web server: the React PWA + Dart shelf rewrite (lib/services/web).
        // Started on launch (_autoStartWebServer) or via the Settings toggle.
        // Collaborators are wired via setX. ChatService's own ImageGenService
        // (Scene Guest portraits) is wired in the post-frame block below.
        ChangeNotifierProvider<WebServerHost>(
          create: (context) {
            final host = WebServerHost(
              Provider.of<StorageService>(context, listen: false),
            );
            host.setDatabase(db);
            host.setChatService(
              Provider.of<ChatService>(context, listen: false),
            );
            host.setKoboldService(
              Provider.of<KoboldService>(context, listen: false),
            );
            host.setCharacterRepository(
              Provider.of<CharacterRepository>(context, listen: false),
            );
            host.setGroupChatRepository(
              Provider.of<GroupChatRepository>(context, listen: false),
            );
            host.setLlmProvider(
              Provider.of<LLMProvider>(context, listen: false),
            );
            host.setFolderService(
              Provider.of<FolderService>(context, listen: false),
            );
            host.setUserPersonaService(
              Provider.of<UserPersonaService>(context, listen: false),
            );
            host.setWorldRepository(
              Provider.of<WorldRepository>(context, listen: false),
            );
            host.setModelManager(
              Provider.of<ModelManager>(context, listen: false),
            );
            host.setHardwareService(
              Provider.of<HardwareService>(context, listen: false),
            );
            host.setImageGenService(
              Provider.of<ImageGenService>(context, listen: false),
            );
            host.setTtsService(
              Provider.of<TtsService>(context, listen: false),
            );
            host.setSttService(
              Provider.of<SttService>(context, listen: false),
            );
            host.setStoryRepository(
              Provider.of<StoryRepository>(context, listen: false),
            );
            host.setStoryPipelineService(
              Provider.of<StoryPipelineService>(context, listen: false),
            );
            return host;
          },
        ),
      ],
      child: const MyApp(),
      ),
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

  // Track normal (non-maximized) window bounds for correct save/restore
  double _normalWidth = 1280;
  double _normalHeight = 720;
  double? _normalX;
  double? _normalY;

  /// macOS-only hook for Cmd+Q / Dock-quit — see [_onAppExitRequested].
  AppLifecycleListener? _appExitListener;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    if (Platform.isMacOS) {
      _appExitListener = AppLifecycleListener(
        onExitRequested: _onAppExitRequested,
      );
    }
    // Run migration after first frame, then reunification if needed
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Capture initial window bounds after restore so tracking is correct
      // even if user maximizes without any interactive resize this session.
      try {
        if (!await windowManager.isMaximized()) {
          final size = await windowManager.getSize();
          final position = await windowManager.getPosition();
          _normalWidth = size.width;
          _normalHeight = size.height;
          _normalX = position.dx;
          _normalY = position.dy;
        }
      } catch (e) {
        debugPrint('Failed to capture initial window bounds: $e');
      }
      await _checkDbHealth();
      // Show stable DB import dialog on first beta launch (before migration)
      await _showStableDbImportIfNeeded();
      await _runMigrationIfNeeded();
      await _runReunificationIfNeeded();
    });
  }

  /// Show the stable DB import dialog on first beta launch.
  /// Only shown when a stable DB exists and no beta DB has been created yet.
  /// If the user chooses Import, the stable DB is manually copied to the
  /// beta location and all repositories are reloaded with the new data.
  Future<void> _showStableDbImportIfNeeded() async {
    if (!isPreRelease) return;
    final shouldShow = await StableDbImportDialog.shouldShow();
    if (!shouldShow || !mounted) return;

    // Show the dialog — it's modal and blocks further initialization
    await StableDbImportDialog.show(context);

    // If user chose Import, manually copy the stable DB and reinitialize
    final stablePath = await StableDbImportDialog.stableDbPath();
    if (stablePath == null) return;

    final prefs = await SharedPreferences.getInstance();
    final skipped = prefs.getBool('beta_stable_import_skipped') ?? false;
    if (skipped) return;

    final betaRoot = p.join(
      (await getApplicationDocumentsDirectory()).path,
      'FrontPorchAI-Beta',
    );
    final betaDbDir = p.join(betaRoot, 'KoboldManager');
    final betaDb = File(p.join(betaDbDir, 'front_porch_beta.db'));
    final stableDb = File(stablePath);

    if (betaDb.existsSync()) return; // another process already copied

    await Directory(betaDbDir).create(recursive: true);
    await stableDb.copy(betaDb.path);
    debugPrint('[DB] Pre-release build — imported stable DB to beta DB');

    // Reinitialize the database and reload all repositories
    await _reinitializeAfterImport();
  }

  /// Rebinds every DB-holding service to a fresh AppDatabase instance and
  /// reloads them. Returns false when the rebind could not run/complete —
  /// callers that just closed the old instance (import, restore) must treat
  /// false as "the app needs a restart", not as success.
  Future<bool> _reinitializeAfterImport() async {
    if (!mounted) return false;

    try {
      final oldDb = Provider.of<AppDatabase>(context, listen: false);
      await oldDb.close();

      final newDb = await AppDatabase.instance();
      _MyAppState._dbHealthy = await newDb.integrityCheck();

      final charRepo = Provider.of<CharacterRepository>(context, listen: false);
      final folderService = Provider.of<FolderService>(context, listen: false);
      final personaService = Provider.of<UserPersonaService>(
        context,
        listen: false,
      );
      final groupRepo = Provider.of<GroupChatRepository>(
        context,
        listen: false,
      );
      final worldRepo = Provider.of<WorldRepository>(context, listen: false);

      charRepo.updateDatabase(newDb);
      folderService.updateDatabase(newDb);
      personaService.updateDatabase(newDb);
      groupRepo.updateDatabase(newDb);
      worldRepo.updateDatabase(newDb);
      Provider.of<ChatService>(context, listen: false).updateDatabase(newDb);
      // Rebind the web server + Porch Stories too (same gap the storage-path
      // move had) — otherwise after an import/restore they keep the closed DB
      // and web logins / story queries fail until an app restart.
      Provider.of<StoryRepository>(
        context,
        listen: false,
      ).updateDatabase(newDb);
      Provider.of<WebServerHost>(context, listen: false).setDatabase(newDb);

      await charRepo.loadCharacters();
      await charRepo.cleanOrphanedPngs();
      await folderService.reload();
      await personaService.reload();
      await groupRepo.reload();
      await worldRepo.loadWorlds();
      return true;
    } catch (e) {
      debugPrint('[DB] Reinitialize after import failed: $e');
      return false;
    }
  }

  @override
  void dispose() {
    _appExitListener?.dispose();
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowResized() async {
    try {
      if (!await windowManager.isMaximized()) {
        final size = await windowManager.getSize();
        _normalWidth = size.width;
        _normalHeight = size.height;
      }
    } catch (e) {
      debugPrint('Failed to capture window size: $e');
    }
  }

  @override
  void onWindowMoved() async {
    try {
      if (!await windowManager.isMaximized()) {
        final pos = await windowManager.getPosition();
        _normalX = pos.dx;
        _normalY = pos.dy;
      }
    } catch (e) {
      debugPrint('Failed to capture window position: $e');
    }
  }

  @override
  void onWindowUnmaximize() async {
    try {
      final size = await windowManager.getSize();
      final pos = await windowManager.getPosition();
      _normalWidth = size.width;
      _normalHeight = size.height;
      _normalX = pos.dx;
      _normalY = pos.dy;
    } catch (e) {
      debugPrint('Failed to capture window bounds after unmaximize: $e');
    }
  }

  @override
  void onWindowClose() {
    _saveStateAndShutdown();
  }

  /// Cmd+Q / Dock "Quit" (macOS): AppKit asks the framework for a cancelable
  /// app exit BEFORE terminating. Without this hook the default answer lets
  /// [NSApp terminate:] proceed straight into libc exit() and the native-
  /// finalizer abort — so quitting via Cmd+Q kept producing crash reports
  /// even with the red-button path fixed. Run the same cleanup instead; it
  /// ends in exitWithoutNativeFinalizers, so the response is never sent.
  Future<AppExitResponse> _onAppExitRequested() async {
    if (_shutdownStarted) {
      // A close is already in flight and will _exit when done — refuse this
      // termination so the engine can't race our cleanup with its teardown.
      return AppExitResponse.cancel;
    }
    await _saveStateAndShutdown();
    return AppExitResponse.exit; // unreachable on macOS
  }

  /// True once a shutdown path has started — makes close requests
  /// idempotent (red button + Cmd+Q can both fire in one quit).
  bool _shutdownStarted = false;

  Future<void> _saveStateAndShutdown() async {
    if (_shutdownStarted) return;
    _shutdownStarted = true;
    // Save window state (size, position, maximized) before cleanup.
    // Must happen early while the window is still alive and queryable.
    try {
      final isMax = await windowManager.isMaximized();
      // A window closed while MINIMIZED reports the Win32 minimized sentinel
      // (~ -32000, -32000) from getPosition(). Saving that poisons the restore
      // and strands the window off-screen next launch (issue #78). Treat
      // minimized exactly like maximized: persist the tracked non-minimized
      // _normal* bounds instead of the live (bogus) rect.
      final isMin = await windowManager.isMinimized();
      final prefs = await SharedPreferences.getInstance();

      if (isMax || isMin) {
        // Save tracked normal (non-maximized, non-minimized) bounds so the
        // restore code never sets the window to full-screen size in the
        // non-maximized state and never writes the minimized sentinel.
        // This eliminates the ghost frame root cause on Windows and the
        // off-screen-taskbar-icon bug from issue #78.
        //
        // NOTE: _normal* fields are populated ONLY from live windowManager
        // queries during this session (post-frame capture, resize/move
        // listeners, unmaximize). They are NOT seeded from the persisted
        // window_* prefs on launch. Consequence: if the user launches
        // maximized, never unmaximizes or resizes, and closes while still
        // maximized, stale defaults are saved here (1280x720 / 0) rather
        // than their actual normal geometry. This works across
        // Windows/macOS/Linux because each OS internally preserves the
        // pre-maximize "restore down" rect and applies it when the window
        // is unmaximized after next launch — the stale prefs are simply
        // overwritten. If a platform ever drops this behavior, the fix is
        // to unconditionally seed _normal* from persisted prefs in the
        // post-frame callback (around line 682), before or instead of the
        // live capture. See PR #53 for the full ghost-frame analysis.
        await prefs.setDouble(_k('window_width'), _normalWidth);
        await prefs.setDouble(_k('window_height'), _normalHeight);
        await prefs.setDouble(_k('window_x'), _normalX ?? 0.0);
        await prefs.setDouble(_k('window_y'), _normalY ?? 0.0);
      } else {
        final size = await windowManager.getSize();
        final position = await windowManager.getPosition();
        _normalWidth = size.width;
        _normalHeight = size.height;
        _normalX = position.dx;
        _normalY = position.dy;
        await prefs.setDouble(_k('window_width'), size.width);
        await prefs.setDouble(_k('window_height'), size.height);
        await prefs.setDouble(_k('window_x'), position.dx);
        await prefs.setDouble(_k('window_y'), position.dy);
      }
      await prefs.setBool(_k('window_maximized'), isMax);
    } catch (e) {
      debugPrint('Failed to save window state: $e');
    }

    // Flush any pending chat save BEFORE tearing anything down. The last turn's
    // post-generation Needs vector + Realism scalars are applied in memory and
    // reach the DB only through _saveChat(); some of those saves are
    // fire-and-forget, so one can still be queued or mid-commit at close time.
    // Awaiting the flush drains the save chain and writes the live state once
    // more, so exit(0)/destroy() below can't kill an in-flight write. This is
    // the fix for "the needs deltas from the last character message didn't
    // stick after closing and reopening the app."
    try {
      await Provider.of<ChatService>(
        context,
        listen: false,
      ).flushPendingSaves();
    } catch (e) {
      debugPrint('AG_DEBUG: Error flushing chat save on window close: $e');
    }

    // Stop the managed KoboldCPP backend BEFORE destroying the window. This
    // prevents an orphaned process when the app closes.
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
      final webServer = Provider.of<WebServerHost>(context, listen: false);
      if (webServer.isRunning) {
        await webServer.stop();
      }
    } catch (e) {
      debugPrint('AG_DEBUG: Error stopping web server on close: $e');
    }


    // On Linux and Windows, windowManager.destroy() can trigger a Flutter engine bug:
    //   "FlutterEngineRemoveView returned kInvalidArguments"
    //   "Segmentation fault (core dumped)" or a native crash popup on Windows 11.
    // Workaround: exit(0) after cleanup to bypass the buggy view teardown.
    if (Platform.isLinux || Platform.isWindows) {
      exit(0);
    } else {
      // macOS: end the process WITHOUT running C++ static destructors.
      // destroy() → [NSApp terminate:] → libc exit() → __cxa_finalize runs
      // the bundled native libraries' global destructors — and onnxruntime's
      // (in-process expression/embedding engines; its worker pool holds ~16
      // parked threads at quit) aborts there via std::terminate. Every
      // red-button close produced an "Abort trap: 6" crash report in
      // ~/Library/Logs/DiagnosticReports even though the quit was clean.
      // Dart's exit(0) would hit the same finalize pass, so end the process
      // with no finalizers instead. Safe: everything above was awaited
      // (prefs written, chat saves flushed, KoboldCpp stopped, web server
      // stopped), and SQLite's committed WAL data is crash-safe by design.
      exitWithoutNativeFinalizers(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    // StorageService is the single source of truth for isDark (persisted + notifies on load/toggle).
    // Using Consumer2 ensures the entire MaterialApp tree (and thus ThemeData) rebuilds when the user
    // toggles or when the async prefs load completes. AppState is kept only for selectedIndex.
    return Consumer2<StorageService, AppState>(
      builder: (context, storage, appState, child) {
        final isDark = storage.uiSettings.isDark;
        return MaterialApp(
          title: 'Front Porch AI',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: isDark ? Brightness.dark : Brightness.light,
            // Warm-porch app-wide accent: seed the Material 3 color scheme from
            // porch amber (was primarySwatch: Colors.blue) so every default
            // control — switches, sliders, buttons, progress bars, the text
            // cursor, tab indicators — warms up to match the chat sidebar and
            // the web UI (whose --accent is already porch amber). The scheme's
            // surfaces are pinned back to the app's existing slate/warm-paper
            // grounds so only the ACCENT roles change, not the backgrounds.
            colorScheme:
                ColorScheme.fromSeed(
                  seedColor: AppColors.porchAmber,
                  brightness: isDark ? Brightness.dark : Brightness.light,
                ).copyWith(
                  primary: isDark
                      ? AppColors.porchAmber
                      : AppColors.porchAmberLight,
                  onPrimary: isDark ? AppColors.onChaosAccent : Colors.white,
                  surface: isDark ? AppColors.surface : AppColors.lightSurface,
                ),
            scaffoldBackgroundColor: isDark
                ? AppColors.background
                : AppColors.lightBackground, // warmer paper
            cardColor: isDark ? AppColors.card : AppColors.lightCard,
            textTheme: GoogleFonts.interTextTheme(Theme.of(context).textTheme)
                .apply(
                  bodyColor: isDark ? Colors.white : Colors.black87,
                  displayColor: isDark ? Colors.white : Colors.black87,
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
                  // Wire ExpressionClassifierService into ChatService
                  try {
                    final chatService = Provider.of<ChatService>(
                      context,
                      listen: false,
                    );
                    final classifier = Provider.of<ExpressionClassifierService>(
                      context,
                      listen: false,
                    );
                    chatService.setExpressionClassifierService(classifier);
                  } catch (_) {}
                  // Wire ImageGenService into ChatService for Scene Guest
                  // background portraits (previously done in the legacy web
                  // server provider's create, removed at cutover).
                  try {
                    final chatService = Provider.of<ChatService>(
                      context,
                      listen: false,
                    );
                    chatService.setImageGenService(
                      Provider.of<ImageGenService>(context, listen: false),
                    );
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
                        final webServer = Provider.of<WebServerHost>(
                          context,
                          listen: false,
                        );
                        if (webServer.isRunning) await webServer.stop();
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
              final effectiveScale =
                  responsiveScale * storage.uiSettings.textScale;

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
                            separatorBuilder: (_, _) =>
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
                                        color: AppColors.porchAmber,
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

      // Re-open AND rebind: restoreBackup closed the old AppDatabase, but every
      // repository/service captured that instance at startup. Without the same
      // rebind+reload the import flow uses, the app dismisses this overlay and
      // then throws "database was closed" on every action until a restart.
      final rebound = await _reinitializeAfterImport();

      if (mounted) {
        if (rebound) {
          setState(() => _isMigrating = false);
        } else {
          // The backup IS safely on disk — only the live rewiring failed.
          // Never dismiss as success: every DB action would fail confusingly.
          setState(() {
            _migrationStep =
                'Backup restored. Please close and reopen Front Porch AI '
                'to finish.';
          });
        }
      }

      debugPrint('[DB] Backup restored successfully from: ${backup.path}');
    } catch (e) {
      debugPrint('[DB] Backup restore failed: $e');
      // The old DB may already be closed — dismissing the overlay would leave
      // a half-dead app that looks fine. Keep it up with an honest message.
      if (mounted) {
        setState(() {
          _migrationStep =
              'Restore failed. Please close and reopen Front Porch AI, '
              'then try another backup.';
        });
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
    try {
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
    } catch (e) {
      // A migration throw must NOT leave _isMigrating true forever (a
      // full-screen overlay = unusable app) and must NOT re-run every launch
      // (each retry re-imports characters, worsening the very duplicate-path
      // condition that can cause the throw). Log, drop the overlay, and let
      // the app open on whatever migrated so far — the legacy JSON is left in
      // place, so a fixed future build can retry.
      debugPrint('[DB Migration] Failed — continuing without it: $e');
    }

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
                      colors: [AppColors.porchAmberLight, AppColors.porchAmber],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.formMasterAccent.withValues(alpha: 0.3),
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
                    color: AppColors.porchAmber,
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
                      AppColors.formMasterAccent,
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
                        AppColors.porchAmberLight,
                        AppColors.porchAmber,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.formMasterAccent.withValues(alpha: 0.3),
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
                        color: AppColors.formMasterAccent.withValues(alpha: 0.3),
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
                                    color: AppColors.formMasterAccent,
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
                                backgroundColor: AppColors.formMasterAccent,
                                foregroundColor: AppColors.onChaosAccent,
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
                      color: AppColors.porchAmber,
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
                        AppColors.formMasterAccent,
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

  Future<void> _autoStartWebServer(BuildContext context) async {
    final storage = Provider.of<StorageService>(context, listen: false);
    await storage.initialized;
    if (!storage.webServerSettings.webServerEnabled) return;

    final webServer = Provider.of<WebServerHost>(context, listen: false);
    // Crash-loop-safe: a hung or crashing start disables the server instead of
    // re-crashing on every launch and locking the user out (see startSafely).
    await webServer.startSafely(
      storage.webServerSettings.webServerPort,
      isAutoStart: true,
    );
  }
}
