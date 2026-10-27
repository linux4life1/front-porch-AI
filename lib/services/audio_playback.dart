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

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The one door to an audioplayers [AudioPlayer].
///
/// On Linux, audioplayers builds a GStreamer `playbin` inside its native
/// player constructor and throws an uncaught C++ exception when the element
/// is missing (no `gstreamer1.0-plugins-base`), which aborts the whole app
/// (issue #625). Dart cannot catch that, so before any player is built the
/// Linux runner is asked whether `playbin` exists
/// (`linux/runner/my_application.cc`). Every other desktop plays through the
/// OS media stack and is always available.
class AudioPlayback {
  AudioPlayback._();

  static const _channel = MethodChannel('front_porch_ai/audio_support');
  static Future<bool>? _available;

  /// Forces the runner probe on (true) or off (false) whatever the OS.
  @visibleForTesting
  static bool? debugProbeOverride;

  /// What the user is told when sound is off for want of GStreamer.
  static const missingMessage =
      'Sound is off: this computer is missing the GStreamer base plugins. '
      'Install gstreamer1.0-plugins-base (Debian/Ubuntu), gst-plugins-base '
      '(Arch) or gstreamer1-plugins-base (Fedora), then restart Front Porch AI.';

  /// Whether a native player can be built here. Probed once per run.
  static Future<bool> available() => _available ??= _probe();

  /// A new player, or null when [available] is false.
  static Future<AudioPlayer?> create() async =>
      await available() ? AudioPlayer() : null;

  static Future<bool> _probe() async {
    if (!(debugProbeOverride ?? Platform.isLinux)) return true;
    try {
      return await _channel.invokeMethod<bool>('canPlay') ?? true;
    } on MissingPluginException {
      // A runner without the probe (headless tests) behaves as before.
      return true;
    } catch (e) {
      debugPrint('[Audio] playback probe failed, assuming available: $e');
      return true;
    }
  }

  @visibleForTesting
  static void debugReset() {
    _available = null;
    debugProbeOverride = null;
  }
}
