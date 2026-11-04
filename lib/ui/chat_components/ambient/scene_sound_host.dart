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
    this.overlayOutput,
    this.rootPath,
  });

  final SceneTokens tokens;

  /// Appearance → Scene sound.
  final bool enabled;

  /// Appearance → Scene sound volume, 0 to 1.
  final double volume;

  /// Builds the stage, wiring its flashes to `onFlash`.
  final Widget Function(BuildContext context, ValueChanged<SceneFlash> onFlash)
  builder;

  /// Where the base sound goes; audioplayers unless a test hands in its own.
  final SceneSoundOutput Function()? output;

  /// Where the weather overlay goes; a second output instance. Null in tests
  /// that hand in only one fake — the overlay channel then stays off.
  final SceneSoundOutput Function()? overlayOutput;

  /// The live data root, so a custom user sound's bare name resolves against
  /// `$rootPath/audio/` at play time (a root move never breaks it).
  final String? rootPath;

  @override
  State<SceneSoundHost> createState() => _SceneSoundHostState();
}

class _SceneSoundHostState extends State<SceneSoundHost>
    with WidgetsBindingObserver, WindowListener {
  late final SceneSoundService _sound = SceneSoundService(
    output: widget.output ?? AudioplayersSceneSoundOutput.new,
    overlayOutput: widget.overlayOutput ?? AudioplayersSceneSoundOutput.new,
    audioRootPath: widget.rootPath,
  );

  TtsService? _tts;
  bool _appShown = true;
  bool _minimised = false;
  bool _focused = true;
  bool _inRail = false;
  Timer? _frameWatch;

  /// A Stage Manager rail thumbnail or off-screen park at this size or
  /// smaller. macOS composites the real window scaled down in the rail,
  /// so it stays "visible" and the app stays active — only the frame
  /// tells you the stage is out of sight. The chat surface is unusable
  /// under this width, so a frame this small is never a working window.
  static const double _kRailEdge = 400;
  static const Duration _kFramePoll = Duration(seconds: 1);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    windowManager.addListener(this);
    _frameWatch = Timer.periodic(_kFramePoll, (_) => _checkFrame());
    _checkFrame();
    unawaited(_syncFocus());
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
    _frameWatch?.cancel();
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

  // Focus counts as off while no window of the app is key: Stage
  // Manager parking the stage in the rail resigns key even while the
  // app stays active and the menu bar still names it.
  void _onVisibility() =>
      _sound.visible = _appShown && !_minimised && _focused && !_inRail;

  /// Focus at mount is assumed on (the chat page just came up); the
  /// honest answer arrives on the first blur/focus event. Asking
  /// window_manager directly is attempted once and ignored where the
  /// plugin is absent (headless tests).
  Future<void> _syncFocus() async {
    try {
      final focused = await windowManager.isFocused();
      if (!mounted || focused == _focused) return;
      _focused = focused;
      _onVisibility();
    } catch (_) {
      // A runner without window_manager: events alone drive focus.
    }
  }

  /// The frame check: Stage Manager parks the window as a rail thumbnail
  /// (or off-screen) while keeping the app active and the window
  /// nominally visible, so the frame size is the only tell that the
  /// stage is out of sight. Runners without window_manager (headless
  /// tests) simply never grow this reason to hold.
  Future<void> _checkFrame() async {
    bool? rail;
    try {
      final size = await windowManager.getSize();
      rail = size.width < _kRailEdge || size.height < _kRailEdge * 0.6;
    } catch (_) {
      return;
    }
    if (!mounted || rail == _inRail) return;
    _inRail = rail;
    _onVisibility();
  }

  // The rule: play while the stage is actually in sight. Holds when the
  // app goes to the background (Cmd-Tab, hidden, closed lid), when the
  // window minimises, when Stage Manager parks the stage in its rail
  // (that resigns key while the app stays active — the menu bar still
  // names it, so lifecycle alone misses it), and when the frame check
  // finds a thumbnail-sized or off-screen park. In-app dialogs and menus
  // never resign key, so they keep the music.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appShown = state == AppLifecycleState.resumed;
    _onVisibility();
  }

  @override
  void onWindowFocus() {
    _focused = true;
    _onVisibility();
  }

  @override
  void onWindowBlur() {
    _focused = false;
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
