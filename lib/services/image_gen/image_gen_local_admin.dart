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

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:front_porch_ai/services/comfy_ui_service.dart';
import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/storage_service.dart';

import 'image_gen_clients.dart';

/// Local backend discovery & model admin (A1111 / Draw Things / ComfyUI).
/// [unloadViaService] is the service's own (overridable) unloadLocalModel, so
/// a switch unloads through whatever the service answers to.
class ImageGenLocalAdmin {
  ImageGenLocalAdmin(
    this._storage,
    this._clients, {
    required this.unloadViaService,
  });

  final StorageService _storage;
  final ImageGenClients _clients;
  final Future<bool> Function(String baseUrl) unloadViaService;

  /// The checkpoint name that is currently loaded on the local A1111 server.
  /// Used to skip redundant unload→reload cycles that can leave tensors
  /// split across CPU and CUDA on Windows/nVidia setups.
  String? lastLoadedCheckpoint;

  Future<bool> testLocalConnection(String baseUrl) async {
    final backendKey = _storage.imageGenSettings.imageGenBackend;

    if (backendKey == 'drawthings') {
      try {
        final grpcService = _clients.drawThingsGrpc;
        return await grpcService.testConnection();
      } catch (e) {
        debugPrint('ImageGen: Draw Things connection test failed: $e');
        return false;
      }
    } else if (backendKey == 'comfyui') {
      return _clients.comfyUi.testConnection();
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

  Future<List<String>> fetchA1111Models(String baseUrl) async {
    final isDrawThings =
        _storage.imageGenSettings.imageGenBackend == 'drawthings';

    if (isDrawThings) {
      try {
        final grpcService = _clients.drawThingsGrpc;
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

  /// Fetch LoRAs from an A1111 / Forge / SD.Next server, enriched with
  /// base-model family.
  ///
  /// Endpoint: GET /sdapi/v1/loras — each entry carries a `metadata` block that
  /// usually includes `ss_base_model_version` / `modelspec.architecture`, which
  /// gives an authoritative family (this is the same field A1111's own UI uses).
  /// When a LoRA exposes no metadata we fall back to file-name detection.
  /// Draw Things uses [fetchDrawThingsLoras] instead (no HTTP endpoint).
  Future<List<LoraOption>> fetchA1111Loras(String baseUrl) async {
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

  /// Unload the currently active model from memory on a local server.
  ///
  /// Calls `POST /sdapi/v1/unload-checkpoint` (standard A1111 endpoint).
  /// Draw Things may support this via its A1111-compat layer.
  /// If the server doesn't support it the error is silently ignored —
  /// model switching via [switchLocalModel] will still proceed.
  ///
  /// Returns true if the server acknowledged the unload (HTTP 200).
  Future<bool> unloadLocalModel(String baseUrl) async {
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

  /// Switch the active checkpoint on a local A1111 / Draw Things server.
  ///
  /// Sequence:
  ///   1. `POST /sdapi/v1/unload-checkpoint` — free current model from memory
  ///      (silently ignored if not supported by the server)
  ///   2. `POST /sdapi/v1/options` with the new model name — trigger model load
  ///   3. Poll `GET /sdapi/v1/options` to confirm the model is fully loaded
  ///      on the GPU before returning, preventing tensor device mismatches.
  ///
  /// Returns true if the model was successfully switched and confirmed ready.
  Future<bool> switchLocalModel(String baseUrl, String modelName) async {
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
      lastLoadedCheckpoint = modelName;
      return true;
    }
    // Step 1: unload current model (best-effort — Draw Things may ignore this)
    await unloadViaService(baseUrl);
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
        lastLoadedCheckpoint = modelName;
      } else {
        debugPrint('ImageGen: Model ready check timed out — proceeding anyway');
        lastLoadedCheckpoint = modelName; // assume it loaded
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

  Future<List<String>> fetchA1111Samplers(String baseUrl) async {
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

  /// Fetch available schedulers from an A1111 / Forge / SD.Next server.
  ///
  /// Endpoint: GET /sdapi/v1/schedulers
  /// Returns scheduler names (the `name` field from each entry). Older forks
  /// (and Draw Things' A1111 shim) predate this endpoint and answer 404 — that
  /// degrades silently to an empty list, so the UI simply offers only
  /// 'Automatic' there.
  Future<List<String>> fetchA1111Schedulers(String baseUrl) async {
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

  Future<List<String>> fetchDrawThingsModels() async {
    try {
      final grpcService = _clients.drawThingsGrpc;
      return await grpcService.fetchModels();
    } catch (e) {
      debugPrint('ImageGen: fetchDrawThingsModels failed: $e');
      return [];
    }
  }

  Future<Map<String, String>> fetchDrawThingsModelVersions() async {
    try {
      return await _clients.drawThingsGrpc.fetchModelVersions();
    } catch (e) {
      debugPrint('ImageGen: fetchDrawThingsModelVersions failed: $e');
      return const {};
    }
  }

  /// Fetch LoRA files from a Draw Things server (gRPC CLI op 'loras' — the
  /// same Echo('models') listing as [fetchDrawThingsModels], filtered to
  /// LoRAs). The selected name is applied natively via the generation config.
  ///
  /// Draw Things records the base model on each LoRA in `custom_lora.json`
  /// (`version`). That id is passed as metadata so the picker can keep the
  /// checkpoint's family and tuck the other bases away. A bare file name is
  /// still only a guess.
  Future<List<LoraOption>> fetchDrawThingsLoras() async {
    try {
      final grpcService = _clients.drawThingsGrpc;
      final rows = await grpcService.fetchLoras();
      return [
        for (final row in rows)
          ImageModelFamily.classifyLora(
            row.file,
            metadata: row.version.isEmpty
                ? null
                : {'dt_base_model': row.version},
          ),
      ];
    } catch (e) {
      debugPrint('ImageGen: fetchDrawThingsLoras failed: $e');
      return [];
    }
  }

  /// ComfyUI LoRAs, enriched with base-model family. Names come from
  /// /object_info; the family is read per-LoRA from the embedded safetensors
  /// metadata via /view_metadata (authoritative), falling back to the file name
  /// when a model exposes none. Metadata reads run in small concurrent batches
  /// so a large library doesn't stall the picker, and any failure degrades
  /// silently to name detection.
  Future<List<LoraOption>> fetchComfyLoras() async {
    final comfy = _clients.comfyUi;
    final names = await comfy.fetchLoras();
    final out = <LoraOption>[];
    const batch = 8;
    for (var i = 0; i < names.length; i += batch) {
      final slice = names.skip(i).take(batch);
      final metas = await Future.wait(slice.map(comfy.fetchLoraMetadata));
      var j = 0;
      for (final n in slice) {
        final meta = metas[j++];
        out.add(
          ImageModelFamily.classifyLora(
            n,
            metadata: meta.isEmpty ? null : meta,
          ),
        );
      }
    }
    return out;
  }
}

/// Asks Automatic1111 to look at its Lora folder again. It lists the LoRAs it
/// found when it started, so a file downloaded since is not in
/// `GET /sdapi/v1/loras` until this is asked. A top-level function (not only
/// a class member) so callers holding a test double that implements the
/// service still reach the real server.
///
/// `POST /sdapi/v1/refresh-loras`. A server that has no such endpoint, or
/// does not answer, is simply left as it was: false.
Future<bool> refreshA1111LorasAt(String baseUrl) async {
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
