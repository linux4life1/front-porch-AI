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
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/audio_playback.dart';
import 'package:front_porch_ai/services/storage_service.dart';

/// Custom scene-sound files are user-owned, so they live under
/// `$rootPath/audio/` (never `assets/`) and are referenced by bare name.
/// The desktop picker copies by path, the PWA upload writes bytes; both go
/// through the same header check, size cap and load test here. A bare name
/// is resolved against the live root at play/serve time, so a data-root move
/// or another machine never breaks it.
class UserAudioStore {
  const UserAudioStore._();

  /// A sound file can be tens of megabytes; cap it so a huge pick never
  /// fills the user's data folder (and a 30 MB file is still streamed by
  /// the web server, never read whole per request).
  static const int kUserAudioMaxBytes = 30 * 1024 * 1024;

  /// Test seam: when set, the load test runs this instead of a real player.
  @visibleForTesting
  static Future<void> Function(String path)? testLoadOverride;

  /// Test seam: when set, [listUserAudio] answers this instead of reading
  /// the directory — so a widget test can face the real panel with fake
  /// time (a real directory read cannot complete inside the fake zone).
  @visibleForTesting
  static Future<List<({String name, int bytes, int modifiedMs})>> Function()?
  testListOverride;

  /// Store a picked file by its path (desktop: copy by path, not bytes).
  /// Returns the bare name to reference, an error to surface, and a note
  /// when the load test was skipped (Linux without GStreamer).
  static Future<({String? name, String? error, String? note})>
  storeUserAudioPath(String path, StorageService storage) async {
    final name = p.basename(path);
    if (!name.toLowerCase().endsWith('.mp3')) {
      return (name: null, error: 'Only MP3 files are supported.', note: null);
    }
    final size = await File(path).length();
    if (size > kUserAudioMaxBytes) {
      return (
        name: null,
        error:
            'That sound file is larger than '
            '${kUserAudioMaxBytes ~/ (1024 * 1024)} MiB.',
        note: null,
      );
    }
    if (!_validMp3HeaderPath(path)) {
      return (
        name: null,
        error: 'That file is not a playable MP3.',
        note: null,
      );
    }
    final dir = storage.audioDir;
    final dest = File(p.join(dir.path, name));
    try {
      await dir.create(recursive: true);
      if (p.equals(path, dest.path)) {
        return (name: name, error: null, note: null);
      }
      await File(path).copy(dest.path);
    } catch (e) {
      return (
        name: null,
        error: 'Could not copy the file into your data folder ($e).',
        note: null,
      );
    }
    final load = await _loadTest(dest.path);
    if (!load.ok) {
      try {
        if (await dest.exists()) await dest.delete();
      } catch (_) {}
      return (
        name: null,
        error: 'That file could not be loaded here.',
        note: null,
      );
    }
    return (name: name, error: null, note: load.note);
  }

  /// Store uploaded bytes (PWA / phone app). The name is sanitized to the
  /// safe charset the web server's name guard accepts.
  static Future<({String? name, String? error, String? note})>
  storeUserAudioBytes(
    Uint8List bytes,
    String fileName,
    StorageService storage,
  ) async {
    final name = _safeName(fileName);
    if (!name.toLowerCase().endsWith('.mp3')) {
      return (name: null, error: 'Only MP3 files are supported.', note: null);
    }
    if (bytes.length > kUserAudioMaxBytes) {
      return (
        name: null,
        error:
            'That sound file is larger than '
            '${kUserAudioMaxBytes ~/ (1024 * 1024)} MiB.',
        note: null,
      );
    }
    if (!_validMp3HeaderBytes(bytes)) {
      return (
        name: null,
        error: 'That file is not a playable MP3.',
        note: null,
      );
    }
    final dir = storage.audioDir;
    final dest = File(p.join(dir.path, name));
    try {
      await dir.create(recursive: true);
      await dest.writeAsBytes(bytes, flush: true);
    } catch (e) {
      return (
        name: null,
        error: 'Could not write the file into your data folder ($e).',
        note: null,
      );
    }
    final load = await _loadTest(dest.path);
    if (!load.ok) {
      try {
        if (await dest.exists()) await dest.delete();
      } catch (_) {}
      return (
        name: null,
        error: 'That file could not be loaded here.',
        note: null,
      );
    }
    return (name: name, error: null, note: load.note);
  }

  /// [fileName] with anything outside the safe sound-name charset replaced
  /// by `_`, so an upload cannot name a path that climbs out of `audio/`.
  /// Every stored user sound, newest first: the picker's library. Only
  /// `.mp3` files the store itself put there are listed (its own naming
  /// discipline), with size and mtime so the UI can label and order them.
  static Future<List<({String name, int bytes, int modifiedMs})>> listUserAudio(
    StorageService storage,
  ) async {
    if (testListOverride != null) return testListOverride!();
    final dir = storage.audioDir;
    if (!await dir.exists()) return const [];
    final found = <({String name, int bytes, int modifiedMs})>[];
    await for (final entry in dir.list()) {
      if (entry is! File || !entry.path.toLowerCase().endsWith('.mp3')) {
        continue;
      }
      try {
        final stat = await entry.stat();
        found.add((
          name: p.basename(entry.path),
          bytes: stat.size,
          modifiedMs: stat.modified.millisecondsSinceEpoch,
        ));
      } catch (_) {
        // A file mid-write or just deleted: it will be there next open.
      }
    }
    found.sort((a, b) => b.modifiedMs.compareTo(a.modifiedMs));
    return found;
  }

  static String _safeName(String fileName) =>
      fileName.replaceAll(RegExp(r'[^A-Za-z0-9_.\-]'), '_').trim();

  /// MP3 header: an ID3v2 tag, or an MPEG audio frame sync (`0xFF` + a
  /// `0xE0`-masked second byte). FLAC's `fLaC` magic is rejected — FLAC
  /// stays out until a per-OS manual verification passes.
  static bool _validMp3HeaderBytes(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0x49 &&
        bytes[1] == 0x44 &&
        bytes[2] == 0x33) {
      return true;
    }
    return bytes.length >= 2 && bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0;
  }

  static bool _validMp3HeaderPath(String path) {
    try {
      final raf = File(path).openSync();
      try {
        final len = raf.lengthSync();
        final bytes = raf.readSync(len < 16 ? len : 16);
        return _validMp3HeaderBytes(bytes);
      } finally {
        raf.closeSync();
      }
    } catch (_) {
      return false;
    }
  }

  /// Load the copied file on a throwaway [AudioPlayer] with
  /// [setSourceDeviceFile]. That waits for the player's `prepared` event and
  /// throws when the platform reports a load error. On Linux with no
  /// GStreamer ([AudioPlayback] sound off) the load test is skipped, the
  /// header check stays, and the caller says so.
  static Future<({bool ok, String? note})> _loadTest(String path) async {
    final hook = testLoadOverride;
    if (hook != null) {
      try {
        await hook(path);
        return (ok: true, note: null);
      } catch (_) {
        return (ok: false, note: null);
      }
    }
    if (!await AudioPlayback.available()) {
      return (
        ok: true,
        note:
            'Sound is off here: the header check passed but no player '
            'could load-test the file.',
      );
    }
    final old = AudioPlayer.preparationTimeout;
    AudioPlayer.preparationTimeout = const Duration(seconds: 10);
    try {
      final player = AudioPlayer();
      try {
        await player.setSourceDeviceFile(path);
        return (ok: true, note: null);
      } finally {
        await player.dispose();
      }
    } catch (_) {
      return (ok: false, note: null);
    } finally {
      AudioPlayer.preparationTimeout = old;
    }
  }
}
