// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';
import 'dart:typed_data';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/storage_service.dart';

/// The portrait a pack is built from when the person picked none: the
/// character's prime expression avatar (else any avatar), else the card's own
/// image. Null when the character has no picture at all.
Future<Uint8List?> packBaseImage(
  CharacterRepository repository,
  StorageService storage,
  String characterDbId,
  String characterName,
) async {
  CharacterCard? card;
  for (final c in repository.characters) {
    if (c.dbId == characterDbId) {
      card = c;
      break;
    }
  }

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

  final imagePath = card?.imagePath;
  if (imagePath != null && imagePath.isNotEmpty) {
    final file = File(imagePath);
    if (await file.exists()) return file.readAsBytes();
  }
  return null;
}
