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
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'comfy_workflow.dart';
import 'image/comfy_edit_workflow.dart';

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

  /// Normalize a user-typed server address into a usable base URL: trims,
  /// strips trailing slashes, and prepends `http://` when no scheme is given
  /// (`localhost:8188`, `192.168.1.20:7860` → valid URLs instead of a silent
  /// connection failure). Shared by the A1111 paths in ImageGenService. Pure.
  static String ensureHttpScheme(String url) {
    var u = url.trim().replaceAll(RegExp(r'/+$'), '');
    if (u.isEmpty) return u;
    if (!u.contains('://')) u = 'http://$u';
    return u;
  }

  /// Known A1111-style → ComfyUI sampler name mappings, used when the stored
  /// sampler (shared across backends) isn't already a ComfyUI-native name.
  static const Map<String, String> _samplerAliases = {
    'euler a': 'euler_ancestral',
    'euler': 'euler',
    'heun': 'heun',
    'ddim': 'ddim',
    'lcm': 'lcm',
    'uni_pc': 'uni_pc',
    'unipc': 'uni_pc',
    'dpm++ 2m': 'dpmpp_2m',
    'dpm++ 2m karras': 'dpmpp_2m',
    'dpm++ sde': 'dpmpp_sde',
    'dpm++ sde karras': 'dpmpp_sde',
    'dpm++ 2m sde': 'dpmpp_2m_sde',
    'dpm++ 2m sde karras': 'dpmpp_2m_sde',
    'dpm++ 3m sde': 'dpmpp_3m_sde',
  };

  /// Normalize a (possibly A1111-style) sampler name to one this ComfyUI
  /// server actually offers. Pure — unit-tested. Preference order: already
  /// valid → known alias → 'euler' → first available.
  static String normalizeSampler(String stored, List<String> available) {
    final s = stored.trim();
    if (available.contains(s)) return s;
    final alias = _samplerAliases[s.toLowerCase()];
    if (alias != null && (available.isEmpty || available.contains(alias))) {
      return alias;
    }
    if (available.contains('euler')) return 'euler';
    return available.isNotEmpty ? available.first : 'euler';
  }

  /// A "Karras"-flavored A1111 sampler name maps to the karras scheduler in
  /// ComfyUI (the sampler and schedule are separate knobs there). Pure.
  static String schedulerFor(String storedSampler) =>
      storedSampler.toLowerCase().contains('karras') ? 'karras' : 'normal';

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
  ) {
    final node = objectInfo[nodeType];
    if (node is! Map) return const [];
    final input = node['input'];
    if (input is! Map) return const [];
    for (final section in ['required', 'optional']) {
      final sec = input[section];
      if (sec is! Map) continue;
      final spec = sec[inputName];
      if (spec is List && spec.isNotEmpty && spec.first is List) {
        return (spec.first as List).map((e) => e.toString()).toList();
      }
    }
    return const [];
  }

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

  /// One /object_info fetch shared by the model/LoRA/sampler listings.
  Future<Map<String, dynamic>?> _objectInfo() async {
    try {
      final r = await http
          .get(Uri.parse('$_root/object_info'))
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return null;
      return jsonDecode(r.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('ComfyUI: object_info failed: $e');
      return null;
    }
  }

  Future<List<String>> fetchModels() async {
    final info = await _objectInfo();
    if (info == null) return const [];
    return optionsFromObjectInfo(info, 'CheckpointLoaderSimple', 'ckpt_name');
  }

  Future<List<String>> fetchLoras() async {
    final info = await _objectInfo();
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
      final uri = Uri.parse(
        '$_root/view_metadata/loras',
      ).replace(queryParameters: {'filename': filename});
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
    final info = await _objectInfo();
    if (info == null) return const [];
    return optionsFromObjectInfo(info, 'KSampler', 'sampler_name');
  }

  /// The schedule (noise sigma curve) options ComfyUI's KSampler exposes —
  /// karras / exponential / sgm_uniform / normal / etc. Read from the same
  /// /object_info payload as the samplers. Empty on any error.
  Future<List<String>> fetchSchedulers() async {
    final info = await _objectInfo();
    if (info == null) return const [];
    return optionsFromObjectInfo(info, 'KSampler', 'scheduler');
  }

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
    final hasRef = referenceImageBytes != null && referenceImageBytes.isNotEmpty;
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

  /// Probe: the subset of [requiredNodes] this ComfyUI does NOT have. Empty = all
  /// present (ready). `null` = couldn't tell (server/`/object_info` unreachable),
  /// which the UI shows as "can't check" rather than a false "missing". Used to
  /// gate a bundled edit preset before the user can run it.
  Future<List<String>?> missingEditNodes(List<String> requiredNodes) async {
    final info = await _objectInfo();
    if (info == null) return null;
    return requiredNodes.where((n) => !info.containsKey(n)).toList();
  }

  /// The model files this ComfyUI offers for a loader slot (e.g.
  /// `UNETLoader.unet_name`) — feeds the Edit tab's "pick your model" dropdowns.
  Future<List<String>> fetchModelFilesFor(
    String loaderClass,
    String inputName,
  ) async {
    final info = await _objectInfo();
    if (info == null) return const [];
    return optionsFromObjectInfo(info, loaderClass, inputName);
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
    return _runWorkflow(graph, onProgress);
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
    final submit = await http
        .post(
          Uri.parse('$_root/prompt'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'prompt': workflow, 'client_id': clientId}),
        )
        .timeout(const Duration(seconds: 30));
    if (submit.statusCode != 200) {
      String detail = 'HTTP ${submit.statusCode}';
      try {
        final err = jsonDecode(submit.body);
        detail = err['error']?['message']?.toString() ?? detail;
      } catch (_) {}
      throw Exception('ComfyUI rejected the workflow: $detail');
    }
    final promptId =
        (jsonDecode(submit.body) as Map<String, dynamic>)['prompt_id']
            ?.toString();
    if (promptId == null || promptId.isEmpty) {
      throw Exception('ComfyUI did not return a prompt_id');
    }

    // Best-effort live progress over ComfyUI's WebSocket: text frames carry
    // {type:'progress', data:{value,max}} during sampling; binary frames are
    // preview images (8-byte header: int32 event type 1 = preview, int32
    // format, then JPEG/PNG bytes) when the server runs with previews on.
    WebSocket? ws;
    if (onProgress != null) {
      try {
        final wsRoot = _root
            .replaceFirst('https://', 'wss://')
            .replaceFirst('http://', 'ws://');
        ws = await WebSocket.connect(
          '$wsRoot/ws?clientId=$clientId',
        ).timeout(const Duration(seconds: 3));
        ws.listen(
          (frame) {
            try {
              if (frame is String) {
                final msg = jsonDecode(frame) as Map<String, dynamic>;
                if (msg['type'] == 'progress') {
                  final d = msg['data'] as Map<String, dynamic>?;
                  final value = (d?['value'] as num?)?.toDouble();
                  final max = (d?['max'] as num?)?.toDouble();
                  if (value != null && max != null && max > 0) {
                    onProgress((value / max).clamp(0.0, 1.0), null);
                  }
                }
              } else if (frame is List<int> && frame.length > 8) {
                final header = Uint8List.fromList(
                  frame.sublist(0, 4),
                ).buffer.asByteData();
                if (header.getInt32(0) == 1) {
                  onProgress(null, Uint8List.fromList(frame.sublist(8)));
                }
              }
            } catch (_) {
              // malformed frame — ignore; progress is decorative
            }
          },
          onError: (_) {},
          cancelOnError: true,
        );
      } catch (e) {
        debugPrint('ComfyUI: progress WebSocket unavailable ($e)');
        ws = null;
      }
    }

    // Poll history until this prompt completes (generation can be slow on
    // first model load; 10 min cap mirrors the other local backends). The
    // WebSocket above is decorative only — completion truth stays here.
    final deadline = DateTime.now().add(const Duration(minutes: 10));
    Map<String, dynamic>? outputs;
    try {
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(seconds: 1));
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
            throw Exception(
              'ComfyUI reported an error — check the model name and its '
              'server console.',
            );
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
