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
import 'package:front_porch_ai/ui/window_size_env.dart';
import 'package:front_porch_ai/services/backporch/backporch.dart';
import 'package:front_porch_ai/ui/layout/main_layout.dart'; // Keep original import for MainLayout
import 'package:front_porch_ai/app_version.dart';
import 'package:front_porch_ai/utils/native_exit.dart';
import 'package:front_porch_ai/utils/utils.dart' show StartupTrace;
import 'package:front_porch_ai/database/database.dart';
// ignore: unused_import — used in the commented-out auto-cleanup block below
import 'package:front_porch_ai/database/database_cleanup.dart';
import 'package:front_porch_ai/database/data_migration_service.dart';

// Barrel imports for the most common services and widgets used directly in main.dart
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

// Services and modules not yet in the services barrel (internal, low-frequency, or side-effect heavy)
import 'package:front_porch_ai/services/download_manager.dart';
import 'package:front_porch_ai/services/prefs_recovery.dart';
import 'package:front_porch_ai/services/setup_service.dart';
import 'package:front_porch_ai/services/db_reunification_service.dart';
import 'package:front_porch_ai/services/embedding_service.dart';
import 'package:front_porch_ai/services/memory_service.dart';
import 'package:front_porch_ai/services/audiobook_generator_service.dart';
import 'package:front_porch_ai/services/file_consolidation_service.dart';
import 'package:front_porch_ai/services/web/web_server_host.dart';

// Dialogs and specific widgets used only in main.dart (direct imports are appropriate)
import 'package:front_porch_ai/ui/dialogs/dialogs.dart';
import 'package:front_porch_ai/ui/widgets/db_init_error_app.dart';

// God-file split (Tranche C, docs/design/god-file-elimination.md): main.dart
// is a library-of-top-level-functions + one State class. Parts hold the
// pre-runApp startup phases, the provider graph, and the _MyAppState
// extensions. Order below mirrors the original file's top-to-bottom layout.
part 'main.startup.dart';
part 'main.providers.dart';
part 'main.lifecycle.dart';
part 'main.recovery.dart';
part 'main.migration.dart';
part 'main.reunification.dart';

/// Prefix SharedPreferences keys for beta builds so window state is
/// isolated from the stable installation.  Unchanged for stable builds.
String _k(String key) => isPreRelease ? 'beta_$key' : key;

/// DB health flag, set once from `_openDatabaseGuarded()` before the first
/// `runApp` and read/written thereafter by `_MainDbRecovery._checkDbHealth`
/// (main.recovery.dart) and `_rebindAfterDatabaseSwap`. Hoisted to a
/// top-level library-private variable — main() writes it before any
/// `_MyAppState` exists, and an extension cannot resolve an unqualified
/// class static, so it can't stay a `static` field on `_MyAppState`.
bool _dbHealthy = true; // set from main() before runApp

void _mark(String step) => StartupTrace.mark(step);

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  _mark('binding ready');
  await windowManager.ensureInitialized();
  _mark('windowManager.ensureInitialized');

  // Ordered startup phases — each builder lives in main.startup.dart /
  // main.providers.dart. The ORDER of these calls is the init contract;
  // never reorder (see the phase functions' own comments for why each
  // must precede the next).
  _installSignalHandlers();
  await _healPrefsAndConsolidateFiles();
  final boot = await _openDatabaseGuarded();
  if (boot == null) return; // DbInitErrorApp is already running
  await _showMainWindow();
  runApp(_buildRootWidget(boot.db, boot.needsMigration));
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WindowListener {
  /// False for exactly the first frame — gates the service-graph-touching
  /// overlays so first paint happens before the providers spin up.
  bool _overlaysArmed = false;
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
      _mark('FIRST FRAME (user sees the app)');
      // First frame is up — arm the deferred overlays (see the home Stack).
      if (mounted) setState(() => _overlaysArmed = true);
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
      // Deferred idempotent maintenance (moved out of main()'s pre-window
      // path): purge month-old soft-deletes + pre-0.8.0 legacy JSON files.
      try {
        final db = await AppDatabase.instance();
        await db.purgeSoftDeletes();
      } catch (_) {}
      try {
        await DataMigrationService.cleanupLegacyFiles();
      } catch (_) {}
    });
  }

  /// setState bridge for the `_MyAppState` extensions split into
  /// main.lifecycle.dart / main.recovery.dart / main.migration.dart /
  /// main.reunification.dart — `setState` is `@protected`, so an extension
  /// method calling it directly fails the analyzer's
  /// `invalid_use_of_protected_member` check. Same pattern as
  /// `settings_page.dart`'s `rebuildState` and `tts_service.dart`'s
  /// `_notify`; private because every caller is library-internal.
  void _rebuild(VoidCallback fn) => setState(fn);

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

  @override
  Widget build(BuildContext context) {
    // StorageService is the single source of truth for isDark (persisted + notifies on load/toggle).
    // The Consumer ensures the entire MaterialApp tree (and thus ThemeData) rebuilds when the user
    // toggles or when the async prefs load completes. AppState was in the tuple historically but
    // never read here — subscribing meant every sidebar NAV TAP re-ran ColorScheme.fromSeed and
    // re-derived the whole app theme. MainLayout watches AppState itself for navigation.
    return Consumer<StorageService>(
      builder: (context, storage, child) {
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
                  // A settings reset must never be silent — especially the
                  // custom storage folder, whose loss makes the library look
                  // empty until the user re-selects it in Settings.
                  if (PrefsRecovery.recovered) {
                    showWarmDialog<void>(
                      context,
                      title: 'Your settings were reset',
                      icon: Icons.settings_backup_restore_rounded,
                      content: const WarmDialogText(
                        'Front Porch AI found its settings file damaged — '
                        'this can happen after a crash or power loss — and '
                        'started fresh so the app could open. Your '
                        'characters and chats are unaffected.\n\n'
                        'If you had moved your storage folder, point the '
                        'app back at it in Settings and everything will '
                        'reappear.',
                      ),
                      actions: [warmDialogCancel(context, label: 'OK')],
                    );
                  }
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
                    // Mounted one frame late ON PURPOSE: SetupOverlay reads
                    // SetupService/BackendManager and RemoteLockOverlay
                    // consumes WebServerHost — whose provider reads ~15
                    // others — so building them in the FIRST frame defeated
                    // every lazy provider and constructed the whole service
                    // graph (process spawns, dir scans, DB loads) before
                    // anything had painted. One frame (~16 ms) later is
                    // imperceptible; first paint no longer waits on it.
                    if (_overlaysArmed) const SetupOverlay(),
                    if (_overlaysArmed) const RemoteLockOverlay(),
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
}
