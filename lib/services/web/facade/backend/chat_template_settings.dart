// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:front_porch_ai/services/services.dart';

class ChatTemplateSettings {
  ChatTemplateSettings(this._storage);
  final StorageService _storage;
  Future<void> save({
    required String preset,
    String? name,
    String? content,
  }) async {
    if (_storage.backendSettings.activeKcppsPath != preset) {
      throw const FormatException('The selected preset changed. Try again.');
    }
    await saveUploadedKoboldTemplate(
      engineDir: _storage.binDir.path,
      preset: preset,
      name: name,
      content: content,
      stillSelected: () => _storage.backendSettings.activeKcppsPath == preset,
    );
    await _storage.backendSettings.setActiveKcppsPath(preset);
  }
}
