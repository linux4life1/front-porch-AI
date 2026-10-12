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

import '../settings_base.dart';

const String kDefaultComfyUiUrl = 'http://127.0.0.1:8188';

/// The ComfyUI server address, and whether the person gave it or it was
/// found on its own.
mixin ComfyUiUrlPrefs on SettingsBase {
  String _comfyUiUrl = kDefaultComfyUiUrl;
  bool _comfyUiUrlExplicit = false;

  String get comfyUiUrl => _comfyUiUrl;

  /// True once the person has given an address. Then a ComfyUI found
  /// elsewhere is only offered, never switched to.
  bool get comfyUiUrlExplicit => _comfyUiUrlExplicit;

  void loadComfyUiUrlPrefs() {
    _comfyUiUrl = prefs?.getString(k('comfy_ui_url')) ?? kDefaultComfyUiUrl;
    _comfyUiUrlExplicit = prefs?.getBool(k('comfy_ui_url_explicit')) ?? false;
  }

  /// An address the person gave (typed on the desk, or saved from the phone):
  /// it always wins over one found on its own. An empty one turns finding the
  /// address on again.
  Future<void> setComfyUiUrl(String value) async {
    final cleared = value.trim().isEmpty;
    _comfyUiUrl = cleared ? kDefaultComfyUiUrl : value;
    _comfyUiUrlExplicit = !cleared;
    await prefs?.setString(k('comfy_ui_url'), _comfyUiUrl);
    await prefs?.setBool(k('comfy_ui_url_explicit'), _comfyUiUrlExplicit);
    notify();
  }

  /// Saves an address that was found, not given. It stays not-given, so a
  /// later find can replace it too.
  Future<void> adoptFoundComfyUiUrl(String url) async {
    _comfyUiUrl = url;
    _comfyUiUrlExplicit = false;
    await prefs?.setString(k('comfy_ui_url'), url);
    await prefs?.setBool(k('comfy_ui_url_explicit'), false);
    notify();
  }
}
