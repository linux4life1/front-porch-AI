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

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:window_manager/window_manager.dart';

import 'package:front_porch_ai/services/chat/scene/scene_effects.dart';
import 'package:front_porch_ai/services/chat/scene/scene_effects_sim.dart';
import 'package:front_porch_ai/services/chat/scene/scene_tokens.dart';
import 'ambient_stage_game.dart';

/// Hosts the [AmbientStageGame] behind the chat column and owns its pause.
///
/// A static stage ([animated] false: the tint, or the weather under reduce
/// motion) never runs the engine loop: it paints once when it loads and
/// once per change of scene, so it costs no frames at all, and any weather
/// on it holds still where it is. An animated stage (the effects) ticks
/// only while the app is visible and the window has focus, so a stage
/// nobody is looking at costs nothing on a laptop or beside a local model
/// on the same GPU; with Pause effects while generating on, it also stops
/// while [generating] and starts again when the reply is done. The caller
/// mounts it only when there is a scene to paint; Off means not mounted.
/// It never takes focus or a Tab stop.
class AmbientStage extends StatefulWidget {
  const AmbientStage({
    super.key,
    required this.tokens,
    this.animated = false,
    this.generating = false,
    this.onFlash,
  });

  final SceneTokens tokens;

  /// Whether anything on the stage moves. False paints on change only.
  final bool animated;

  /// Whether a reply is being generated now.
  final bool generating;

  /// Each storm flash as the stage fires it, for the scene sound's thunder.
  final ValueChanged<SceneFlash>? onFlash;

  @override
  State<AmbientStage> createState() => _AmbientStageState();
}

class _AmbientStageState extends State<AmbientStage>
    with WidgetsBindingObserver, WindowListener {
  late final AmbientStageGame _game = AmbientStageGame(widget.tokens)
    ..effectsFrozen = !widget.animated;
  bool _appVisible = true;
  StreamSubscription<SceneFlash>? _flashes;

  /// True until the window plugin answers, so a stage on a platform
  /// without one still runs.
  bool _windowFocused = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    windowManager.addListener(this);
    _flashes = _game.flashes.listen((flash) => widget.onFlash?.call(flash));
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
    final flashes = _flashes;
    if (flashes != null) unawaited(flashes.cancel());
    WidgetsBinding.instance.removeObserver(this);
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void didUpdateWidget(AmbientStage old) {
    super.didUpdateWidget(old);
    _game.effectsFrozen = !widget.animated;
    _game.tokens = widget.tokens;
    _applyPause();
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
  bool get shouldRun =>
      widget.animated && _appVisible && _windowFocused && !_pausedForReply;

  bool get _pausedForReply =>
      widget.generating &&
      widget.tokens.pauseWhileGenerating &&
      widget.tokens.level == SceneLevel.effects;

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
