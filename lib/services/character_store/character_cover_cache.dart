// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/storage_service.dart';

/// Memo for card cover resolution: chat message bubbles resolve the cover
/// on EVERY rebuild (dozens of bubbles × every streaming token batch),
/// and the uncached path does a synchronous existsSync per call — near
/// free on macOS/APFS, but 10-100x slower on Windows where Defender
/// intercepts file stats. Field-reported as "the app got sluggish" in
/// the 20260716 nightly. The key embeds the star id, portrait path and
/// cover epoch, so changing any of them self-invalidates; the repository
/// also [clear]s on mutations to cover files changing on disk under an
/// unchanged key.
class CharacterCoverCache {
  CharacterCoverCache(this._storage);

  final StorageService _storage;
  final Map<String, File?> _cache = {};

  void clear() => _cache.clear();

  /// The ★ starred avatar when set and present on disk, else the library
  /// portrait. Null when neither resolves.
  File? fileFor(CharacterCard card, {required int epoch}) {
    final favId = card.frontPorchExtensions?.favoriteAvatarId;
    final key = '${card.name}|$favId|${card.imagePath}|$epoch';
    if (_cache.containsKey(key)) return _cache[key];
    if (_cache.length > 512) _cache.clear();

    File? result;
    if (favId != null) {
      for (final a in card.avatarImages ?? const <AvatarImage>[]) {
        if (a.id == favId) {
          final f = a.resolveFile(_storage.characterBaseDir(card.name).path);
          if (f.existsSync()) result = f;
          break;
        }
      }
    }
    if (result == null) {
      final img = card.imagePath;
      if (img != null && img.isNotEmpty) {
        result = _storage.resolveCharacterImage(img);
      }
    }
    _cache[key] = result;
    return result;
  }
}
