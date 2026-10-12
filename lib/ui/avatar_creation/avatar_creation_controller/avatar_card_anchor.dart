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

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';

/// The card the creator works on and the emotion labels it already has.
///
/// The card is persisted once, on first use, through the host's
/// `ensureCardSaved`; every later caller reuses it.
class AvatarCardAnchor {
  AvatarCardAnchor({
    required this.ensureCardSaved,
    required this.repository,
    required this.isDisposed,
    required this.notify,
    CharacterCard? card,
  }) : _card = card;

  final Future<CharacterCard?> Function() ensureCardSaved;
  final CharacterRepository repository;
  final bool Function() isDisposed;
  final VoidCallback notify;

  CharacterCard? _card;
  Set<String> _existingEmotions = const {};

  /// The one in-flight first-persist (see [ensure]'s single-flight guard).
  Future<bool>? _ensuring;

  CharacterCard? get card => _card;
  Set<String> get existingEmotions => _existingEmotions;

  void addEmotions(Iterable<String> emotions) {
    _existingEmotions = {..._existingEmotions, ...emotions};
  }

  /// Single-flight: two quick user actions before the first persist lands
  /// (upload + ZIP, say) must NOT both see a null dbId and addCharacter
  /// twice — every concurrent caller awaits the ONE in-flight save.
  Future<bool> ensure() {
    if (_card?.dbId != null && _ensuring == null) {
      return loadExistingEmotions().then((_) => true);
    }
    return _ensuring ??= _ensureOnce().whenComplete(() => _ensuring = null);
  }

  Future<bool> _ensureOnce() async {
    if (_card?.dbId != null) return true;
    final c = await ensureCardSaved();
    if (isDisposed()) return false;
    if (c == null || c.dbId == null) return false;
    _card = c;
    await loadExistingEmotions();
    if (!isDisposed()) notify();
    return true;
  }

  Future<void> loadExistingEmotions() async {
    final id = _card?.dbId;
    if (id == null) return;
    _existingEmotions = (await repository.getAvatarImages(id))
        .map((a) => (a.label ?? '').toLowerCase())
        .where((l) => l.isNotEmpty && l != AvatarImage.lookLabel)
        .toSet();
  }
}
