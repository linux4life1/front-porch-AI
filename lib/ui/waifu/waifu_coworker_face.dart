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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';

/// The library's live copy of [coworker]: by id, else by name. Null when
/// the card is gone or no repository is in the tree. [listen] subscribes
/// the caller so a card edit rebuilds it.
CharacterCard? waifuLibraryCard(
  BuildContext context,
  CharacterCard coworker, {
  bool listen = false,
}) {
  try {
    final repo = Provider.of<CharacterRepository>(context, listen: listen);
    for (final c in repo.characters) {
      if (coworker.dbId != null && c.dbId != null && c.dbId == coworker.dbId) {
        return c;
      }
      if (c.name == coworker.name) return c;
    }
  } on ProviderNotFoundException {
    // Tests without the repository have no library to follow.
  }
  return null;
}

/// Same face chat / the home grid show: live library card ★ cover, else
/// the portrait file. Session JSON is a thin copy and often has no path.
File? waifuCoworkerFace(BuildContext context, CharacterCard coworker) {
  final card = waifuLibraryCard(context, coworker) ?? coworker;
  try {
    final repo = Provider.of<CharacterRepository>(context, listen: false);
    final cover = repo.coverImageFileFor(card);
    if (cover != null) return cover;
  } on ProviderNotFoundException {
    // Tests without the repository fall through to imagePath.
  }
  final path = card.imagePath ?? coworker.imagePath;
  if (path == null || path.isEmpty) return null;
  try {
    return Provider.of<StorageService>(
      context,
      listen: false,
    ).resolveCharacterImage(path);
  } on ProviderNotFoundException {
    return File(path);
  }
}
