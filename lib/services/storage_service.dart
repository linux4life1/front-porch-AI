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
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/app_version.dart';

// Stage 7: directories + domain settings. Do not grow this file.
import 'desktop_spell_check_service.dart';
import 'reasoning_effort_store.dart';
import 'storage/storage.dart';

class StorageService extends ChangeNotifier {
  final Completer<void> _initCompleter = Completer<void>();
  Future<void> get initialized => _initCompleter.future;

  /// True when one of the data subdirectories could not be created at startup
  /// (a stray file sitting where a folder belongs, a per-folder ACL, Windows
  /// Controlled Folder Access). The root itself is deliberately NOT changed —
  /// see [_init] for why relocating was worse than the failure it "fixed".
  ///
  /// Nothing surfaces this to the user yet; a "your data folder had a problem"
  /// banner reading this flag is still owed.
  bool rootDirectoriesUnavailable = false;

  SharedPreferences? _prefs;
  String? _rootPath;
  String? _customModelsPath;
  Directory? _binDir;

  // Stage 7: domain settings (plain classes + base mixin; single Storage ChangeNotifier surface)
  late final GenerationSettings _generationSettings = GenerationSettings();
  late final BackendSettings _backendSettings = BackendSettings();
  late final UiSettings _uiSettings = UiSettings();
  late final TtsSettings _ttsSettings = TtsSettings();
  late final SttSettings _sttSettings = SttSettings();
  late final ImageGenSettings _imageGenSettings = ImageGenSettings();
  late final ExpressionSettings _expressionSettings = ExpressionSettings();
  late final WebServerSettings _webServerSettings = WebServerSettings();
  late final RealismSettings _realismSettings = RealismSettings();
  late final WebSearchSettings _webSearchSettings = WebSearchSettings();
  late final MemorySettings _memorySettings = MemorySettings();
  late final PresetSettings _presetSettings = PresetSettings();
  late final LorebookSettings _lorebookSettings = LorebookSettings();

  // Directories lifted to directories.dart (Stage 7); thin god owns root state for setRootPath.
  // Getter ensures live values after setRootPath / setCustomModelsPath.
  AppDirectories get directories =>
      AppDirectories(rootPath: _rootPath, customModelsPath: _customModelsPath);

  String? get rootPath => _rootPath;
  String? get customModelsPath => _customModelsPath;
  Directory get binDir => _binDir ?? Directory(_rootPath ?? '');
  Directory get modelsDir => directories.modelsDir;
  Directory get chatsDir => directories.chatsDir;
  Directory get worldsDir => directories.worldsDir;
  Directory get toolsDir => directories.toolsDir;

  Directory get charactersDir => directories.charactersDir;

  /// Directory for all group-private data (decoupled from singular library characters).
  /// Each group gets its own subdirectory (by group id) under here to store its
  /// member avatar PNGs (primary only; no multi-avatar or expressions per spec).
  /// Group data is NEVER written to or resolved from the global charactersDir or library.
  /// The only bridge to library is the user's explicit "Separate to my library" action.
  Directory get groupsDir => directories.groupsDir;

  File resolveCharacterImage(String imagePath) =>
      directories.resolveCharacterImage(imagePath);

  Directory characterAvatarDir(String characterName) =>
      directories.characterAvatarDir(characterName);

  /// The character's private base folder (`avatars/` + `looks/` live under it).
  /// Used to resolve gallery-look files via [AvatarImage.resolveFile].
  Directory characterBaseDir(String characterName) =>
      directories.characterBaseDir(characterName);

  Directory get customBackgroundDir => directories.customBackgroundDir;

  /// Cache directory for downscaled web-UI avatar thumbnails (derived data).
  Directory get webThumbnailCacheDir => directories.webThumbnailCacheDir;

  // Public accessors to extracted domain settings (post-Stage 7).
  // Callers use storage.generationSettings.systemPrompt etc.
  GenerationSettings get generationSettings => _generationSettings;
  BackendSettings get backendSettings => _backendSettings;
  UiSettings get uiSettings => _uiSettings;
  TtsSettings get ttsSettings => _ttsSettings;
  SttSettings get sttSettings => _sttSettings;
  ImageGenSettings get imageGenSettings => _imageGenSettings;
  ExpressionSettings get expressionSettings => _expressionSettings;
  WebServerSettings get webServerSettings => _webServerSettings;
  RealismSettings get realismSettings => _realismSettings;
  WebSearchSettings get webSearchSettings => _webSearchSettings;
  MemorySettings get memorySettings => _memorySettings;
  PresetSettings get presetSettings => _presetSettings;
  LorebookSettings get lorebookSettings => _lorebookSettings;

  // God-level (not in a *Settings): spell check language.
  //
  // Stored as a dictionary tag ('en_US', 'de_DE') or kSpellCheckOff. Defaults
  // to English, NOT the system locale — a German or Polish desktop says
  // nothing about the language someone role-plays in, and checking English
  // prose against a German dictionary underlines every word. See the doc on
  // DesktopSpellCheckService.activeLanguage.
  String get spellCheckLanguage => DesktopSpellCheckService.activeLanguage;

  Future<void> setSpellCheckLanguage(String v) async {
    if (DesktopSpellCheckService.activeLanguage == v) return;
    DesktopSpellCheckService.activeLanguage = v;
    await _prefs?.setString(_k('spell_check_language'), v);
    notifyListeners();
  }

  // God-level (not in a *Settings): custom models path
  // (narrower than setRootPath: no relocation dance needed; early return + beta _k + notify for parity with god pattern)
  Future<void> setCustomModelsPath(String? v) async {
    final normalized = (v != null && v.isNotEmpty) ? v : null;
    if (_customModelsPath == normalized) return;
    _customModelsPath = normalized;
    if (normalized != null) {
      await _prefs?.setString(_k('custom_models_path'), normalized);
    } else {
      await _prefs?.remove(_k('custom_models_path'));
    }
    notifyListeners();
  }

  StorageService() {
    _init();
  }

  /// Headless agent-test storage: [rootPath] is the only data dir. Never
  /// calls [SharedPreferences.getInstance] or
  /// [getApplicationDocumentsDirectory].
  StorageService.sandbox(String rootPath) {
    if (rootPath.contains('FrontPorchAI')) {
      throw ArgumentError(
        'StorageService.sandbox refuses a live FrontPorchAI path: $rootPath',
      );
    }
    _prefs = null;
    _rootPath = rootPath;
    _binDir = Directory(path.join(rootPath, 'koboldcpp_bin'));
    for (final dir in [
      chatsDir,
      modelsDir,
      worldsDir,
      charactersDir,
      groupsDir,
      customBackgroundDir,
      toolsDir,
    ]) {
      try {
        dir.createSync(recursive: true);
      } catch (e) {
        rootDirectoriesUnavailable = true;
        debugPrint('[Storage] sandbox could not create "${dir.path}" ($e).');
      }
    }
    _generationSettings.initializeBase(null, notifyListeners);
    _backendSettings.initializeBase(null, notifyListeners);
    _uiSettings.initializeBase(null, notifyListeners);
    _ttsSettings.initializeBase(null, notifyListeners);
    _sttSettings.initializeBase(null, notifyListeners);
    _imageGenSettings.initializeBase(null, notifyListeners);
    _expressionSettings.initializeBase(null, notifyListeners);
    _webServerSettings.initializeBase(null, notifyListeners);
    _realismSettings.initializeBase(null, notifyListeners);
    _webSearchSettings.initializeBase(null, notifyListeners);
    _memorySettings.initializeBase(null, notifyListeners);
    _presetSettings.initializeBase(null, notifyListeners);
    _lorebookSettings.initializeBase(null, notifyListeners);
    _generationSettings.load();
    _backendSettings.load();
    _uiSettings.load();
    _ttsSettings.load();
    _sttSettings.load();
    _imageGenSettings.load();
    _expressionSettings.load();
    _webServerSettings.load();
    _realismSettings.load();
    unawaited(_webSearchSettings.load());
    _memorySettings.load();
    _presetSettings.load();
    _lorebookSettings.load();
    if (!_initCompleter.isCompleted) _initCompleter.complete();
  }

  // ── Beta / stable isolation ────────────────────────────────────────────────
  //
  // ALL of the logic below is driven by [isPreRelease] from app_version.dart.
  // When a stable tag is built (e.g. v0.9.8 — no "-Beta" suffix),
  // isPreRelease returns false and every method here behaves exactly as before.
  // No code needs to be reverted when merging the beta branch into main.

  /// SharedPreferences key used to persist the root data directory.
  /// Beta builds use a separate key so a custom beta path never overwrites
  /// the user's stable path choice.
  static String get _rootPathKey =>
      isPreRelease ? 'root_path_beta' : 'root_path';

  /// Prefix all SharedPreferences keys for beta builds so settings (API keys,
  /// TTS config, etc.) are completely isolated from the stable installation.
  /// Returns [key] unchanged for stable builds — zero reversal needed on merge.
  static String _k(String key) => isPreRelease ? 'beta_$key' : key;

  Future<void> _init() async {
    _prefs = await SharedPreferences.getInstance();
    final docsDir = await getApplicationDocumentsDirectory();

    // For developers running from source (`flutter run`), allow forcing the
    // exact same data directory as the packaged app via environment variable.
    // This makes cloud sync testing from source behave identically to packaged builds.
    String? devOverride;
    if (isPreRelease) {
      devOverride = Platform.environment['FRONT_PORCH_AI_DATA_DIR'];
    }

    // Beta builds default to a completely separate data directory so they
    // never touch a stable user's characters, chats, or database.
    final defaultRootName = isPreRelease ? 'FrontPorchAI-Beta' : 'FrontPorchAI';
    final defaultRoot = path.join(docsDir.path, defaultRootName);
    _rootPath = devOverride ?? _prefs?.getString(_rootPathKey) ?? defaultRoot;
    if (devOverride != null) {
      debugPrint('[Storage] Using dev override data directory: $_rootPath');
    }
    _binDir = Directory(path.join(_rootPath!, 'koboldcpp_bin'));

    // Ensure directories exist. A failure here must not escape: _init is
    // fire-and-forget, so a throw left _initCompleter hanging FOREVER and
    // anything awaiting `initialized` (the web-server autostart, groups,
    // worlds) blocked with the app half-booted.
    //
    // Swallowing it is the whole recovery — we do NOT relocate to the default
    // root any more. Relocating split the app in two: AppDatabase.instance()
    // already opened `<persisted root>/KoboldManager` back in main()'s
    // _openDatabaseGuarded (a failure THERE ends the launch in DbInitErrorApp),
    // so reaching this line proves the persisted root took the database (the
    // one exception is a pre-release FRONT_PORCH_AI_DATA_DIR run, where a dev
    // has deliberately split the two roots already).
    // Pointing storage at a different root then listed the database's rows
    // while every portrait, chat file, world and background resolved under a
    // tree that has none of them. Staying put keeps files and rows on one root.
    //
    // Each folder is also created independently: one bad entry (a stray file
    // named `chats`) used to abort the whole run at the first await, so the
    // five innocent folders were never created either.
    for (final dir in [
      chatsDir,
      modelsDir,
      worldsDir,
      toolsDir,
      charactersDir,
      groupsDir,
      customBackgroundDir,
    ]) {
      try {
        await dir.create(recursive: true);
      } catch (e) {
        rootDirectoriesUnavailable = true;
        debugPrint(
          '[Storage] ⚠ could not create "${dir.path}" ($e). Staying '
          'on this root anyway — the database is already open here, and '
          'moving would leave every portrait and chat file resolving '
          'somewhere the library\'s rows do not live.',
        );
      }
    }

    // Stage 7: initialize domain settings (plain classes) + load (moved from god)
    // Single notify surface preserved (see plan "Why not multiple ChangeNotifiers").
    _generationSettings.initializeBase(_prefs, notifyListeners);
    _backendSettings.initializeBase(_prefs, notifyListeners);
    _uiSettings.initializeBase(_prefs, notifyListeners);
    _ttsSettings.initializeBase(_prefs, notifyListeners);
    _sttSettings.initializeBase(_prefs, notifyListeners);
    _imageGenSettings.initializeBase(_prefs, notifyListeners);
    _expressionSettings.initializeBase(_prefs, notifyListeners);
    _webServerSettings.initializeBase(_prefs, notifyListeners);
    _realismSettings.initializeBase(_prefs, notifyListeners);
    _webSearchSettings.initializeBase(_prefs, notifyListeners);
    _memorySettings.initializeBase(_prefs, notifyListeners);
    _presetSettings.initializeBase(_prefs, notifyListeners);
    _lorebookSettings.initializeBase(_prefs, notifyListeners);

    // Nothing between here and the completer may escape. _init is
    // fire-and-forget, so one throw (a corrupt prefs value) would leave
    // `initialized` unresolved FOREVER — the same wedge the makeDirs fallback
    // above exists to prevent, and it silently costs the web-server autostart,
    // groups and worlds. Whatever failed keeps its in-code defaults.
    try {
      _generationSettings.load();
      _backendSettings.load();
      _uiSettings.load();
      _ttsSettings.load();
      _sttSettings.load();
      _imageGenSettings.load();
      _expressionSettings.load();
      _webServerSettings.load();
      _realismSettings.load();
      await _webSearchSettings.load();
      _memorySettings.load();
      _presetSettings.load();
      _lorebookSettings.load();
      attachReasoningEffortMenuStore(_prefs);

      if (!_presetSettings.savedPrompts.any(
        (p) => p['name'] == 'Immersive Roleplay',
      )) {
        await _presetSettings.savePrompt(
          'Immersive Roleplay',
          PresetSettings.defaultSystemPrompt,
        );
      }

      final loadedCustom = _prefs?.getString(_k('custom_models_path'));
      _customModelsPath = (loadedCustom != null && loadedCustom.isNotEmpty)
          ? loadedCustom
          : null;

      final loadedSpell = _prefs?.getString(_k('spell_check_language'));
      if (loadedSpell != null && loadedSpell.isNotEmpty) {
        DesktopSpellCheckService.activeLanguage = loadedSpell;
      }
    } catch (e, st) {
      debugPrint(
        '[Storage] ⚠ settings load failed ($e) — booting with '
        'defaults for whatever did not load.\n$st',
      );
    }

    if (!_initCompleter.isCompleted) _initCompleter.complete();
    notifyListeners();
  }

  /// Change the root installation directory and relocate all data files.
  /// Returns null on success, or a human-readable reason on refusal.
  Future<String?> setRootPath(String pathStr) async {
    final oldRoot = _rootPath;
    if (oldRoot == pathStr) return null;

    final refusal = await relocateRootDirectories(oldRoot, pathStr);
    if (refusal != null) return refusal;

    _rootPath = pathStr;
    _binDir = Directory(path.join(_rootPath!, 'koboldcpp_bin'));
    await _prefs?.setString(_rootPathKey, pathStr);

    await chatsDir.create(recursive: true);
    await modelsDir.create(recursive: true);
    await worldsDir.create(recursive: true);
    await toolsDir.create(recursive: true);
    await charactersDir.create(recursive: true);
    await groupsDir.create(recursive: true);
    await customBackgroundDir.create(recursive: true);

    if (oldRoot != null) {
      await repointCustomBackgroundsAfterRootMove(
        oldRoot: oldRoot,
        newRoot: pathStr,
        backgrounds: uiSettings.customBackgrounds,
        remove: uiSettings.removeCustomBackground,
        add: uiSettings.addCustomBackground,
      );
    }

    notifyListeners();
    return null;
  }
}
