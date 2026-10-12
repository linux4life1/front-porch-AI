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

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/waifu/waifu_session_scope.dart';

/// Every change to an open Waifu session goes through here, so widgets
/// only read the session and call back. Each change is saved; a failed
/// save is logged and handed to [onError] instead of vanishing.
class WaifuSessionController extends ChangeNotifier {
  WaifuSessionController({
    required this.session,
    this.store,
    Future<void> Function()? releaseTools,
  }) : _releaseTools = releaseTools ?? releasePorchToolsMcp;

  final WaifuSession session;
  final WaifuStore? store;
  final Future<void> Function() _releaseTools;

  /// Shown to the user, e.g. as a snackbar. Set by the page.
  void Function(String message)? onError;

  WaifuHarness? _harness;
  WaifuHarness? get harness => _harness;

  Uint8List? _pendingImage;
  bool? _visionOk;
  String? _blindReason;
  Uint8List? get pendingImage => _pendingImage;
  bool? get visionOk => _visionOk;
  String? get blindReason => _blindReason;

  bool get canUndo => _harness?.canUndo == true;
  bool get canRedo => _harness?.canRedo == true;

  /// Binds the turn runner once; its progress repaints listeners.
  void attach(WaifuHarness? harness) {
    _harness = harness;
    harness?.onChanged = notifyListeners;
  }

  Future<void> save() async {
    final s = store;
    if (s == null) return;
    try {
      await s.saveLast(session);
    } catch (e) {
      debugPrint('[Waifu] Session save failed for ${session.folderRoot}: $e');
      onError?.call('Could not save this session: $e');
    }
  }

  Future<void> setMode(WaifuMode mode) async {
    if (session.mode == mode) return;
    final h = _harness;
    if (h != null) {
      h.applyMode(mode);
    } else {
      session.mode = mode;
    }
    notifyListeners();
    await save();
  }

  Future<void> setPathMode(WaifuPathMode next) async {
    if (session.pathMode == next) return;
    final h = _harness;
    if (h != null) {
      h.applyPathMode(next);
    } else {
      session.pathMode = next;
    }
    notifyListeners();
    await save();
  }

  Future<void> setPreserveThinking(bool value) async {
    session.preserveThinking = value;
    _harness?.refreshMeter();
    notifyListeners();
    await save();
  }

  Future<void> setToolsOptIn(bool value) async {
    final h = _harness;
    if (h != null) {
      h.applyToolsOptIn(value);
    } else {
      session.mcpOptIn = value;
    }
    notifyListeners();
    if (!value) unawaited(_releaseTools());
    await save();
  }

  Future<void> setGenSettings(
    ChatGenerationSettings next, {
    int? contextBudget,
  }) async {
    session.genSettings = next;
    if (contextBudget != null) session.contextBudget = contextBudget;
    notifyListeners();
    await save();
  }

  Future<void> setThemeOverrides(ChatThemeOverrides next) async {
    session.themeOverrides = next;
    notifyListeners();
    await save();
  }

  /// Resume and card edits: the voice follows the library card.
  Future<void> followLibraryCard(CharacterCard? live) async {
    if (live == null || !waifuAdoptCoworker(session, live)) return;
    notifyListeners();
    await save();
  }

  void setContextBudget(int budget) => session.contextBudget = budget;

  void setToolsSupported(bool supported) {
    if (session.toolsSupported == supported) return;
    session.toolsSupported = supported;
    notifyListeners();
  }

  /// Sizes the meter before the first turn, then saves so a fresh session
  /// is never stored as 0 tokens used.
  Future<void> armMeter({int mcpToolCount = 0}) async {
    if (session.tokensUsed == 0 && !session.tokensFromApi) {
      session.tokensUsed = waifuIdleRequestTokens(
        session,
        mcpToolCount: mcpToolCount,
      );
    }
    _harness?.refreshMeter();
    await save();
  }

  void dismissReceipt() {
    session.lastWrite = null;
    session.turnWrites.clear();
    session.turnVerifyPaths.clear();
    notifyListeners();
  }

  void removeQueued(int index) {
    if (index < 0 || index >= session.queued.length) return;
    session.queued.removeAt(index);
    notifyListeners();
  }

  void holdImage(Uint8List bytes) {
    _pendingImage = bytes;
    _visionOk = null;
    _blindReason = null;
    notifyListeners();
  }

  /// Ignored when the photo it was checked for is no longer pending.
  void setVision(Uint8List forImage, {required bool ok, String? blindReason}) {
    if (!identical(_pendingImage, forImage)) return;
    _visionOk = ok;
    _blindReason = blindReason;
    notifyListeners();
  }

  void dropImage() {
    _pendingImage = null;
    _visionOk = null;
    _blindReason = null;
    notifyListeners();
  }

  /// False when nothing went out: empty, or no model to send to. With no
  /// model a stage line says so and the caller keeps the words.
  /// [onAccepted] runs once the words are taken, before the turn starts.
  Future<bool> send(String text, {VoidCallback? onAccepted}) async {
    final words = text.trim();
    final photo = _pendingImage;
    if (words.isEmpty && photo == null) return false;
    final h = _harness;
    if (h == null) {
      session.transcript.add(WaifuStage.of(session).noModel());
      notifyListeners();
      return false;
    }
    onAccepted?.call();
    String? imagePath;
    if (photo != null) {
      dropImage();
      try {
        imagePath = await waifuSaveInboxPhoto(session.folderRoot, photo);
      } catch (e) {
        debugPrint('[Waifu] Photo not saved to the inbox: $e');
        onError?.call('Could not save the photo into the folder: $e');
      }
    }
    await h.send(words, imagePng: photo, imagePath: imagePath);
    return true;
  }

  /// The session's language servers, made on first use in [dirOf].
  WaifuLangRuntime langs(String Function() dirOf) =>
      session.langs ??= WaifuLangRuntime(directory: dirOf());

  void abort() => _harness?.abort();
  Future<void> undo() async => _harness?.undo();
  Future<void> redo() async => _harness?.redo();
  Future<void> compact() async => _harness?.compact();

  @override
  void dispose() {
    session.langs?.killAll();
    final h = _harness;
    if (h != null) {
      h.onChanged = null;
      h.abort();
    }
    unawaited(_releaseTools());
    super.dispose();
  }
}
