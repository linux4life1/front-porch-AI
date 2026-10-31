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
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'package:front_porch_ai/app/app.dart';
import 'package:front_porch_ai/app_version.dart';
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/database/data_migration_service.dart';
import 'package:front_porch_ai/services/prefs_recovery.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/web_server_host.dart';
import 'package:front_porch_ai/ui/layout/main_layout.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/utils/utils.dart'
    show StartupTrace, formatRelativeTime;

void _mark(String step) => StartupTrace.mark(step);

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  _mark('binding ready');
  await windowManager.ensureInitialized();
  _mark('windowManager.ensureInitialized');

  // Ordered startup phases — each lives in lib/app/ (startup_phases.dart,
  // main_window.dart, root_providers.dart). The ORDER of these calls is the
  // init contract; never reorder (see the phase functions' own comments for
  // why each must precede the next).
  installSignalHandlers();
  await healPrefsAndConsolidateFiles();
  final boot = await openDatabaseGuarded();
  if (boot == null) return; // DbInitErrorApp is already running
  // The saved theme is read before anything is painted: the native view
  // behind Flutter takes its background, and StorageService loads it for
  // the first frame.
  final prefs = await SharedPreferences.getInstance();
  final background = launchBackground(prefs);
  await paintLaunchBackground(background);
  Widget root() => _buildRootWidget(boot.db, boot.needsMigration, prefs);
  if (Platform.isWindows) {
    // Windows runs the app first and shows the window once it has painted
    // at its final size. Restoring the saved bounds before the engine has
    // produced a frame can leave its resize handshake stuck, and the window
    // white until a real resize (flutter/flutter#192537). The runner keeps
    // the window hidden until Dart shows it (windows/runner/flutter_window.cpp).
    runApp(root());
    await showMainWindow(background: background);
    return;
  }
  await showMainWindow(background: background);
  runApp(root());
}

Widget _buildRootWidget(
  AppDatabase db,
  bool needsMigration,
  SharedPreferences prefs,
) => buildRootWidget(db, needsMigration, app: const MyApp(), bootPrefs: prefs);

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp>
    with WindowListener, WidgetsBindingObserver {
  /// False for exactly the first frame — gates the service-graph-touching
  /// overlays so first paint happens before the providers spin up.
  bool _overlaysArmed = false;
  bool _updateChecked = false;

  late final StartupRecovery _recovery = StartupRecovery(setState);
  final WindowBoundsTracker _bounds = WindowBoundsTracker();
  final AppShutdown _shutdown = AppShutdown();

  /// macOS-only hook for Cmd+Q / Dock-quit — see [_onAppExitRequested].
  AppLifecycleListener? _appExitListener;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    WidgetsBinding.instance.addObserver(this);
    if (Platform.isMacOS) {
      _appExitListener = AppLifecycleListener(
        onExitRequested: _onAppExitRequested,
      );
    }
    // Run migration after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _mark('FIRST FRAME (user sees the app)');
      // First frame is up — arm the deferred overlays (see the home Stack).
      if (mounted) setState(() => _overlaysArmed = true);
      await _bounds.captureInitial();
      await _recovery.checkDbHealth(context);
      // Show stable DB import dialog on first beta launch (before migration)
      await _recovery.showStableDbImportIfNeeded(context);
      await _recovery.runMigrationIfNeeded(context);
      // Deferred idempotent maintenance (moved out of main()'s pre-window
      // path): purge month-old soft-deletes + pre-0.8.0 legacy JSON files.
      try {
        final db = await AppDatabase.instance();
        await db.purgeSoftDeletes();
      } catch (e) {
        debugPrint('[Startup] Soft-delete purge failed: $e');
      }
      try {
        await DataMigrationService.cleanupLegacyFiles();
      } catch (e) {
        debugPrint('[Startup] Legacy file cleanup failed: $e');
      }
    });
  }

  @override
  void dispose() {
    _appExitListener?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    windowManager.removeListener(this);
    super.dispose();
  }

  /// Match system: follow the OS when it switches light/dark.
  @override
  void didChangePlatformBrightness() {
    Provider.of<StorageService>(
      context,
      listen: false,
    ).appearance.setPlatformBrightness(
      WidgetsBinding.instance.platformDispatcher.platformBrightness,
    );
  }

  @override
  void onWindowResized() async {
    await _bounds.onResized();
  }

  @override
  void onWindowMoved() async {
    await _bounds.onMoved();
  }

  @override
  void onWindowUnmaximize() async {
    await _bounds.onUnmaximized();
  }

  @override
  void onWindowClose() async {
    if (!_shutdown.started && !await UnsavedChanges.instance.confirmLeave()) {
      return;
    }
    _shutdown.run(context, _bounds);
  }

  /// Cmd+Q / Dock "Quit" (macOS): AppKit asks the framework for a cancelable
  /// app exit BEFORE terminating. Without this hook the default answer lets
  /// [NSApp terminate:] proceed straight into libc exit() and the native-
  /// finalizer abort — so quitting via Cmd+Q kept producing crash reports
  /// even with the red-button path fixed. Run the same cleanup instead; it
  /// ends in exitWithoutNativeFinalizers, so the response is never sent.
  Future<AppExitResponse> _onAppExitRequested() async {
    if (_shutdown.started) {
      // A close is already in flight and will _exit when done — refuse this
      // termination so the engine can't race our cleanup with its teardown.
      return AppExitResponse.cancel;
    }
    if (!await UnsavedChanges.instance.confirmLeave()) {
      return AppExitResponse.cancel;
    }
    await _shutdown.run(context, _bounds);
    return AppExitResponse.exit; // unreachable on macOS
  }

  @override
  Widget build(BuildContext context) {
    // StorageService.appearance is the single source of truth for the app
    // theme, mode, accent, font and corners (persisted + notifies on load and
    // on every change). The Consumer rebuilds the MaterialApp tree (and thus
    // ThemeData) when any of them changes or when the async prefs load
    // completes. AppTheme caches the ThemeData, so a notify that doesn't
    // change the theme doesn't re-derive it. MainLayout watches AppState
    // itself for navigation.
    return Consumer<StorageService>(
      builder: (context, storage, child) {
        final appearance = storage.appearance;
        return MaterialApp(
          title: appWindowTitle,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.build(
            palettes: appearance.resolvedPalettes(),
            brightness: appearance.brightness,
            font: appearance.font,
            corners: appearance.corners,
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
                    final from = PrefsRecovery.restoredFrom;
                    showWarmDialog<void>(
                      context,
                      title: from == null
                          ? 'Your settings were reset'
                          : 'Your settings were restored',
                      icon: Icons.settings_backup_restore_rounded,
                      content: WarmDialogText(
                        from == null
                            ? 'Front Porch AI found its settings file damaged '
                                  '(this can happen after a crash or power '
                                  'loss) and started fresh so the app could '
                                  'open. Your characters and chats are '
                                  'unaffected.\n\n'
                                  'If you had moved your storage folder, '
                                  'point the app back at it in Settings and '
                                  'everything will reappear.'
                            : 'Front Porch AI found its settings file damaged '
                                  '(this can happen after a crash or power '
                                  'loss) and put back the copy saved '
                                  '${formatRelativeTime(from)}. Settings changed '
                                  'after that may need setting again. Your '
                                  'characters and chats are unaffected.',
                      ),
                      actions: [warmDialogCancel(context, label: 'OK')],
                    );
                  }
                  checkForAppUpdates(context).then((_) {
                    if (context.mounted) checkKoboldEngine(context);
                  });
                  autoStartWebServer(context);
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
                  } catch (e) {
                    debugPrint('[Startup] TTS not wired into chat: $e');
                  }
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
                  } catch (e) {
                    debugPrint(
                      '[Startup] Expression classifier not wired into chat: $e',
                    );
                  }
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
                  } catch (e) {
                    debugPrint('[Startup] Image gen not wired into chat: $e');
                  }
                  // Wire UpdateService shutdown callback so child processes
                  // (KoboldCPP, web server) are stopped
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
                        if (kobold.isRunning || kobold.isStarting) {
                          await kobold.stopKobold();
                        }
                      } catch (e) {
                        debugPrint(
                          '[Update] Kobold stop before exit failed: $e',
                        );
                      }
                      try {
                        final webServer = Provider.of<WebServerHost>(
                          context,
                          listen: false,
                        );
                        if (webServer.isRunning) await webServer.stop();
                      } catch (e) {
                        debugPrint(
                          '[Update] Web server stop before exit failed: $e',
                        );
                      }
                    });
                  } catch (e) {
                    debugPrint('[Startup] Update shutdown hook not wired: $e');
                  }
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
                    if (_recovery.isDbCorrupt)
                      DbCorruptionOverlay(
                        backups: _recovery.availableBackups,
                        onRestore: (backup) =>
                            _recovery.restoreBackup(this.context, backup),
                        onContinue: () =>
                            _recovery.continueWithoutRestoring(this.context),
                      ),
                    if (_recovery.isMigrating)
                      MigrationOverlay(
                        step: _recovery.migrationStep,
                        current: _recovery.migrationCurrent,
                        total: _recovery.migrationTotal,
                      ),
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
