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
import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';

/// Web adapter for image generation: read/flip the backend config (Local A1111 /
/// Draw Things ↔ remote API) and generate an image. Reuses [ImageGenService]
/// (which routes to whichever backend is configured) and the existing settings.
class ImageFacade {
  ImageFacade(this._image, this._storage);

  final ImageGenService _image;
  final StorageService _storage;

  /// Current image-gen config for the web panel. The API key is never returned
  /// (presence only), matching the text-backend settings facade.
  Map<String, dynamic> config() {
    final img = _storage.imageGenSettings;
    final b = _storage.backendSettings;
    return {
      'backend': img.imageGenBackend, // 'remote' | 'a1111' | 'drawthings'
      'isConfigured': _image.isConfigured,
      'isGenerating': _image.isGenerating,
      'statusMessage': _image.statusMessage,
      'size': img.imageGenSize,
      'style': img.imageGenStyle,
      'model': img.imageGenModel,
      'negativePrompt': img.imageGenNegativePrompt,
      'steps': img.imageGenSteps,
      'cfgScale': img.imageGenCfgScale,
      'sampler': img.imageGenSampler,
      'localUrl': img.localImageGenUrl,
      'drawThingsHost': img.drawThingsGrpcHost,
      'drawThingsPort': img.drawThingsGrpcPort,
      // Remote (API) image gen reuses the shared remote backend config.
      'remoteApiUrl': b.remoteApiUrl,
      'remoteModelName': b.remoteModelName,
      'hasApiKey': b.remoteApiKey.isNotEmpty,
    };
  }

  /// Apply any subset of the image-gen config (only present keys change).
  Future<void> updateConfig(Map<String, dynamic> f) async {
    final img = _storage.imageGenSettings;
    final b = _storage.backendSettings;
    if (f['backend'] is String) await img.setImageGenBackend(f['backend'] as String);
    if (f['size'] is String) await img.setImageGenSize(f['size'] as String);
    if (f['style'] is String) await img.setImageGenStyle(f['style'] as String);
    if (f['model'] is String) await img.setImageGenModel(f['model'] as String);
    if (f['negativePrompt'] is String) {
      await img.setImageGenNegativePrompt(f['negativePrompt'] as String);
    }
    if (f['steps'] is int) await img.setImageGenSteps(f['steps'] as int);
    if (f['cfgScale'] is num) {
      await img.setImageGenCfgScale((f['cfgScale'] as num).toDouble());
    }
    if (f['sampler'] is String) await img.setImageGenSampler(f['sampler'] as String);
    if (f['localUrl'] is String) {
      await img.setLocalImageGenUrl(f['localUrl'] as String);
    }
    if (f['drawThingsHost'] is String) {
      await img.setDrawThingsGrpcHost(f['drawThingsHost'] as String);
    }
    if (f['drawThingsPort'] is int) {
      await img.setDrawThingsGrpcPort(f['drawThingsPort'] as int);
    }
    // Remote API config (shared with text backend).
    if (f['remoteApiUrl'] is String) {
      await b.setRemoteApiUrl(f['remoteApiUrl'] as String);
    }
    if (f['remoteModelName'] is String) {
      await b.setRemoteModelName(f['remoteModelName'] as String);
    }
    final apiKey = f['apiKey']?.toString();
    if (apiKey != null && apiKey.isNotEmpty) await b.setRemoteApiKey(apiKey);
  }

  /// Generate an image from [prompt] using the configured backend. Returns the
  /// image as a base64 data URL plus the on-disk save path, or null on failure.
  Future<Map<String, dynamic>?> generate(Map<String, dynamic> f) async {
    final prompt = f['prompt']?.toString().trim() ?? '';
    if (prompt.isEmpty) return null;
    final bytes = await _image.generateImage(
      prompt: prompt,
      negativePrompt: f['negativePrompt']?.toString() ?? '',
      size: f['size']?.toString(),
    );
    if (bytes == null) return null;
    final savedPath = await _image.saveImageToDisk(bytes);
    return {
      'image': 'data:image/png;base64,${base64Encode(bytes)}',
      'savedPath': savedPath,
      // Basename only — the client references this to serve the saved image
      // (GET /api/image/saved/<filename>) and to insert it into a chat.
      'filename': savedPath != null ? p.basename(savedPath) : null,
    };
  }

  /// Resolve a previously-saved generated image by [name] (basename only) for
  /// serving over HTTP. Returns null on a missing file or a path-traversal
  /// attempt. Mirrors [ImageGenService]'s images directory layout.
  File? savedImageFile(String name) {
    if (name.isEmpty ||
        name.contains('/') ||
        name.contains(r'\') ||
        name.contains('..')) {
      return null;
    }
    final root = _storage.rootPath;
    if (root == null || root.isEmpty) return null;
    final file = File(p.join(root, 'KoboldManager', 'images', name));
    return file.existsSync() ? file : null;
  }
}
