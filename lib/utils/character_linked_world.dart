// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Detects legacy "character worlds" — auto-cloned character lorebooks that
// cluttered the Worlds tab. Real places never have a linked character.

import 'package:front_porch_ai/models/world.dart';

/// True when [world] is a legacy character-lore clone, not a real place.
///
/// Signals (any one is enough):
/// - linked character id/name set
/// - description is the auto-import boilerplate
bool isCharacterLinkedWorld(World world) {
  final linkedId = world.linkedCharacterId?.trim() ?? '';
  if (linkedId.isNotEmpty) return true;
  final linkedName = world.linkedCharacterName?.trim() ?? '';
  if (linkedName.isNotEmpty) return true;
  final desc = world.description.trim().toLowerCase();
  if (desc.startsWith('auto-imported from character card')) return true;
  return false;
}
