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

import 'dart:convert';

import 'package:front_porch_ai/services/capability/image_reference_role.dart';
import 'package:front_porch_ai/services/storage/settings/remote_api_key_vault.dart';
import 'package:front_porch_ai/services/storage/settings/settings_base.dart';

/// Image Studio–scoped remote host + last image-model-per-host.
///
/// Kept off [BackendSettings.remoteApiUrl] so Studio chips never rewrite
/// chat's mouth. Last-used image ids are a separate map from the chat
/// text-model vault (`remote_api_models`).
mixin ImageGenRemotePrefs on SettingsBase {
  String _imageRemoteApiUrl = '';
  final Map<String, String> _remoteImageModels = {};

  /// Empty until the user picks a Studio host. Fetch/generate then fall
  /// back to chat's URL without writing it here.
  String get imageRemoteApiUrl => _imageRemoteApiUrl;

  /// Last image id for [url]. [edit] uses a `#edit` suffix so a Comfy
  /// checkpoint left in the create slot cannot poison Remote/Nano Edit or
  /// expression-pack resolution (and the reverse).
  String remoteImageModelFor(String url, {bool edit = false}) {
    final slot = _hostModelKey(url, edit: edit);
    if (slot.isEmpty) return '';
    final id = _remoteImageModels[slot] ?? '';
    return looksLikeLocalImageModel(id) ? '' : id;
  }

  void loadImageRemotePrefs() {
    _imageRemoteApiUrl = prefs?.getString(k('image_remote_api_url')) ?? '';
    _remoteImageModels
      ..clear()
      ..addAll(
        _decodeRemoteImageModels(prefs?.getString(k('image_remote_models'))),
      );
  }

  Future<void> setImageRemoteApiUrl(String value) async {
    _imageRemoteApiUrl = normalizeRemoteApiUrl(value);
    await prefs?.setString(k('image_remote_api_url'), _imageRemoteApiUrl);
    notify();
  }

  Future<void> setRemoteImageModelFor(
    String url,
    String modelId, {
    bool edit = false,
  }) async {
    final slot = _hostModelKey(url, edit: edit);
    if (slot.isEmpty) return;
    final id = modelId.trim();
    if (id.isEmpty || looksLikeLocalImageModel(id)) {
      _remoteImageModels.remove(slot);
    } else {
      _remoteImageModels[slot] = id;
    }
    await prefs?.setString(
      k('image_remote_models'),
      jsonEncode(_remoteImageModels),
    );
    notify();
  }

  static String _hostModelKey(String url, {required bool edit}) {
    final slot = normalizeRemoteApiUrl(url);
    if (slot.isEmpty) return '';
    return edit ? '$slot#edit' : slot;
  }

  static Map<String, String> _decodeRemoteImageModels(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return {
        for (final e in decoded.entries)
          if (normalizeRemoteApiUrl(e.key.toString()).isNotEmpty)
            normalizeRemoteApiUrl(e.key.toString()): e.value.toString(),
      };
    } catch (_) {
      return {};
    }
  }
}
