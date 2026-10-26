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
import 'package:window_manager/window_manager.dart';

import 'package:front_porch_ai/services/chat/scene/scene_effects.dart';
import 'package:front_porch_ai/services/chat/scene/scene_tokens.dart';
import 'ambient_stage_game.dart';

/// Hosts the [AmbientStageGame] behind the chat column and owns its pause
/// rules: the engine stops ticking while the app is hidden or inactive and
/// while the window has lost focus, so a stage nobody is looking at costs
/// nothing on a laptop or beside a local model on the same GPU. The caller
/// mounts it only when there is a scene to paint; Off means not mounted.
///
/// With the moving weather on, two more rules: the OS's reduce motion holds
/// the weather still where it is (the tint stays), and with Pause effects
/// while generating on, the engine stops while [generating] and starts
/// again when the reply is done. Tint only keeps ticking as before.
class AmbientStage extends StatefulWidget {
  const AmbientStage({
    super.key,
    required this.tokens,
    this.generating = false,
  });

  final SceneTokens tokens;

  /// Whether a reply is being generated now.
  final bool generating;

  @override
  State<AmbientStage> createState() => _AmbientStageState();
}

class _AmbientStageState extends State<AmbientStage>
    with WidgetsBindingObserver, WindowListener {
  late final AmbientStageGame _game = AmbientStageGame(widget.tokens);
  bool _appVisible = true;
  bool _windowFocused = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    windowManager.addListener(this);
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
    _applyPause();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _game.effectsFrozen = MediaQuery.disableAnimationsOf(context);
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

  /// Whether the engine should be ticking now.
  bool get shouldRun => _appVisible && _windowFocused && !_pausedForReply;

  bool get _pausedForReply =>
      widget.generating &&
      widget.tokens.pauseWhileGenerating &&
      widget.tokens.level == SceneLevel.effects;

  void _applyPause() {
    if (shouldRun) {
      if (_game.paused) _game.resumeEngine();
    } else if (!_game.paused) {
      _game.pauseEngine();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Never takes focus: the composer keeps the keyboard.
    return GameWidget(game: _game, autofocus: false);
  }
}
