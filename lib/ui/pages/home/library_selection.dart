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

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// Multi-select and Organize into folders: the two picking modes.
enum LibraryPickMode { none, select, organize }

/// The home library's picks, in one place: which mode, which cards (by
/// selection key: character stableGroupId, group id) and the card a
/// Shift-click ranges from. Every gesture — tap, Ctrl/Cmd-click, Shift-click,
/// a box, Select all, Move to Folder — goes through here, so the home page
/// and the tests drive the same rules.
class LibrarySelection extends ChangeNotifier {
  LibraryPickMode _mode = LibraryPickMode.none;
  final Set<String> characterIds = {};
  final Set<String> groupIds = {};
  String? _anchor;

  bool get isSelecting => _mode == LibraryPickMode.select;
  bool get isOrganizing => _mode == LibraryPickMode.organize;
  bool get picking => _mode != LibraryPickMode.none;
  bool get isEmpty => characterIds.isEmpty && groupIds.isEmpty;

  void _clear() {
    characterIds.clear();
    groupIds.clear();
  }

  void toggleSelectMode() => _toggleMode(LibraryPickMode.select);
  void toggleOrganizeMode() => _toggleMode(LibraryPickMode.organize);

  void _toggleMode(LibraryPickMode mode) {
    _mode = _mode == mode ? LibraryPickMode.none : mode;
    if (_mode == LibraryPickMode.none) _clear();
    notifyListeners();
  }

  /// The ✕, Esc, and the end of a move: no picks, no mode.
  void cancel() {
    _mode = LibraryPickMode.none;
    _anchor = null;
    _clear();
    notifyListeners();
  }

  /// Select none: every pick out, hidden ones too; still picking.
  void selectNone() {
    _clear();
    notifyListeners();
  }

  /// Select all / Ctrl+A: adds what the grid shows and keeps hidden picks.
  /// Outside a mode it starts Multi-select.
  void selectAll(Set<String> characters, Set<String> groups) {
    if (characters.isEmpty && groups.isEmpty) return;
    if (!picking) _mode = LibraryPickMode.select;
    characterIds.addAll(characters);
    groupIds.addAll(groups);
    notifyListeners();
  }

  /// A plain click while picking, or Ctrl/Cmd-click anywhere: one card in
  /// or out. Outside a mode it starts Multi-select; taking the last pick out
  /// ends the mode, as it always has. The card becomes the Shift anchor.
  void toggle(String key, {required bool group}) {
    final set = group ? groupIds : characterIds;
    _anchor = key;
    if (set.remove(key)) {
      if (isEmpty) _mode = LibraryPickMode.none;
    } else {
      set.add(key);
      if (!picking) _mode = LibraryPickMode.select;
    }
    notifyListeners();
  }

  /// Shift-click: adds every card from the last clicked one to [key], in
  /// grid order ([order] — group ids then character keys, as shown). With
  /// no anchor on screen it is a plain toggle.
  void addRange(
    String key, {
    required bool group,
    required List<String> order,
    required Set<String> groupKeys,
  }) {
    final from = _anchor == null ? -1 : order.indexOf(_anchor!);
    final to = order.indexOf(key);
    if (from < 0 || to < 0) {
      toggle(key, group: group);
      return;
    }
    final lo = from < to ? from : to;
    final hi = from < to ? to : from;
    for (final k in order.sublist(lo, hi + 1)) {
      (groupKeys.contains(k) ? groupIds : characterIds).add(k);
    }
    if (!picking) _mode = LibraryPickMode.select;
    notifyListeners();
  }

  /// A box drag: these become the picks (the caller adds the picks it
  /// started from when Ctrl/Cmd was held). Starts Multi-select once the box
  /// touches a card.
  void replace(Set<String> characters, Set<String> groups) {
    characterIds
      ..clear()
      ..addAll(characters);
    groupIds
      ..clear()
      ..addAll(groups);
    if (!picking && !isEmpty) _mode = LibraryPickMode.select;
    notifyListeners();
  }

  /// Moves the picks to [folderId] (null: the top level) in one go, then
  /// ends the selection, as the Move to Folder button always has. Returns
  /// how many moved.
  Future<int> moveTo(
    String? folderId, {
    required FolderService folders,
    required List<CharacterCard> library,
  }) async {
    final byKey = <String, CharacterCard>{};
    for (final c in library) {
      byKey.putIfAbsent(c.stableGroupId, () => c);
    }
    final moved = await folders.moveMany(
      folderId: folderId,
      characterPaths: [for (final key in characterIds) ?byKey[key]?.imagePath],
      groupIds: {...groupIds},
    );
    cancel();
    return moved;
  }
}
