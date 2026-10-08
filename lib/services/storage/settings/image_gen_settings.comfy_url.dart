// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of 'image_gen_settings.dart';

/// ComfyUI's own default address, used until one is given or found.
const String kDefaultComfyUiUrl = 'http://127.0.0.1:8188';

/// Whose ComfyUI address this is: one the person gave, or one Front Porch
/// found by itself (see `redialComfy`).
extension ImageGenSettingsComfyUrl on ImageGenSettings {
  /// True once the person has given an address. Then a ComfyUI found
  /// elsewhere is only offered, never switched to.
  bool get comfyUiUrlExplicit => _comfyUiUrlExplicit;

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
