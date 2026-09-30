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

/// Cluster E — local backend discovery & model admin. Every public member
/// here is overridden by test doubles that `implement` the service (the desk
/// tests among them), so the shell keeps one-line forwarding stubs and this extension holds the verbatim
/// bodies (renamed with an `Impl` suffix). `_waitForModelReady` was already
/// private and unfaked, so it moves with its original name unchanged.
extension _ImageGenLocalAdmin on ImageGenService {
  Future<bool> _testLocalConnectionImpl(String baseUrl) async {
    final backendKey = _storage.imageGenSettings.imageGenBackend;

    if (backendKey == 'drawthings') {
      try {
        final grpcService = _ensureDrawThingsGrpc;
        return await grpcService.testConnection();
      } catch (e) {
        debugPrint('ImageGen: Draw Things connection test failed: $e');
        return false;
      }
    } else if (backendKey == 'comfyui') {
      return _ensureComfyUi.testConnection();
    } else {
      final client = http.Client();
      try {
        final uri = Uri.parse(
          '${ComfyUiService.ensureHttpScheme(baseUrl)}/sdapi/v1/sd-models',
        );
        final response = await client
            .get(uri)
            .timeout(const Duration(seconds: 5));
        return response.statusCode == 200;
      } catch (_) {
        return false;
      } finally {
        client.close();
      }
    }
  }

  Future<List<String>> _fetchA1111ModelsImpl(String baseUrl) async {
    final isDrawThings =
        _storage.imageGenSettings.imageGenBackend == 'drawthings';

    if (isDrawThings) {
      try {
        final grpcService = _ensureDrawThingsGrpc;
        return await grpcService.fetchModels();
      } catch (e) {
        debugPrint('ImageGen: fetchDrawThingsModels failed: $e');
        return [];
      }
    } else {
      final client = http.Client();
      try {
        final uri = Uri.parse(
          '${ComfyUiService.ensureHttpScheme(baseUrl)}/sdapi/v1/sd-models',
        );
        final response = await client
            .get(uri)
            .timeout(const Duration(seconds: 15));
        if (response.statusCode != 200) return [];
        final list = jsonDecode(response.body) as List<dynamic>;
        return list
            .map((m) => (m as Map<String, dynamic>)['title']?.toString() ?? '')
            .where((s) => s.isNotEmpty)
            .toList();
      } catch (_) {
        return [];
      } finally {
        client.close();
      }
    }
  }

  Future<List<LoraOption>> _fetchA1111LorasImpl(String baseUrl) async {
    final client = http.Client();
    try {
      final uri = Uri.parse(
        '${ComfyUiService.ensureHttpScheme(baseUrl)}/sdapi/v1/loras',
      );
      debugPrint('ImageGen: Fetching LoRAs from $uri');
      final response = await client
          .get(uri)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return [];
      final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
      final out = <LoraOption>[];
      for (final e in data) {
        final m = e as Map<String, dynamic>;
        // Prefer alias if present and non-empty, else use name
        final alias = m['alias']?.toString() ?? '';
        final name = m['name']?.toString() ?? '';
        final display = alias.isNotEmpty ? alias : name;
        if (display.isEmpty) continue;
        final meta = m['metadata'];
        out.add(
          ImageModelFamily.classifyLora(
            display,
            metadata: meta is Map<String, dynamic> ? meta : null,
          ),
        );
      }
      return out;
    } catch (e) {
      debugPrint('ImageGen: fetchA1111Loras failed: $e');
      return [];
    } finally {
      client.close();
    }
  }

  Future<bool> _unloadLocalModelImpl(String baseUrl) async {
    final client = http.Client();
    try {
      final uri = Uri.parse(
        '${ComfyUiService.ensureHttpScheme(baseUrl)}/sdapi/v1/unload-checkpoint',
      );
      debugPrint('ImageGen: Requesting model unload at $uri');
      final response = await client
          .post(uri, headers: {'Content-Type': 'application/json'})
          .timeout(const Duration(seconds: 30));
      final ok = response.statusCode == 200;
      debugPrint(
        'ImageGen: Unload ${ok ? "accepted" : "rejected (${response.statusCode}) — may not be supported"}',
      );
      return ok;
    } catch (e) {
      debugPrint('ImageGen: unloadLocalModel failed (ignored): $e');
      return false;
    } finally {
      client.close();
    }
  }

  Future<bool> _switchLocalModelImpl(String baseUrl, String modelName) async {
    if (modelName.isEmpty) return false;
    final backendKey = _storage.imageGenSettings.imageGenBackend;
    if (backendKey == 'drawthings' || backendKey == 'comfyui') {
      // Draw Things and ComfyUI have no separate switch endpoint — the model
      // is named per-generation (DT config dict / ComfyUI workflow graph).
      // Treat as immediate success so web API / legacy callers and the
      // lastLoaded tracking continue to work without error.
      debugPrint(
        'ImageGen: switchLocalModel: $backendKey backend — recording '
        '$modelName (sent at generate time; no pre-load call)',
      );
      _lastLoadedCheckpoint = modelName;
      return true;
    }
    // Step 1: unload current model (best-effort — Draw Things may ignore this)
    await unloadLocalModel(baseUrl);
    // Step 2: request the new checkpoint
    final client = http.Client();
    try {
      final uri = Uri.parse(
        '${ComfyUiService.ensureHttpScheme(baseUrl)}/sdapi/v1/options',
      );
      debugPrint('ImageGen: Switching checkpoint → $modelName');
      final response = await client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'sd_model_checkpoint': modelName}),
          )
          .timeout(const Duration(seconds: 120)); // model loads can be slow
      final ok = response.statusCode == 200;
      debugPrint(
        'ImageGen: Checkpoint switch ${ok ? "accepted" : "rejected (${response.statusCode})"}',
      );
      if (!ok) return false;

      // Step 3: confirm the model is fully loaded before returning.
      // A1111's /sdapi/v1/options POST returns 200 when the load *starts*,
      // but on Windows/nVidia/CuBLAS the model may still be transferring
      // tensors to CUDA. We poll until the reported checkpoint matches or
      // we exhaust retries.
      final ready = await _waitForModelReady(baseUrl, modelName, client);
      if (ready) {
        _lastLoadedCheckpoint = modelName;
      } else {
        debugPrint('ImageGen: Model ready check timed out — proceeding anyway');
        _lastLoadedCheckpoint = modelName; // assume it loaded
      }
      return true;
    } catch (e) {
      debugPrint('ImageGen: switchLocalModel failed: $e');
      return false;
    } finally {
      client.close();
    }
  }

  /// Poll the A1111 server until the active checkpoint matches [expected].
  ///
  /// This prevents a race condition where `txt2img` fires while the model
  /// is still being moved to the CUDA device, causing the
  /// "Expected all tensors to be on the same device" RuntimeError.
  ///
  /// Polls up to 30 times with a 2-second interval (60 s total).
  Future<bool> _waitForModelReady(
    String baseUrl,
    String expected,
    http.Client client,
  ) async {
    final uri = Uri.parse(
      '${ComfyUiService.ensureHttpScheme(baseUrl)}/sdapi/v1/options',
    );
    const maxAttempts = 30;
    const pollInterval = Duration(seconds: 2);

    for (var i = 0; i < maxAttempts; i++) {
      try {
        final resp = await client.get(uri).timeout(const Duration(seconds: 10));
        if (resp.statusCode == 200) {
          final body = jsonDecode(resp.body) as Map<String, dynamic>;
          final active = body['sd_model_checkpoint']?.toString() ?? '';
          if (active == expected) {
            debugPrint('ImageGen: Model ready confirmed on attempt ${i + 1}');
            return true;
          }
          debugPrint(
            'ImageGen: Waiting for model load… '
            '(active="$active", expected="$expected", attempt ${i + 1}/$maxAttempts)',
          );
        }
      } catch (e) {
        debugPrint('ImageGen: Model ready poll failed (attempt ${i + 1}): $e');
      }
      await Future<void>.delayed(pollInterval);
    }
    return false;
  }

  Future<List<String>> _fetchA1111SamplersImpl(String baseUrl) async {
    final client = http.Client();
    try {
      final uri = Uri.parse(
        '${ComfyUiService.ensureHttpScheme(baseUrl)}/sdapi/v1/samplers',
      );
      final response = await client
          .get(uri)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return [];
      final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
      return data
          .map((e) => (e as Map<String, dynamic>)['name']?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('ImageGen: fetchA1111Samplers failed: $e');
      return [];
    } finally {
      client.close();
    }
  }

  Future<List<String>> _fetchA1111SchedulersImpl(String baseUrl) async {
    final client = http.Client();
    try {
      final uri = Uri.parse(
        '${ComfyUiService.ensureHttpScheme(baseUrl)}/sdapi/v1/schedulers',
      );
      final response = await client
          .get(uri)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return [];
      final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
      return data
          .map((e) => (e as Map<String, dynamic>)['name']?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('ImageGen: fetchA1111Schedulers failed: $e');
      return [];
    } finally {
      client.close();
    }
  }
}

/// Asks Automatic1111 to look at its Lora folder again. It lists the LoRAs it
/// found when it started, so a file downloaded since is not in
/// `GET /sdapi/v1/loras` until this is asked. A public extension (not a class
/// member) so the test doubles that implement the service need no change.
extension A1111LoraRefresh on ImageGenService {
  /// `POST /sdapi/v1/refresh-loras`. A server that has no such endpoint, or
  /// does not answer, is simply left as it was: false.
  Future<bool> refreshA1111Loras(String baseUrl) async {
    final client = http.Client();
    try {
      final uri = Uri.parse(
        '${ComfyUiService.ensureHttpScheme(baseUrl)}/sdapi/v1/refresh-loras',
      );
      final response = await client
          .post(uri)
          .timeout(const Duration(seconds: 15));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('ImageGen: refreshA1111Loras failed (ignored): $e');
      return false;
    } finally {
      client.close();
    }
  }
}
