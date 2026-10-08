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
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'backporch_api.dart';

/// Card art loader shared by every Stoop image on desktop.
///
/// Mirrors what the hub site does for the same art: bytes are kept on disk
/// under [dir] (`<id>.t` for the thumb, `<id>.f` for the original) so a
/// relaunch never refetches, and at most [maxConcurrent] fetches run at once
/// so a browse grid of two-megabyte originals cannot stall the hub. Flutter's
/// own in-memory image cache sits above this and dedupes repeated tiles.
class StoopAssetCache {
  StoopAssetCache({required this.dir, BackporchApi? api})
    : _api = api ?? BackporchApi();

  /// Hub `AVATAR_MAX` — the number the droplet is known to cope with.
  static const maxConcurrent = 3;

  static StoopAssetCache? _shared;

  /// One loader per app so the cap spans every grid, hero and avatar.
  static StoopAssetCache shared(Directory dir) {
    final s = _shared;
    if (s != null && s.dir.path == dir.path) return s;
    return _shared = StoopAssetCache(dir: dir);
  }

  /// Drop every picture on disk. Stoop art is served to signed-in users
  /// only, so a sign-out must not leave the last account's grid behind for
  /// whoever signs in next on the same machine.
  static Future<void> forgetAll() async {
    final s = _shared;
    if (s == null) return;
    if (await s.dir.exists()) await s.dir.delete(recursive: true);
  }

  final Directory dir;
  final BackporchApi _api;

  int _busy = 0;
  final _waiting = <Completer<void>>[];

  /// Bytes for [assetId], from disk when present, else fetched with [token]
  /// and written for next time. Throws like [BackporchApi.assetBytes] when
  /// the server refuses, so an image's errorBuilder can show its placeholder.
  Future<Uint8List> bytes(
    String assetId, {
    required bool thumb,
    required String token,
  }) async {
    final file = File(p.join(dir.path, _fileName(assetId, thumb)));
    if (await file.exists()) return file.readAsBytes();

    await _acquire();
    try {
      final data = await _api.assetBytes(token, assetId, thumb: thumb);
      await _store(file, data);
      return data;
    } finally {
      _release();
    }
  }

  /// Whether [assetId] is already on disk (no fetch).
  Future<bool> has(String assetId, {required bool thumb}) =>
      File(p.join(dir.path, _fileName(assetId, thumb))).exists();

  static String _fileName(String assetId, bool thumb) {
    final safe = assetId.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return '$safe.${thumb ? 't' : 'f'}';
  }

  // Write beside, then rename: a half-written file must never be served as
  // an image on the next launch.
  Future<void> _store(File file, Uint8List data) async {
    await dir.create(recursive: true);
    final tmp = File('${file.path}.part');
    await tmp.writeAsBytes(data, flush: true);
    await tmp.rename(file.path);
  }

  Future<void> _acquire() async {
    if (_busy < maxConcurrent) {
      _busy++;
      return;
    }
    final slot = Completer<void>();
    _waiting.add(slot);
    await slot.future;
  }

  void _release() {
    if (_waiting.isNotEmpty) {
      _waiting.removeAt(0).complete();
      return;
    }
    _busy--;
  }
}
