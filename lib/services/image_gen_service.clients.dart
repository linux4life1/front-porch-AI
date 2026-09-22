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

part of 'image_gen_service.dart';

/// Lazy backend clients and the images directory. [isConfigured] and
/// [nudgeComfyFree] stay shell instance members — protected test fakes
/// override them — and forward here.
extension _ImageGenClients on ImageGenService {
  bool get _isConfiguredImpl {
    if (!_storage.imageGenSettings.imageGenEnabled) return false;
    final backend = ImageGenBackend.fromKey(
      _storage.imageGenSettings.imageGenBackend,
    );
    switch (backend) {
      case ImageGenBackend.remote:
        return _imageRemoteAccount.key.isNotEmpty &&
            _storage.imageGenSettings.imageGenModel.isNotEmpty;
      case ImageGenBackend.a1111:
        return _storage.imageGenSettings.localImageGenUrl.isNotEmpty;
      case ImageGenBackend.drawThings:
        return _storage.imageGenSettings.drawThingsGrpcHost.isNotEmpty;
      case ImageGenBackend.comfyUi:
        return _storage.imageGenSettings.comfyUiUrl.isNotEmpty;
    }
  }

  ComfyUiService get _ensureComfyUi {
    final url = _storage.imageGenSettings.comfyUiUrl;
    if (_comfyUi == null || _comfyUi!.baseUrl != url) {
      _comfyUi = ComfyUiService(baseUrl: url);
    }
    return _comfyUi!;
  }

  DrawThingsGrpcService get _ensureDrawThingsGrpc {
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
  ({String url, String key}) get _imageRemoteAccount =>
      resolveImageStudioRemoteAccount(
        imageRemoteApiUrl: _storage.imageGenSettings.imageRemoteApiUrl,
        chatRemoteApiUrl: _storage.backendSettings.remoteApiUrl,
        keyFor: _storage.backendSettings.remoteApiKeyFor,
      );

  Future<void> _nudgeComfyFreeImpl() async {
    final backend = ImageGenBackend.fromKey(
      _storage.imageGenSettings.imageGenBackend,
    );
    if (backend != ImageGenBackend.comfyUi) return;
    await _ensureComfyUi.freeMemory();
  }

  /// Build the images directory path.
  Directory get _imagesDir =>
      Directory(path.join(_storage.rootPath ?? '', 'KoboldManager', 'images'));
}
