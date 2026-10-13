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

import 'dart:io';

import 'package:path/path.dart' as path;

import 'package:front_porch_ai/services/comfy_ui_service.dart';
import 'package:front_porch_ai/services/grpc/draw_things_grpc_service.dart';
import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/storage_service.dart';

/// Lazy backend clients, the remote account and the images directory, all
/// read from the live settings on each use.
class ImageGenClients {
  ImageGenClients(this._storage);

  final StorageService _storage;

  DrawThingsGrpcService? _drawThingsGrpc;
  ComfyUiService? _comfyUi;

  /// The ComfyUI client made so far, if any — never creates one.
  ComfyUiService? get comfyOrNull => _comfyUi;

  bool get isConfigured {
    if (!_storage.imageGenSettings.imageGenEnabled) return false;
    final backend = ImageGenBackend.fromKey(
      _storage.imageGenSettings.imageGenBackend,
    );
    switch (backend) {
      case ImageGenBackend.remote:
        return remoteAccount.key.isNotEmpty &&
            _storage.imageGenSettings.imageGenModel.isNotEmpty;
      case ImageGenBackend.a1111:
        return _storage.imageGenSettings.localImageGenUrl.isNotEmpty;
      case ImageGenBackend.drawThings:
        return _storage.imageGenSettings.drawThingsGrpcHost.isNotEmpty;
      case ImageGenBackend.comfyUi:
        return _storage.imageGenSettings.comfyUiUrl.isNotEmpty;
    }
  }

  ComfyUiService get comfyUi {
    final url = _storage.imageGenSettings.comfyUiUrl;
    if (_comfyUi == null || _comfyUi!.baseUrl != url) {
      _comfyUi = ComfyUiService(baseUrl: url);
    }
    return _comfyUi!;
  }

  DrawThingsGrpcService get drawThingsGrpc {
    final h = _storage.imageGenSettings.drawThingsGrpcHost;
    final p = _storage.imageGenSettings.drawThingsGrpcPort;
    // Recreate if host/port changed since last use (cheap; keeps things in sync with settings)
    if (_drawThingsGrpc == null ||
        _drawThingsGrpc!.host != h ||
        _drawThingsGrpc!.port != p) {
      _drawThingsGrpc = DrawThingsGrpcService(host: h, port: p);
    }
    return _drawThingsGrpc!;
  }

  /// Studio host + vault key. Empty Studio URL falls back to chat's mouth
  /// without writing it — flipping Studio chips never changes chat.
  ({String url, String key}) get remoteAccount =>
      resolveImageStudioRemoteAccount(
        imageRemoteApiUrl: _storage.imageGenSettings.imageRemoteApiUrl,
        chatRemoteApiUrl: _storage.backendSettings.remoteApiUrl,
        keyFor: _storage.backendSettings.remoteApiKeyFor,
      );

  /// The last image-model list read from the Studio host, so a generate
  /// sends the size the desk showed for that model.
  List<ImageModelInfo> remoteModels = const [];

  ImageModelInfo? remoteModelById(String id) {
    for (final m in remoteModels) {
      if (m.id == id) return m;
    }
    return null;
  }

  Future<void> nudgeComfyFree() async {
    final backend = ImageGenBackend.fromKey(
      _storage.imageGenSettings.imageGenBackend,
    );
    if (backend != ImageGenBackend.comfyUi) return;
    await comfyUi.freeMemory();
  }

  /// Build the images directory path.
  Directory get imagesDir =>
      Directory(path.join(_storage.rootPath ?? '', 'KoboldManager', 'images'));
}
