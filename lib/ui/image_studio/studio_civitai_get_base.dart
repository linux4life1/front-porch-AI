// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of 'studio_civitai_get.dart';

/// The base picker's state. Typing only narrows the menu; the pick is what
/// the field shows when it is left, and it is exactly what a search sends.
/// "Only installed models" hiding the pick drops it, with a note, so turning
/// that off again never brings it back.
extension _CivitaiBaseState on _StudioCivitaiGetState {
  Set<String>? get _onlyApis =>
      _installedOnly ? civitaiBasesForFiles(_modelFiles) : null;

  void _watchBaseField() {
    _baseText.addListener(_baseTyped);
    _baseFocus.addListener(_baseFocusChanged);
    _showBaseLabel();
  }

  /// Any change to the text while it is not showing the pick: typing, the
  /// clear button, select-all and delete, or a clear from code.
  void _baseTyped() {
    if (_baseShowsLabel || _baseText.text == _baseQuery) return;
    _set(() => _baseQuery = _baseText.text);
  }

  void _baseFocusChanged() {
    if (_baseFocus.hasFocus) {
      _baseShowsLabel = false;
      _baseText.clear();
    } else {
      _showBaseLabel();
    }
    _set(() {});
  }

  void _showBaseLabel() {
    _baseShowsLabel = true;
    _baseQuery = '';
    _baseText.text = _base.isEmpty ? 'Any base' : civitaiBaseLabel(_base);
  }

  void _pickBase(String api) {
    _set(() {
      if (api != _base) _clearResults();
      _base = api;
      _baseNote = null;
    });
    if (_baseFocus.hasFocus) {
      _baseFocus.unfocus();
    } else {
      _showBaseLabel();
    }
  }

  void _setInstalledOnly(bool on) {
    _set(() {
      _installedOnly = on;
      _baseNote = null;
      _dropHiddenBase();
    });
  }

  /// Call inside a state change. Leaves the pick alone while the models
  /// folder is still being looked through.
  void _dropHiddenBase() {
    if (_base.isEmpty || !_installedOnly || _scanning) return;
    final shown = filterCivitaiBaseGroups(
      kCivitaiBaseGroups,
      onlyApis: _onlyApis,
    );
    if (civitaiBaseShown(shown, _base)) return;
    _baseNote =
        "${civitaiBaseLabel(_base)} isn't installed — showing Any base.";
    _base = '';
    _clearResults();
    if (!_baseFocus.hasFocus) _showBaseLabel();
  }
}
