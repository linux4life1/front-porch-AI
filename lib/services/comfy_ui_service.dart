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

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'comfy_ui/comfy_ui.dart';
import 'comfy_workflow.dart';
import 'image/image.dart';

export 'image/comfy_run_ledger.dart' show ComfyRunCancelled;

/// ComfyUI backend client (plain HTTP — no sidecar). The novice contract:
/// ComfyUI runs on http://127.0.0.1:8188 out of the box, everything the UI
/// needs (models, LoRAs, samplers) is discovered via GET /object_info, and
/// generation submits a bundled txt2img workflow graph with the app's
/// prompt/model/LoRA/sampler slotted in — the user never sees a node graph.
/// The same graph shape covers SD1.5 and SDXL checkpoints (only the latent
/// size differs, and that comes from the configured size).
class ComfyUiService {
  ComfyUiService({required this.baseUrl});

  /// e.g. `http://127.0.0.1:8188` (trailing slash tolerated; a missing
  /// scheme is assumed to be http — novices type `localhost:8188`).
  final String baseUrl;

  String get _root => ensureHttpScheme(baseUrl);

  final ComfyRunLedger _runs = ComfyRunLedger();

  late final ComfyCatalogReader _catalog = ComfyCatalogReader(_root);

  /// Stops what this client has running on the server: a queued prompt is
  /// taken off the queue, a running one is interrupted. The waiting call then
  /// throws [ComfyRunCancelled]. [beforePost]: a generation is under way that
  /// has not posted its workflow yet.
  Future<void> cancelRun({bool beforePost = false}) =>
      _runs.cancel(_root, beforePost: beforePost);

  /// A new generation begins: an earlier cancel does not reach it.
  void clearCancel() => _runs.clearStop();

  /// Whether a cancel is waiting for the next post; for tests.
  bool get cancelIsPending => _runs.stopIsPending;

  /// Normalize a user-typed server address into a usable base URL: trims,
  /// strips trailing slashes, and prepends `http://` when no scheme is given
  /// (`localhost:8188`, `192.168.1.20:7860` → valid URLs instead of a silent
  /// connection failure). Shared by the A1111 paths in ImageGenService. Pure.
  static String ensureHttpScheme(String url) => normalizeImageServerUrl(url);

  /// Normalize a (possibly A1111-style) sampler name to one this ComfyUI
  /// server actually offers. Pure — unit-tested. Preference order: already
  /// valid → known alias → 'euler' → first available.
  static String normalizeSampler(String stored, List<String> available) =>
      normalizeComfySampler(stored, available);

  /// A "Karras"-flavored A1111 sampler name maps to the karras scheduler in
  /// ComfyUI (the sampler and schedule are separate knobs there). Pure.
  static String schedulerFor(String storedSampler) =>
      comfySchedulerFor(storedSampler);

  /// Upload an image to ComfyUI's input folder (POST /upload/image, multipart)
  /// so a LoadImage node can reference it by name — the prerequisite for
  /// img2img. Returns the server-side filename (prefixed with its subfolder
  /// when ComfyUI stored it in one). Throws with a readable message on failure.
  Future<String> uploadImage(Uint8List bytes) async {
    final req = http.MultipartRequest('POST', Uri.parse('$_root/upload/image'))
      ..fields['overwrite'] = 'true'
      ..files.add(
        http.MultipartFile.fromBytes(
          'image',
          bytes,
          filename: 'fpai_ref_${DateTime.now().microsecondsSinceEpoch}.png',
        ),
      );
    final streamed = await req.send().timeout(const Duration(seconds: 30));
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode != 200) {
      throw Exception(
        'ComfyUI rejected the reference image (HTTP ${resp.statusCode})',
      );
    }
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    final name = body['name']?.toString() ?? '';
    final subfolder = body['subfolder']?.toString() ?? '';
    if (name.isEmpty) {
      throw Exception('ComfyUI upload returned no filename');
    }
    return subfolder.isEmpty ? name : '$subfolder/$name';
  }

  /// Extract the option list for one node input from a GET /object_info
  /// payload, e.g. node 'CheckpointLoaderSimple' input 'ckpt_name'. ComfyUI
  /// encodes enum inputs as `[ [options...], {meta} ]`. Pure — unit-tested.
  static List<String> optionsFromObjectInfo(
    Map<String, dynamic> objectInfo,
    String nodeType,
    String inputName,
  ) => comfyOptionsFromObjectInfo(objectInfo, nodeType, inputName);

  /// True when the server answers GET /system_stats.
  Future<bool> testConnection() async {
    try {
      final r = await http
          .get(Uri.parse('$_root/system_stats'))
          .timeout(const Duration(seconds: 5));
      return r.statusCode == 200;
    } catch (e) {
      debugPrint('ComfyUI: testConnection failed: $e');
      return false;
    }
  }

  /// Best-effort memory nudge (POST /free): ask the server to drop its loaded
  /// models before a model swap — e.g. the creator pack's create→edit switch,
  /// so the edit workflow doesn't fight the txt2img checkpoint for VRAM.
  /// Fire-and-forget: failure just means the swap costs a little more time.
  Future<void> freeMemory() async {
    try {
      await http
          .post(
            Uri.parse('$_root/free'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'unload_models': true, 'free_memory': true}),
          )
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('ComfyUI: freeMemory nudge failed (ignored): $e');
    }
  }

  Future<List<String>> fetchLoras() async {
    final info = await _catalog.objectInfo(fresh: true);
    if (info == null) return const [];
    return optionsFromObjectInfo(info, 'LoraLoader', 'lora_name');
  }

  /// Read a LoRA's embedded safetensors metadata via ComfyUI's core
  /// `/view_metadata/loras?filename=…` endpoint. Used to detect the LoRA's base
  /// model (`ss_base_model_version` / `modelspec.architecture`). Returns an empty
  /// map on any error or when the server/model exposes no metadata — callers
  /// fall back to file-name detection, so this is strictly best-effort.
  Future<Map<String, dynamic>> fetchLoraMetadata(String filename) async {
    try {
      final uri = Uri.parse('$_root/view_metadata/loras')
          .replace(queryParameters: {'filename': filename});
      final r = await http.get(uri).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200 || r.body.isEmpty) return const {};
      final decoded = jsonDecode(r.body);
      return decoded is Map<String, dynamic> ? decoded : const {};
    } catch (e) {
      debugPrint('ComfyUI: fetchLoraMetadata($filename) failed: $e');
      return const {};
    }
  }

  Future<List<String>> fetchSamplers() async {
    final info = await _catalog.objectInfo();
    if (info == null) return const [];
    return optionsFromObjectInfo(info, 'KSampler', 'sampler_name');
  }

  /// The schedule (noise sigma curve) options ComfyUI's KSampler exposes —
  /// karras / exponential / sgm_uniform / normal / etc. Read from the same
  /// /object_info payload as the samplers. Empty on any error.
  Future<List<String>> fetchSchedulers() async {
    final info = await _catalog.objectInfo();
    if (info == null) return const [];
    return optionsFromObjectInfo(info, 'KSampler', 'scheduler');
  }

  Future<List<String>> fetchModels() => _catalog.fetchModels();

  /// Raw `/object_info`, or null when this ComfyUI cannot be read. Always a
  /// new read, so a Ready line never rests on a list from before a download.
  Future<Map<String, dynamic>?> fetchObjectInfo() =>
      _catalog.objectInfo(fresh: true);

  /// The node list a generate converts and posts with. A read from the last
  /// two minutes is reused; a fresh [fetchObjectInfo] refreshes it.
  Future<Map<String, dynamic>?> objectInfoForRun() => _catalog.objectInfo();

  Future<ComfyFileCatalog> fetchCatalog() => _catalog.fetchCatalog();

  /// [fetchCatalog], or null when the server did not answer (an empty
  /// catalog is a server that answered with nothing installed).
  Future<ComfyFileCatalog?> fetchCatalogIfUp() => _catalog.fetchCatalogIfUp();

  /// The model files this ComfyUI offers for a loader slot.
  Future<List<String>> fetchModelFilesFor(
    String loaderClass,
    String inputName,
  ) => _catalog.fetchModelFilesFor(loaderClass, inputName);

  /// Default frontend templates (ZIT / Qwen / Flux / …) when this Comfy
  /// install serves `/templates/index.json`. Empty if the API isn't there.
  Future<List<ComfyTemplateEntry>> fetchCreateTemplates() =>
      _catalog.fetchCreateTemplates();

  Future<List<ComfyTemplateEntry>> fetchEditTemplates() =>
      _catalog.fetchEditTemplates();

  /// Saved Desktop workflows (`user/default/workflows`). Empty on 404.
  Future<List<ComfyTemplateEntry>> fetchUserWorkflows() =>
      _catalog.fetchUserWorkflows();

  /// UI or API JSON from the selected template source.
  Future<Map<String, dynamic>?> fetchTemplateJson(
    String name, {
    bool preferUserdata = false,
  }) => _catalog.fetchTemplateJson(name, preferUserdata: preferUserdata);

  /// The live graph behind a Create or Edit workflow pick: a saved Desktop
  /// workflow, one of Comfy's own templates, or a bundled family's template.
  /// Null when the pick has none (a bundled preset without a template, an
  /// uploaded graph) or this ComfyUI cannot serve it. Generate and the Ready
  /// line both read it here, so they judge the same graph.
  Future<Map<String, dynamic>?> fetchWorkflowTemplate(String workflowId) =>
      _catalog.fetchWorkflowTemplate(workflowId);

  /// Generate one image: submit the workflow, poll /history until the prompt
  /// finishes, then download the first output image via /view. Throws with a
  /// readable message on failure (the ImageGenService dispatcher sanitizes).
  ///
  /// [onProgress] receives sampling progress (0..1) and, when the ComfyUI
  /// server has previews enabled, the latest in-progress preview frame —
  /// streamed over ComfyUI's WebSocket. The WebSocket is best-effort: if it
  /// can't connect, generation still completes via /history polling.
  Future<Uint8List> generateImage({
    required String prompt,
    String negativePrompt = '',
    String model = '',
    int width = 1024,
    int height = 1024,
    int steps = 20,
    double cfgScale = 7.0,
    int seed = -1,
    String samplerName = 'euler',
    String scheduler = 'normal',
    String loraName = '',
    double loraWeight = 0.8,
    Uint8List? referenceImageBytes,
    double denoise = 0.5,
    void Function(double? progress, Uint8List? preview)? onProgress,
  }) async {
    if (model.isEmpty) {
      // ComfyUI has no "current model" concept like A1111 — the graph must
      // name a checkpoint. Surface that instead of a cryptic node error.
      throw Exception('Select a checkpoint model for ComfyUI first.');
    }
    final effectiveSeed = seed == -1 ? Random().nextInt(1 << 31) : seed;
    // img2img when a reference image is supplied: upload it first so a
    // LoadImage node can name it, then feed the encoded latent to the sampler.
    final hasRef =
        referenceImageBytes != null && referenceImageBytes.isNotEmpty;
    final workflow = hasRef
        ? ComfyWorkflow.buildImg2ImgWorkflow(
            model: model,
            prompt: prompt,
            negativePrompt: negativePrompt,
            steps: steps,
            cfgScale: cfgScale,
            seed: effectiveSeed,
            samplerName: samplerName,
            scheduler: scheduler,
            loraName: loraName,
            loraWeight: loraWeight,
            initImageName: await uploadImage(referenceImageBytes),
            denoise: denoise,
          )
        : ComfyWorkflow.buildTxt2ImgWorkflow(
            model: model,
            prompt: prompt,
            negativePrompt: negativePrompt,
            width: width,
            height: height,
            steps: steps,
            cfgScale: cfgScale,
            seed: effectiveSeed,
            samplerName: samplerName,
            scheduler: scheduler,
            loraName: loraName,
            loraWeight: loraWeight,
          );

    return _runWorkflow(workflow, onProgress);
  }

  /// Submit an already-built API-format graph (Create families / BYO).
  Future<Uint8List> runPromptGraph(
    Map<String, dynamic> workflow, {
    void Function(double? progress, Uint8List? preview)? onProgress,
    String primaryFile = '',
    bool uploaded = false,
  }) async {
    final posted = await _catalog.graphReadyToPost(
      workflow: workflow,
      primaryFile: primaryFile,
      uploaded: uploaded,
    );
    // Only a graph that loads the Qwen-Image 2.1 GGUF pair is checked; any
    // other model posts without the loader ever being looked at.
    await City96Gate.instance.ensureOrThrow(comfyUrl: _root, graph: posted);
    return _runWorkflow(posted, onProgress);
  }

  /// Run an EDIT: upload the reference image, splice it (as `%IMAGE%`) plus the
  /// caller's [tokenValues] into the token-placeholdered [workflowTemplate] (a
  /// bundled preset OR an uploaded graph — same machinery), then run it through
  /// the exact same submit/poll/download as [generateImage]. Throws with a
  /// readable message if any placeholder is still unfilled (e.g. a model slot).
  Future<Uint8List> generateImageEdit({
    required Uint8List referenceImageBytes,
    required Map<String, dynamic> workflowTemplate,
    required Map<String, Object?> tokenValues,
    void Function(double? progress, Uint8List? preview)? onProgress,
    String primaryFile = '',
    bool uploaded = false,
  }) async {
    final imageName = await uploadImage(referenceImageBytes);
    final graph = substituteComfyWorkflow(workflowTemplate, {
      ...tokenValues,
      ComfyEditTokens.image: imageName,
    });
    final leftover = unresolvedComfyTokens(graph);
    if (leftover.isNotEmpty) {
      throw Exception(
        'This edit workflow still has unfilled placeholders '
        '(${leftover.join(', ')}). Pick a model for each slot, or fix the '
        'uploaded workflow.',
      );
    }
    return runPromptGraph(
      graph,
      onProgress: onProgress,
      primaryFile: primaryFile,
      uploaded: uploaded,
    );
  }

  /// Submit [workflow], stream best-effort progress over ComfyUI's WebSocket,
  /// poll /history until it finishes, then download the first output image via
  /// /view. Shared by [generateImage] (txt2img/img2img) and [generateImageEdit].
  Future<Uint8List> _runWorkflow(
    Map<String, dynamic> workflow,
    void Function(double? progress, Uint8List? preview)? onProgress,
  ) async {
    final clientId =
        'frontporch-${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';
    _runs.submitting();
    http.Response submit;
    try {
      submit = await http
          .post(
            Uri.parse('$_root/prompt'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'prompt': workflow, 'client_id': clientId}),
          )
          .timeout(const Duration(seconds: 30));
    } catch (_) {
      await _runs.submitted(_root, null);
      rethrow;
    }
    if (submit.statusCode != 200) {
      await _runs.submitted(_root, null);
      final refused = parseComfySubmitFailure(_root, submit.body);
      throw Exception(
        refused?.banner ??
            'ComfyUI at $_root rejected the workflow '
                '(HTTP ${submit.statusCode}).',
      );
    }
    final promptId = (jsonDecode(
      submit.body,
    ) as Map<String, dynamic>)['prompt_id']?.toString();
    if (promptId == null || promptId.isEmpty) {
      await _runs.submitted(_root, null);
      throw Exception('ComfyUI did not return a prompt_id');
    }
    await _runs.submitted(_root, promptId);

    final ws = onProgress == null
        ? null
        : await openComfyProgress(_root, clientId, onProgress);

    // Poll history until this prompt completes (generation can be slow on
    // first model load; 10 min cap mirrors the other local backends). The
    // WebSocket above is decorative only — completion truth stays here.
    final deadline = DateTime.now().add(const Duration(minutes: 10));
    Map<String, dynamic>? outputs;
    try {
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(seconds: 1));
        if (_runs.isCancelled(promptId)) throw const ComfyRunCancelled();
        try {
          final h = await http
              .get(Uri.parse('$_root/history/$promptId'))
              .timeout(const Duration(seconds: 10));
          if (h.statusCode != 200) continue;
          final hist = jsonDecode(h.body) as Map<String, dynamic>;
          final entry = hist[promptId];
          if (entry is! Map) continue;
          final status = entry['status'];
          if (status is Map && status['status_str'] == 'error') {
            throw Exception(comfyHistoryFailureMessage(_root, status));
          }
          final out = entry['outputs'];
          if (out is Map && out.isNotEmpty) {
            outputs = Map<String, dynamic>.from(out);
            break;
          }
        } on TimeoutException {
          // transient — keep polling until the deadline
        }
      }
    } finally {
      _runs.finished(promptId);
      unawaited(ws?.close());
    }
    if (outputs == null) {
      throw Exception('ComfyUI generation timed out');
    }

    // First image from any output node (ours is 'save').
    for (final nodeOut in outputs.values) {
      final images = (nodeOut is Map) ? nodeOut['images'] : null;
      if (images is List && images.isNotEmpty && images.first is Map) {
        final img = images.first as Map;
        final uri = Uri.parse('$_root/view').replace(
          queryParameters: {
            'filename': img['filename']?.toString() ?? '',
            'subfolder': img['subfolder']?.toString() ?? '',
            'type': img['type']?.toString() ?? 'output',
          },
        );
        final r = await http.get(uri).timeout(const Duration(seconds: 60));
        if (r.statusCode == 200 && r.bodyBytes.isNotEmpty) {
          return r.bodyBytes;
        }
        throw Exception(
          'ComfyUI produced an image but /view failed to serve it',
        );
      }
    }
    throw Exception('ComfyUI finished without producing an image');
  }
}
