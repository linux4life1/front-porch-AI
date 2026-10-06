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
import 'package:front_porch_ai/ui/pages/home/cards/library_drag_payload.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// Multi-select and Organize into folders: the two picking modes.
enum LibraryPickMode { none, select, organize }

/// The home library's picks, in one place: which mode, which cards (by
/// selection key: character stableGroupId, group id), the card a Shift-click
/// ranges from, and a drag in flight. Every gesture — tap, Ctrl/Cmd-click,
/// Shift-click, a box, Select all, a drag onto a folder — goes through here,
/// so the home page and the tests drive the same rules.
class LibrarySelection extends ChangeNotifier {
  LibraryPickMode _mode = LibraryPickMode.none;
  final Set<String> characterIds = {};
  final Set<String> groupIds = {};
  String? _anchor;
  int _dragCount = 0;
  bool _dragsPicks = false;
  bool _dragCalledOff = false;

  bool get isSelecting => _mode == LibraryPickMode.select;
  bool get isOrganizing => _mode == LibraryPickMode.organize;
  bool get picking => _mode != LibraryPickMode.none;
  bool get isEmpty => characterIds.isEmpty && groupIds.isEmpty;

  /// Cards in a drag that is in flight; 0 when nothing is being dragged,
  /// or Esc called the drag off.
  int get dragCount => _dragCalledOff ? 0 : _dragCount;

  /// The drag in flight carries the picks (not one card).
  bool get dragsPicks => _dragsPicks && !_dragCalledOff;

  /// Esc called the drag in flight off: nothing it is dropped on may take it.
  bool get dragCalledOff => _dragCalledOff;

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
    _resetDrag();
    _clear();
    notifyListeners();
  }

  /// Esc: calls off a drag in flight — nothing will drop and the picks stay —
  /// or, with no drag, ends the selection like the ✕. Flutter cannot end
  /// the drag itself, so the ghost follows the pointer until it is let go.
  void escape() {
    if (_dragCount > 0 && !_dragCalledOff) {
      _dragCalledOff = true;
      notifyListeners();
      return;
    }
    cancel();
  }

  /// Select none: every pick out, hidden ones too; still picking. The Shift
  /// anchor goes too, so the next Shift-click picks only its card.
  void selectNone() {
    _anchor = null;
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

  /// Shift-click: adds every card from the anchor (the last card clicked,
  /// or the last a box picked) to [key], in grid order ([order] — group ids
  /// then character keys, as shown). With no anchor on screen it picks only
  /// [key], which becomes the anchor.
  void addRange(
    String key, {
    required bool group,
    required List<String> order,
    required Set<String> groupKeys,
  }) {
    final from = _anchor == null ? -1 : order.indexOf(_anchor!);
    final to = order.indexOf(key);
    if (from < 0 || to < 0) {
      (group ? groupIds : characterIds).add(key);
      _anchor = key;
      if (!picking) _mode = LibraryPickMode.select;
      notifyListeners();
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
  /// touches a card. [anchor] is the box's last card in grid order, or null
  /// when it touched none: a Shift-click ranges from there, not from a card
  /// clicked before the box.
  void replace(Set<String> characters, Set<String> groups, [String? anchor]) {
    characterIds
      ..clear()
      ..addAll(characters);
    groupIds
      ..clear()
      ..addAll(groups);
    _anchor = anchor;
    if (!picking && !isEmpty) _mode = LibraryPickMode.select;
    notifyListeners();
  }

  /// The picks as a drag carries them.
  LibraryDragPayload get payload => LibraryDragPayload(
    characterIds: {...characterIds},
    groupIds: {...groupIds},
  );

  void beginDrag(int count, {required bool picks}) {
    _dragCount = count;
    _dragsPicks = picks;
    _dragCalledOff = false;
    notifyListeners();
  }

  void endDrag() {
    if (_dragCount == 0 && !_dragsPicks && !_dragCalledOff) return;
    _resetDrag();
    notifyListeners();
  }

  void _resetDrag() {
    _dragCount = 0;
    _dragsPicks = false;
    _dragCalledOff = false;
  }

  /// Moves the picks to [folderId] (null: the top level) in one go, then
  /// ends the selection, as the Move to Folder button always has. Returns
  /// how many moved.
  Future<int> moveTo(
    String? folderId, {
    required FolderService folders,
    required List<CharacterCard> library,
  }) async {
    final moved = await _move(
      characterIds,
      groupIds,
      folderId,
      folders,
      library,
    );
    cancel();
    return moved;
  }

  /// A drop on a folder tile or a level of the path. A dragged selection
  /// moves the cards it picked up — the ghost's — not the picks as they are
  /// now, then the selection ends; a single-card drag moves that card. Null
  /// when nothing dropped: Esc called the drag off, or the library cannot
  /// move the data.
  Future<int?> drop(
    Object item,
    String? folderId, {
    required FolderService folders,
    required List<CharacterCard> library,
  }) async {
    final calledOff = _dragCalledOff;
    endDrag();
    if (calledOff) return null;
    switch (item) {
      case LibraryDragPayload(
        characterIds: final carried,
        groupIds: final carriedGroups,
      ):
        final moved = await _move(
          carried,
          carriedGroups,
          folderId,
          folders,
          library,
        );
        cancel();
        return moved;
      case CharacterCard(:final imagePath?):
        return folders.moveMany(
          folderId: folderId,
          characterPaths: [imagePath],
        );
      case GroupChat(:final id):
        return folders.moveMany(folderId: folderId, groupIds: [id]);
      default:
        return null;
    }
  }

  /// One moveMany for [characters] (selection keys) and [groups].
  Future<int> _move(
    Set<String> characters,
    Set<String> groups,
    String? folderId,
    FolderService folders,
    List<CharacterCard> library,
  ) {
    final byKey = <String, CharacterCard>{};
    for (final c in library) {
      byKey.putIfAbsent(c.stableGroupId, () => c);
    }
    return folders.moveMany(
      folderId: folderId,
      characterPaths: [for (final key in characters) ?byKey[key]?.imagePath],
      groupIds: {...groups},
    );
  }
}
