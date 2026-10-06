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

import 'dart:typed_data';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/porch/porch.dart';
import 'package:front_porch_ai/services/services.dart';

/// The phone's `.porch` / `.porchpack` export and import: the same
/// [PorchExporter] / [PorchImporter] the desktop library uses.
class PorchFacade {
  PorchFacade(this._repo, this._chat, this._storage);

  final CharacterRepository _repo;
  final ChatService _chat;
  final StorageService _storage;

  /// The characters with these library ids as one `.porch`, or one
  /// `.porchpack` for two or more, with how many went in. Group ids
  /// (`group_…`, as the library routes tell them apart) are not characters:
  /// they are left out and counted, so the phone can say so as the desktop
  /// does. With no character left, [PorchRefused] says so.
  Future<({String fileName, Uint8List bytes, int count, int groupsLeftOut})>
  export(List<String> ids) async {
    final wanted = ids.toSet();
    final cards = <CharacterCard>[
      for (final c in _repo.characters)
        if (c.dbId != null && wanted.contains(c.dbId)) c,
    ];
    if (cards.isEmpty) {
      throw const PorchRefused(
        'Pick at least one character to export. Groups can’t be exported to '
        'a .porch file yet.',
      );
    }
    final out = await PorchExporter(
      repo: _repo,
      chat: _chat,
      storage: _storage,
    ).exportCards(cards);
    return (
      fileName: out.fileName,
      bytes: out.bytes,
      count: cards.length,
      groupsLeftOut: wanted.where((id) => id.startsWith('group_')).length,
    );
  }

  Future<PorchImportReport> import(String fileName, Uint8List bytes) async {
    return PorchImporter(
      repo: _repo,
      chat: _chat,
    ).importFiles([(name: fileName, bytes: bytes)]);
  }
}
