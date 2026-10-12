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

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/image/civitai_bases.dart';

/// The base picker's state. Typing only narrows the menu; the pick is what
/// the field shows when it is left, and it is exactly what a search sends.
/// "Only installed models" hiding the pick drops it, with a note, so turning
/// that off again never brings it back.
///
/// [update] is the owning State's `setState`; [onCleared] drops the results
/// on screen and is only ever called inside a state change.
class CivitaiBaseField {
  CivitaiBaseField({required this.update, required this.onCleared}) {
    text.addListener(_typed);
    focus.addListener(_focusChanged);
    _showLabel();
  }

  final void Function(VoidCallback fn) update;
  final VoidCallback onCleared;

  final TextEditingController text = TextEditingController();
  final FocusNode focus = FocusNode();
  String _base = '';
  String _query = '';
  bool _showsLabel = false;
  String? _note;
  bool _installedOnly = false;

  /// Model files found in the models folder, and whether that look is still
  /// under way. Set by the sheet inside a state change.
  List<String> modelFiles = const [];
  bool scanning = true;

  String get base => _base;
  String get query => _query;
  String? get note => _note;
  bool get installedOnly => _installedOnly;

  Set<String>? get _onlyApis =>
      _installedOnly ? civitaiBasesForFiles(modelFiles) : null;

  /// Any change to the text while it is not showing the pick: typing, the
  /// clear button, select-all and delete, or a clear from code.
  void _typed() {
    if (_showsLabel || text.text == _query) return;
    update(() => _query = text.text);
  }

  void _focusChanged() {
    if (focus.hasFocus) {
      _showsLabel = false;
      text.clear();
    } else {
      _showLabel();
    }
    update(() {});
  }

  void _showLabel() {
    _showsLabel = true;
    _query = '';
    text.text = _base.isEmpty ? 'Any base' : civitaiBaseLabel(_base);
  }

  void pick(String api) {
    update(() {
      if (api != _base) onCleared();
      _base = api;
      _note = null;
    });
    if (focus.hasFocus) {
      focus.unfocus();
    } else {
      _showLabel();
    }
  }

  void setInstalledOnly(bool on) {
    update(() {
      _installedOnly = on;
      _note = null;
      dropHidden();
    });
  }

  /// Call inside a state change. Leaves the pick alone while the models
  /// folder is still being looked through.
  void dropHidden() {
    if (_base.isEmpty || !_installedOnly || scanning) return;
    final shown = filterCivitaiBaseGroups(
      kCivitaiBaseGroups,
      onlyApis: _onlyApis,
    );
    if (civitaiBaseShown(shown, _base)) return;
    _note = "${civitaiBaseLabel(_base)} isn't installed — showing Any base.";
    _base = '';
    onCleared();
    if (!focus.hasFocus) _showLabel();
  }

  void dispose() {
    text.dispose();
    focus.dispose();
  }
}
