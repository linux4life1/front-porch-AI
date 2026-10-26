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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'package:front_porch_ai/services/chat/scene/scene_effects_sim.dart';
import 'package:front_porch_ai/services/chat/scene/scene_sound_output.dart';
import 'package:front_porch_ai/services/chat/scene/scene_sound_service.dart';
import 'package:front_porch_ai/services/chat/scene/scene_tokens.dart';
import 'package:front_porch_ai/services/tts_service.dart';

/// Owns the chat's [SceneSoundService] for as long as the Ambient Stage is
/// up, and feeds it what it cannot see: the scene and the Scene sound
/// setting (from the chat page), whether a voice is speaking
/// ([TtsService.isSpeaking], the flag the call's microphone gate reads too,
/// so the duck covers the voice's whole turn), whether the window can be
/// seen (the app lifecycle and the window's minimise and restore), and the
/// stage's flashes, through the `onFlash` it hands to [builder] for the
/// `AmbientStage` it wraps. Unmounting it (the chat closes, or the scene
/// goes) stops the sound and frees the players.
class SceneSoundHost extends StatefulWidget {
  const SceneSoundHost({
    super.key,
    required this.tokens,
    required this.enabled,
    required this.volume,
    required this.builder,
    this.output,
  });

  final SceneTokens tokens;

  /// Appearance → Scene sound.
  final bool enabled;

  /// Appearance → Scene sound volume, 0 to 1.
  final double volume;

  /// Builds the stage, wiring its flashes to `onFlash`.
  final Widget Function(BuildContext context, ValueChanged<SceneFlash> onFlash)
  builder;

  /// Where the sound goes; audioplayers unless a test hands in its own.
  final SceneSoundOutput Function()? output;

  @override
  State<SceneSoundHost> createState() => _SceneSoundHostState();
}

class _SceneSoundHostState extends State<SceneSoundHost>
    with WidgetsBindingObserver, WindowListener {
  late final SceneSoundService _sound = SceneSoundService(
    output: widget.output ?? AudioplayersSceneSoundOutput.new,
  );
  TtsService? _tts;
  bool _appShown = true;
  bool _minimised = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    windowManager.addListener(this);
    _sync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    TtsService? tts;
    try {
      tts = Provider.of<TtsService>(context, listen: false);
    } on ProviderNotFoundException {
      // No voices on this tree (a test, or a build without TTS): nothing
      // to duck under.
    }
    if (identical(tts, _tts)) return;
    _tts?.removeListener(_onVoice);
    _tts = tts?..addListener(_onVoice);
    _onVoice();
  }

  @override
  void didUpdateWidget(SceneSoundHost old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _tts?.removeListener(_onVoice);
    WidgetsBinding.instance.removeObserver(this);
    windowManager.removeListener(this);
    unawaited(_sound.dispose());
    super.dispose();
  }

  void _sync() => _sound.update(
    tokens: widget.tokens,
    enabled: widget.enabled,
    volume: widget.volume,
  );

  void _onVoice() => _sound.speaking = _tts?.isSpeaking ?? false;

  void _onVisibility() => _sound.visible = _appShown && !_minimised;

  // Sound keeps playing in a window that is up but not focused, and while a
  // reply is generated; only a hidden or minimised window holds it.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appShown =
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    _onVisibility();
  }

  @override
  void onWindowMinimize() {
    _minimised = true;
    _onVisibility();
  }

  @override
  void onWindowRestore() {
    _minimised = false;
    _onVisibility();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _sound.onFlash);
}
