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

  /// Keeps the active [preset]'s template on its model despite the warning,
  /// and stops asking about that template and model.
  Future<void> accept({required String preset}) async {
    final engineDir = _storage.binDir.path;
    if (_storage.backendSettings.activeKcppsPath != preset) {
      throw const FormatException('The selected preset changed. Try again.');
    }
    final read = (await KcppsLibrary.open(preset)).read;
    final template = read is KcppsOk
        ? kcppsChatTemplateFile(read.raw, engineDir)
        : '';
    final model = resolveKoboldLaunch(_storage).modelPath;
    if (template.isEmpty || model.isEmpty) {
      throw const FormatException('This preset has no template to keep.');
    }
    await acceptKoboldTemplate(
      engineDir: engineDir,
      templatePath: template,
      modelPath: model,
    );
  }
}
