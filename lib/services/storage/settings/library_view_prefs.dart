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

import 'settings_base.dart';

const _kScopes = ['currentFolder', 'folderRecursive', 'allCharacters'];
const _kTopScopeDefault = 'allCharacters';
const _kFolderScopeDefault = 'currentFolder';

/// The home library's view choices, remembered on this computer: sort, card
/// size and search scope. A mixin beside [UiSettings] because that file is
/// near the size limit. The scopes are stored as SearchScope names.
mixin LibraryViewPrefs on SettingsBase {
  String _sortMode = 'name'; // 'name', 'recent', 'importDate', 'messages'
  double _gridScale = 300.0; // maxCrossAxisExtent in pixels (150-450)
  String _topSearchScope = _kTopScopeDefault;
  String _folderSearchScope = _kFolderScopeDefault;

  String get sortMode => _sortMode;
  double get gridScale => _gridScale;

  /// Where a search at the top level looks (#346): `allCharacters` is
  /// Everywhere (the default), `currentFolder` is Top level only.
  String get topSearchScope => _topSearchScope;

  /// Where a search inside a folder looks: `currentFolder` (the default),
  /// `folderRecursive` or `allCharacters`. The top level and folders keep
  /// separate choices because they offer different ones.
  String get folderSearchScope => _folderSearchScope;

  static String _scope(String? value, String fallback) =>
      _kScopes.contains(value) ? value! : fallback;

  void loadLibraryViewPrefs() {
    _sortMode = prefs?.getString(k('sort_mode')) ?? 'name';
    _gridScale = prefs?.getDouble(k('grid_scale')) ?? 300.0;
    _topSearchScope = _scope(
      prefs?.getString(k('library_scope_top')),
      _kTopScopeDefault,
    );
    _folderSearchScope = _scope(
      prefs?.getString(k('library_scope_folder')),
      _kFolderScopeDefault,
    );
  }

  Future<void> setSortMode(String value) async {
    _sortMode = value;
    await prefs?.setString(k('sort_mode'), value);
    notify();
  }

  Future<void> setGridScale(double value) async {
    _gridScale = value.clamp(150.0, 450.0);
    await prefs?.setDouble(k('grid_scale'), _gridScale);
    notify();
  }

  Future<void> setTopSearchScope(String value) async {
    _topSearchScope = _scope(value, _kTopScopeDefault);
    await prefs?.setString(k('library_scope_top'), _topSearchScope);
    notify();
  }

  Future<void> setFolderSearchScope(String value) async {
    _folderSearchScope = _scope(value, _kFolderScopeDefault);
    await prefs?.setString(k('library_scope_folder'), _folderSearchScope);
    notify();
  }
}
