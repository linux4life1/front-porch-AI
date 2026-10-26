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

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:window_manager/window_manager.dart';

import 'package:front_porch_ai/services/chat/scene/scene_tokens.dart';
import 'ambient_stage_game.dart';

/// Hosts the [AmbientStageGame] behind the chat column and owns its pause.
///
/// A static stage ([animated] false, the tint) never runs the engine loop:
/// it paints once when it loads and once per change of scene, so a tint
/// costs no frames at all. An animated stage (the effects) ticks only while
/// the app is visible and the window has focus, so a stage nobody is
/// looking at costs nothing on a laptop or beside a local model on the same
/// GPU. The caller mounts it only when there is a scene to paint; Off means
/// not mounted. It never takes focus or a Tab stop.
class AmbientStage extends StatefulWidget {
  const AmbientStage({super.key, required this.tokens, this.animated = false});

  final SceneTokens tokens;

  /// Whether anything on the stage moves. False paints on change only.
  final bool animated;

  @override
  State<AmbientStage> createState() => _AmbientStageState();
}

class _AmbientStageState extends State<AmbientStage>
    with WidgetsBindingObserver, WindowListener {
  late final AmbientStageGame _game = AmbientStageGame(widget.tokens);
  bool _appVisible = true;

  /// True until the window plugin answers, so a stage on a platform
  /// without one still runs.
  bool _windowFocused = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    windowManager.addListener(this);
    _applyPause();
    _readWindowFocus();
  }

  Future<void> _readWindowFocus() async {
    try {
      final focused = await windowManager.isFocused();
      if (!mounted) return;
      _windowFocused = focused;
      _applyPause();
    } on MissingPluginException {
      // No window plugin (widget tests, or an embedder without one): there
      // is no focus to follow, so the stage keeps the visible default.
    } catch (e, st) {
      debugPrint('AmbientStage: could not read window focus: $e\n$st');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void didUpdateWidget(AmbientStage old) {
    super.didUpdateWidget(old);
    _game.tokens = widget.tokens;
    if (old.animated != widget.animated) _applyPause();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appVisible = state == AppLifecycleState.resumed;
    _applyPause();
  }

  @override
  void onWindowBlur() {
    _windowFocused = false;
    _applyPause();
  }

  @override
  void onWindowFocus() {
    _windowFocused = true;
    _applyPause();
  }

  @override
  void onWindowMinimize() {
    _appVisible = false;
    _applyPause();
  }

  @override
  void onWindowRestore() {
    _appVisible = true;
    _applyPause();
  }

  /// Whether the engine loop should be ticking now.
  bool get shouldRun => widget.animated && _appVisible && _windowFocused;

  void _applyPause() {
    if (shouldRun) {
      if (_game.paused) _game.resumeEngine();
    } else if (!_game.paused) {
      _game.pauseEngine();
      // A stage that just stopped animating keeps its last scene painted.
      if (!widget.animated) _game.repaintOnce();
    }
  }

  @override
  Widget build(BuildContext context) {
    // GameWidget wraps the game in its own Focus even with autofocus off,
    // which made the stage a Tab stop; the composer keeps the keyboard.
    return ExcludeFocus(child: GameWidget(game: _game, autofocus: false));
  }
}
