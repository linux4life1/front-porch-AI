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

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:front_porch_ai/services/capability/model_capabilities.dart';
import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/utils/gguf_vision.dart';

/// Resolves ONE cached vision verdict per backend+model identity, mirroring the
/// tool-calling capability probe pattern (resolve with the best signal
/// available, cache only definitive verdicts, degrade every failure to
/// "unknown" rather than a false "none").
///
/// Resolution priority:
///  - Local GGUF (KoboldCpp, incl. .kcpps preset): parse the file — embedded
///    projector, or multimodal-arch + configured mmproj.
///  - OpenRouter: `architecture.input_modalities` from `/models`.
///  - Nano-GPT: `capabilities.vision` from `/models?detailed=true`.
///  - LM Studio: `type == "vlm"` / `capabilities` from `/api/v0/models`.
///  - oMLX: `engine_type == "vlm"` from `/v1/models/status`.
///    (Both extension endpoints are tried opportunistically on every
///    non-metadata host; other servers 404 them in milliseconds and fall
///    through.)
///  - Generic OpenAI-compatible / unknown: a runtime image probe.
///
/// A process-wide singleton so a verdict computed in Settings is reused
/// everywhere without re-reading the file or re-hitting the network.
class VisionSupportResolver {
  VisionSupportResolver._();
  static final VisionSupportResolver instance = VisionSupportResolver._();

  /// Seam for tests to substitute a mock HTTP client; production code always
  /// uses real clients created per request.
  @visibleForTesting
  http.Client Function() httpClientFactory = http.Client.new;

  final Map<String, VisionSupport> _remoteCache = {};
  final Map<String, GgufVisionInfo?> _ggufCache = {};

  /// Raw provider metadata per '$apiUrl::$modelName' — ONE fetch serves both
  /// the vision verdict and the tool-calling short-circuit. Misses are cached
  /// too (null): the fallback runtime probes are the right degraded path
  /// either way, and [clear] forgets a transient failure.
  final Map<String, ModelApiCapabilities?> _capsCache = {};

  /// 64×64 solid-gray PNG used by the runtime probe. Deliberately NOT a 1×1:
  /// several vision preprocessors enforce a minimum image size (Qwen2-VL
  /// rejects anything under its 28-px patch factor, SigLIP-based stacks have
  /// similar floors), so a degenerate probe image made genuinely
  /// vision-capable local models error out and get branded "no vision".
  static const String _probePngB64 =
      'iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAAAAACPAi4CAAAAKUlEQVR42u3MQREA'
      'AAwCIFtb3xD77SAA6VEEAoFAIBAIBAKBQCAQfA8Gmt9wakTxR5IAAAAASUVORK5CYII=';

  /// Clear all cached verdicts (e.g. after the user swaps models/backends).
  void clear() {
    _remoteCache.clear();
    _ggufCache.clear();
    _capsCache.clear();
  }

  /// Raw `/models` capabilities (vision + tool calling) for a remote model,
  /// fetched once and cached. Answers ONLY for capability-metadata providers
  /// (OpenRouter / Nano-GPT) — any other host returns null immediately, so
  /// callers fall back to their runtime probes without a wasted request.
  Future<ModelApiCapabilities?> capabilitiesForRemote({
    required String apiUrl,
    required String apiKey,
    required String modelName,
  }) async {
    if (apiUrl.isEmpty || modelName.isEmpty) return null;
    if (!isCapabilityMetadataProviderUrl(apiUrl)) return null;
    final key = '$apiUrl::$modelName';
    if (_capsCache.containsKey(key)) return _capsCache[key];
    final isNanoGpt = isNanoGptUrl(apiUrl);
    final base = apiUrl.endsWith('/')
        ? apiUrl.substring(0, apiUrl.length - 1)
        : apiUrl;
    final entry = await _fetchModelEntry(
      uri: Uri.parse(isNanoGpt ? '$base/models?detailed=true' : '$base/models'),
      apiKey: apiKey,
      modelName: modelName,
    );
    final caps = entry == null
        ? null
        : (isNanoGpt
              ? ModelApiCapabilities.fromNanoGptEntry(entry)
              : ModelApiCapabilities.fromOpenRouterEntry(entry));
    _capsCache[key] = caps;
    return caps;
  }

  /// Parse (and cache) the vision facts for a local GGUF model file.
  /// Returns null when the file can't be read/parsed.
  Future<GgufVisionInfo?> resolveLocalGgufInfo(String modelPath) async {
    if (_ggufCache.containsKey(modelPath)) return _ggufCache[modelPath];
    GgufVisionInfo? info;
    try {
      info = await GgufVisionParser.getVisionInfo(modelPath);
    } catch (_) {
      info = null;
    }
    _ggufCache[modelPath] = info;
    return info;
  }

  /// Resolve vision for an OpenAI-compatible remote backend, choosing the best
  /// signal for the provider inferred from [apiUrl].
  ///
  /// Only definitive verdicts are cached. Anything that says nothing about
  /// vision — server unreachable, probe timeout while the model is still
  /// loading, an error mentioning neither images nor vision — resolves to
  /// [VisionSupport.unknown] and is retried on the next ask; caching those
  /// used to brand vision models "none" for the rest of the session.
  Future<VisionSupport> resolveRemote({
    required String apiUrl,
    required String apiKey,
    required String modelName,
  }) async {
    if (modelName.isEmpty || apiUrl.isEmpty) return VisionSupport.none;
    final key = '$apiUrl::$modelName';
    final cached = _remoteCache[key];
    if (cached != null) return cached;

    // Metadata path for the two providers whose /models describe capabilities
    // (capabilitiesForRemote returns null immediately for every other host,
    // and caches so the tool-calling short-circuit shares this one fetch).
    final caps = await capabilitiesForRemote(
      apiUrl: apiUrl,
      apiKey: apiKey,
      modelName: modelName,
    );
    if (caps != null) {
      final verdict = VisionSupport.fromApi(caps);
      _remoteCache[key] = verdict;
      return verdict;
    }

    // Local-server extension endpoints, tried opportunistically before the
    // probe — free, instant, and correct even while the model is NOT loaded
    // (the probe can't be either of those). Servers without the extension
    // 404 it in milliseconds and fall through.
    if (!isCapabilityMetadataProviderUrl(apiUrl)) {
      // LM Studio: /api/v0/models, `type: "vlm"` is exactly how LM Studio
      // decides to show its own eye icon. Only trusted when the entry
      // actually carries the discriminating field.
      final lmUri = originEndpointUri(apiUrl, 'api/v0/models');
      if (lmUri != null) {
        final entry = await _fetchModelEntry(
          uri: lmUri,
          apiKey: apiKey,
          modelName: modelName,
          timeout: const Duration(seconds: 6),
        );
        if (entry != null &&
            (entry['type'] != null || entry['capabilities'] != null)) {
          final verdict = VisionSupport.fromApi(
            ModelApiCapabilities.fromLmStudioEntry(entry),
          );
          _remoteCache[key] = verdict;
          return verdict;
        }
      }

      // oMLX: /v1/models/status, `engine_type: "vlm"`. Load-bearing here:
      // oMLX can return HTTP 200 while silently DROPPING images (observed
      // upstream), so a probe "yes" is untrustworthy — the server's own
      // engine type is the only signal that says whether pixels will
      // actually be processed. Tri-state: an entry without a type signal
      // falls through to the probe instead of concluding anything.
      final omlxUri = originEndpointUri(apiUrl, 'v1/models/status');
      if (omlxUri != null) {
        final entry = await _fetchModelEntry(
          uri: omlxUri,
          apiKey: apiKey,
          modelName: modelName,
          timeout: const Duration(seconds: 6),
        );
        final omlxCaps = entry == null
            ? null
            : omlxCapabilitiesFromStatusEntry(entry);
        if (omlxCaps != null) {
          final verdict = VisionSupport.fromApi(omlxCaps);
          _remoteCache[key] = verdict;
          return verdict;
        }
      }
    }

    // Generic OpenAI-compatible / unknown, or a metadata miss above.
    final probed = await _probeVision(
      apiUrl: apiUrl,
      apiKey: apiKey,
      modelName: modelName,
    );
    if (probed == null) return VisionSupport.unknown; // no verdict — no cache
    final verdict = probed
        ? const VisionSupport(true, VisionSource.probe)
        : VisionSupport.none;
    _remoteCache[key] = verdict;
    return verdict;
  }

  /// Vision verdict for the ACTIVE text LLM as configured right now — "can
  /// the current chat model see images?".
  ///
  /// The local Kobold backend (native or a .kcpps preset) is judged from the
  /// GGUF that would actually load: the active .kcpps preset's model when the preset
  /// owns one (mirroring the launch priority in settings_page /
  /// ensureManagedBackendIsRunning), else the last picker-chosen model.
  /// Vision needs an embedded projector, or multimodal arch plus an mmproj
  /// that exists on disk — from the app's per-model mapping OR the preset's
  /// own `mmproj` key. Remaining gap: a server started entirely outside the
  /// app can't be interrogated, so the verdict is "none" — and KoboldCpp
  /// silently ignores images when no projector is loaded rather than
  /// erroring, so a false negative there degrades gracefully.
  /// Remote backends (openRouter / omlx) reuse [resolveRemote] (provider
  /// metadata where available, else the cached image probe); oMLX rides
  /// OpenRouterService at its fixed local URL (see LLMProvider).
  ///
  /// Known residual: the local verdict is read from the CONFIGURED model
  /// (active preset / last picker model), not from whatever a running server
  /// was actually launched with. If the user changes vision config
  /// mid-session WITHOUT restarting the backend, this can be a false positive
  /// (config says vision, server is still the old text model) — pixels are
  /// sent (KoboldCpp ignores them) and the offline caption fallback is
  /// skipped. LLMProvider clears this resolver's cache on any model-identity
  /// change so the verdict at least re-derives from current config; fully
  /// reconciling config with the live server would require server-state
  /// tracking the app does not yet have. The normal flow (change model, then
  /// restart the backend) is unaffected.
  Future<VisionSupport> resolveForActiveLlm({
    required BackendType backend,
    required StorageService storage,
  }) async {
    switch (backend) {
      case BackendType.kobold:
        // Launch semantics: when the active preset carries a model that
        // exists, KoboldCpp loads THAT model (--config wins; the picker
        // model only rides along when the preset has none).
        final presetModel = storage.kcppsModelPath;
        final presetOwnsModel =
            presetModel != null && File(presetModel).existsSync();
        final modelPath = presetOwnsModel
            ? presetModel
            : (storage.lastUsedModelPath ?? '');
        if (modelPath.isEmpty || !File(modelPath).existsSync()) {
          return VisionSupport.none;
        }
        final info = await resolveLocalGgufInfo(modelPath);
        final mmproj = storage.mmprojForModel(modelPath);
        final presetMmproj = presetOwnsModel ? storage.kcppsMmprojPath : null;
        return VisionSupport.fromGguf(
          info,
          mmprojConfigured:
              (mmproj != null &&
                  mmproj.isNotEmpty &&
                  File(mmproj).existsSync()) ||
              (presetMmproj != null && File(presetMmproj).existsSync()),
        );
      case BackendType.openRouter:
        return resolveRemote(
          apiUrl: storage.remoteApiUrl,
          apiKey: storage.remoteApiKey,
          modelName: storage.remoteModelName,
        );
      case BackendType.omlx:
        return resolveRemote(
          apiUrl: 'http://localhost:8000/v1',
          apiKey: storage.remoteApiKey,
          modelName: storage.remoteModelName,
        );
    }
  }

  /// Fetch a models listing from [uri] and return the RAW entry matching
  /// [modelName] (parsing is the caller's job — providers differ). One
  /// implementation serves OpenRouter, Nano-GPT, LM Studio, and oMLX.
  /// Tolerates every listing shape seen in the wild: `{data: [...]}` (OpenAI
  /// convention), `{models: [...]}`, a bare top-level list, or a map keyed by
  /// model id. Returns null when the entry can't be found or the request
  /// fails.
  Future<Map<dynamic, dynamic>?> _fetchModelEntry({
    required Uri uri,
    required String apiKey,
    required String modelName,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final client = httpClientFactory();
    try {
      final response = await client
          .get(
            uri,
            headers: {if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey'},
          )
          .timeout(timeout);
      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body);
      final List<dynamic> entries;
      if (body is List) {
        entries = body;
      } else if (body is Map) {
        final keyed = body[modelName];
        if (keyed is Map) return keyed;
        final data = body['data'];
        final models = body['models'];
        entries = data is List ? data : (models is List ? models : const []);
      } else {
        return null;
      }
      for (final entry in entries) {
        if (entry is! Map) continue;
        final id =
            (entry['id'] ?? entry['name'] ?? entry['model'])?.toString() ?? '';
        if (id != modelName) continue;
        return entry;
      }
      return null;
    } catch (e) {
      debugPrint('[VisionResolver] metadata fetch failed ($uri): $e');
      return null;
    } finally {
      client.close();
    }
  }

  /// Send a small test image via `/chat/completions` and treat a non-error
  /// response as acceptance. Only 200 (yes) or a 4xx whose body names
  /// images/vision (no) are verdicts. EVERYTHING else returns null — server
  /// unreachable, timeout (local servers JIT-load the model on first request,
  /// which can take minutes for a 12B), 404 model-id mismatch, "no model
  /// loaded", 5xx engine hiccups. Those are connectivity/state facts, not
  /// capability facts, and treating them as "no vision" is exactly what made
  /// vision models show "Vision: none".
  Future<bool?> _probeVision({
    required String apiUrl,
    required String apiKey,
    required String modelName,
  }) async {
    final client = httpClientFactory();
    try {
      final base = apiUrl.endsWith('/')
          ? apiUrl.substring(0, apiUrl.length - 1)
          : apiUrl;
      final uri = Uri.parse('$base/chat/completions');
      final payload = {
        'model': modelName,
        'max_tokens': 1,
        'stream': false,
        'messages': [
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': 'ok'},
              {
                'type': 'image_url',
                'image_url': {'url': 'data:image/png;base64,$_probePngB64'},
              },
            ],
          },
        ],
      };
      final response = await client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
            },
            body: jsonEncode(payload),
          )
          // Generous on purpose: a local server may be JIT-loading the model
          // off disk before it can answer the very first request.
          .timeout(const Duration(seconds: 75));

      if (response.statusCode == 200) return true;
      // A 4xx that names images/vision/modality means the model rejected the
      // image specifically → definitively no vision.
      if (response.statusCode >= 400 && response.statusCode < 500) {
        final lower = response.body.toLowerCase();
        if (lower.contains('image') ||
            lower.contains('vision') ||
            lower.contains('modality') ||
            lower.contains('multimodal')) {
          return false;
        }
      }
      debugPrint(
        '[VisionResolver] probe inconclusive '
        '(${response.statusCode}): ${response.body}',
      );
      return null;
    } catch (e) {
      debugPrint('[VisionResolver] probe unreachable/failed: $e');
      return null;
    } finally {
      client.close();
    }
  }
}
