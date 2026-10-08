// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:typed_data';

import 'package:front_porch_ai/services/services.dart';

/// Reads the card's current portrait from its stored image path.
Future<Uint8List?> packCurrentPortraitImage(
  CharacterRepository repository,
  StorageService storage,
  String characterDbId,
) async {
  final card = await repository.getCharacterCardById(characterDbId);
  final path = card?.imagePath;
  if (path == null || path.isEmpty) return null;
  final file = storage.resolveCharacterImage(path);
  return await file.exists() ? file.readAsBytes() : null;
}

/// Current card portrait, falling back to existing expression avatars.
Future<Uint8List?> packBaseImage(
  CharacterRepository repository,
  StorageService storage,
  String characterDbId,
  String characterName,
) async {
  final portrait = await packCurrentPortraitImage(
    repository,
    storage,
    characterDbId,
  );
  if (portrait != null) return portrait;

  final card = await repository.getCharacterCardById(characterDbId);

  final avatars = await repository.getAvatarImages(characterDbId);
  if (avatars.isNotEmpty) {
    // primeAvatarIndex is 1-based; clamp handles stale indices.
    final primeIdx = ((card?.primeAvatarIndex ?? 1) - 1).clamp(
      0,
      avatars.length - 1,
    );
    final dirPath = storage.characterAvatarDir(characterName).path;
    for (final avatar in [avatars[primeIdx], ...avatars]) {
      final file = avatar.file(dirPath);
      if (await file.exists()) return file.readAsBytes();
    }
  }

  return null;
}
