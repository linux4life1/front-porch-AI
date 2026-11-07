// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Pure row ↔ model transforms and naming rules for the character library.

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/database/database.dart' hide AvatarImage;
import 'package:front_porch_ai/database/database.dart' as rows show AvatarImage;
import 'package:front_porch_ai/models/models.dart';

/// Extract the basename from a potentially full path (handles / and \).
/// Returns the input unchanged if it's already a basename.
String toBasename(String path) {
  return path.split(RegExp(r'[/\\]')).last;
}

/// Character-name → on-disk media folder name (same rule used everywhere an
/// avatar/look path is built). Centralized so the rename move can't drift
/// from the write/read/delete sites.
String mediaFolderName(String characterName) =>
    characterName.replaceAll(RegExp(r'[^\w\s\-]'), '').replaceAll(' ', '_');

/// Drift avatar row → model.
AvatarImage avatarFromRow(rows.AvatarImage a) => AvatarImage(
  id: a.id,
  characterId: a.characterId,
  filename: a.filename,
  label: a.label,
  displayOrder: a.displayOrder,
  createdAt: a.createdAt,
);

/// The card-text columns shared by insert and full update. [dbImagePath] is
/// the portable basename stored in the row.
CharactersCompanion characterCompanion(
  CharacterCard card, {
  required String? dbImagePath,
}) {
  return CharactersCompanion(
    name: Value(card.name),
    description: Value(card.description),
    personality: Value(card.personality),
    scenario: Value(card.scenario),
    firstMessage: Value(card.firstMessage),
    mesExample: Value(card.mesExample),
    systemPrompt: Value(card.systemPrompt),
    postHistoryInstructions: Value(card.postHistoryInstructions),
    alternateGreetings: Value(jsonEncode(card.alternateGreetings)),
    tags: Value(jsonEncode(card.tags)),
    imagePath: Value(dbImagePath),
    ttsVoice: Value(card.ttsVoice),
    lorebook: Value(
      card.lorebook != null ? jsonEncode(card.lorebook!.toJson()) : null,
    ),
    worldNames: Value(jsonEncode(card.worldNames)),
    loreWorldNames: Value(
      card.loreWorldNames == null ? null : jsonEncode(card.loreWorldNames),
    ),
  );
}

/// Convert a DB row into a CharacterCard model.
CharacterCard characterFromRow(Character c) {
  List<String> altGreetings = [];
  try {
    altGreetings = List<String>.from(jsonDecode(c.alternateGreetings));
  } catch (e) {
    debugPrint(
      '[CharacterRepo] Unreadable alternate greetings on "${c.name}": $e',
    );
  }

  List<String> tags = [];
  try {
    tags = List<String>.from(jsonDecode(c.tags));
  } catch (e) {
    debugPrint('[CharacterRepo] Unreadable tags on "${c.name}": $e');
  }

  List<String> worldNames = [];
  try {
    worldNames = List<String>.from(jsonDecode(c.worldNames));
  } catch (e) {
    debugPrint('[CharacterRepo] Unreadable world names on "${c.name}": $e');
  }

  List<String>? loreWorldNames;
  if (c.loreWorldNames != null) {
    try {
      loreWorldNames = List<String>.from(jsonDecode(c.loreWorldNames!));
    } catch (e) {
      debugPrint('[CharacterRepo] Unreadable lore worlds on "${c.name}": $e');
    }
  }

  Lorebook? lorebook;
  if (c.lorebook != null) {
    try {
      lorebook = Lorebook.fromJson(jsonDecode(c.lorebook!));
    } catch (e) {
      debugPrint('[CharacterRepo] Unreadable lorebook on "${c.name}": $e');
    }
  }

  final card = CharacterCard(
    name: c.name,
    description: c.description,
    personality: c.personality,
    scenario: c.scenario,
    firstMessage: c.firstMessage,
    mesExample: c.mesExample,
    systemPrompt: c.systemPrompt,
    postHistoryInstructions: c.postHistoryInstructions,
    alternateGreetings: altGreetings,
    tags: tags,
    imagePath: c.imagePath,
    ttsVoice: c.ttsVoice,
    lorebook: lorebook,
    worldNames: worldNames,
    loreWorldNames: loreWorldNames,
  );
  // Store DB id for lookups
  card.dbId = c.id;
  // Library "date added" — used by the home-screen "Import Date" sort. Reading
  // the real DB column (instead of parsing a timestamp out of the image
  // filename) means cards without the legacy `<name>_<epoch>.png` naming
  // (JSON imports, Chub downloads, renamed files) still sort correctly.
  card.createdAt = c.createdAt;
  card.primeAvatarIndex = c.primeAvatarIndex;
  return card;
}
