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

import '../image/image.dart';
import 'object_info_options.dart';

/// Long enough for one expression pack, short enough that a newly installed
/// node shows up on the next sitting.
const Duration _objectInfoFreshFor = Duration(minutes: 2);

/// Reads what one ComfyUI server offers: its `/object_info` node list (with a
/// short-lived cache), the model catalog built from it, and its templates and
/// saved workflows. Discovery: checkpoints AND diffusion_models so
/// ZIT/Flux/Qwen appear.
class ComfyCatalogReader {
  ComfyCatalogReader(this._root);

  /// Scheme-normalized server root, e.g. `http://127.0.0.1:8188`.
  final String _root;

  Map<String, dynamic>? _objectInfoCache;
  DateTime? _objectInfoCachedAt;

  /// One /object_info fetch shared by a generate and its sampler lookup.
  /// A successful read is reused for [_objectInfoFreshFor]. Pass
  /// [fresh] for a model or LoRA list: a file can appear the moment a
  /// download finishes, and that list must not stay on the generate cache.
  /// A failed read is not kept. [fromCache] belongs to this read only.
  Future<({Map<String, dynamic>? info, bool fromCache})> _readObjectInfo({
    bool fresh = false,
  }) async {
    if (!fresh) {
      final cached = _objectInfoCache;
      final at = _objectInfoCachedAt;
      if (cached != null &&
          at != null &&
          DateTime.now().difference(at) < _objectInfoFreshFor) {
        return (info: cached, fromCache: true);
      }
    }
    try {
      final r = await http
          .get(Uri.parse('$_root/object_info'))
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return (info: null, fromCache: false);
      final decoded = jsonDecode(r.body) as Map<String, dynamic>;
      _objectInfoCache = decoded;
      _objectInfoCachedAt = DateTime.now();
      return (info: decoded, fromCache: false);
    } catch (e) {
      debugPrint('ComfyUI: object_info failed: $e');
      return (info: null, fromCache: false);
    }
  }

  /// The node list, or null when this ComfyUI cannot be read. See
  /// [_readObjectInfo] for [fresh].
  Future<Map<String, dynamic>?> objectInfo({bool fresh = false}) async {
    final read = await _readObjectInfo(fresh: fresh);
    return read.info;
  }

  /// The graph to post. A cached node list can predate a loader the user
  /// just installed. One fresh read is enough; a second failure stands.
  /// A checkpoint graph with a GGUF file is not retried: another node list
  /// cannot turn that graph into an unet workflow.
  Future<Map<String, dynamic>> graphReadyToPost({
    required Map<String, dynamic> workflow,
    required String primaryFile,
    required bool uploaded,
  }) async {
    final read = uploaded
        ? (info: null, fromCache: false)
        : await _readObjectInfo();
    try {
      return graphToPost(
        graph: workflow,
        primaryFile: primaryFile,
        uploaded: uploaded,
        objectInfo: read.info,
      );
    } on ComfyGraphNotReady catch (e) {
      if (uploaded ||
          !read.fromCache ||
          e.block != ComfyGraphBlock.missingLoader) {
        rethrow;
      }
      final fresh = await _readObjectInfo(fresh: true);
      return graphToPost(
        graph: workflow,
        primaryFile: primaryFile,
        uploaded: false,
        objectInfo: fresh.info,
      );
    }
  }

  Future<List<String>> fetchModels() async {
    final cat = await fetchCatalog();
    return cat.createDiscovery;
  }

  Future<ComfyFileCatalog> fetchCatalog() async =>
      await fetchCatalogIfUp() ?? const ComfyFileCatalog();

  /// [fetchCatalog], or null when the server did not answer (an empty
  /// catalog is a server that answered with nothing installed).
  Future<ComfyFileCatalog?> fetchCatalogIfUp() async {
    final info = await objectInfo(fresh: true);
    if (info == null) return null;
    return assembleComfyCatalog(
      checkpoints: comfyOptionsFromObjectInfo(
        info,
        'CheckpointLoaderSimple',
        'ckpt_name',
      ),
      unetNames: comfyOptionsFromObjectInfo(info, 'UNETLoader', 'unet_name'),
      ggufNames: comfyOptionsFromObjectInfo(
        info,
        'UnetLoaderGGUF',
        'unet_name',
      ),
      ggufAdvancedNames: comfyOptionsFromObjectInfo(
        info,
        'UnetLoaderGGUFAdvanced',
        'unet_name',
      ),
      textEncoders: mergeComfyCreateModels(
        comfyOptionsFromObjectInfo(info, 'CLIPLoader', 'clip_name'),
        comfyOptionsFromObjectInfo(info, 'CLIPLoaderGGUF', 'clip_name'),
      ),
      vaes: comfyOptionsFromObjectInfo(info, 'VAELoader', 'vae_name'),
      loras: comfyOptionsFromObjectInfo(info, 'LoraLoader', 'lora_name'),
    );
  }

  /// The model files this ComfyUI offers for a loader slot.
  Future<List<String>> fetchModelFilesFor(
    String loaderClass,
    String inputName,
  ) async {
    final info = await objectInfo(fresh: true);
    if (info == null) return const [];
    return comfyOptionsFromObjectInfo(info, loaderClass, inputName);
  }

  /// Default frontend templates (ZIT / Qwen / Flux / …) when this Comfy
  /// install serves `/templates/index.json`. Empty if the API isn't there.
  Future<List<ComfyTemplateEntry>> fetchCreateTemplates() async {
    final raw = await _getJson('/templates/index.json');
    return comfyCreateTemplates(parseComfyTemplateIndex(raw));
  }

  Future<List<ComfyTemplateEntry>> fetchEditTemplates() async {
    final raw = await _getJson('/templates/index.json');
    return comfyEditTemplates(parseComfyTemplateIndex(raw));
  }

  /// Saved Desktop workflows (`user/default/workflows`). Empty on 404.
  Future<List<ComfyTemplateEntry>> fetchUserWorkflows() async {
    final raw =
        await _getJson('/userdata?dir=workflows') ??
        await _getJson('/api/userdata?dir=workflows');
    final names = <String>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is String) {
          names.add(e);
        } else if (e is Map && e['path'] != null) {
          names.add(e['path'].toString());
        }
      }
    }
    return [
      for (final n in names)
        if (n.toLowerCase().endsWith('.json'))
          ComfyTemplateEntry(
            name: n
                .replaceAll('\\', '/')
                .split('/')
                .last
                .replaceAll('.json', ''),
            title: n
                .replaceAll('\\', '/')
                .split('/')
                .last
                .replaceAll('.json', ''),
            tags: const ['Text to Image'],
            source: 'userdata',
          ),
    ];
  }

  /// UI or API JSON from the selected template source.
  Future<Map<String, dynamic>?> fetchTemplateJson(
    String name, {
    bool preferUserdata = false,
  }) async {
    final stem = name.replaceAll('.json', '');
    final savedPath = Uri.encodeComponent('workflows/$stem.json');
    final defaults = '/templates/${Uri.encodeComponent(stem)}.json';
    final saved = ['/userdata/$savedPath', '/api/userdata/$savedPath'];
    for (final path
        in preferUserdata ? [...saved, defaults] : [defaults, ...saved]) {
      final raw = await _getJson(path);
      if (raw is Map) return raw.cast<String, dynamic>();
    }
    return null;
  }

  /// The live graph behind a Create or Edit workflow pick. See
  /// `ComfyUiService.fetchWorkflowTemplate`.
  Future<Map<String, dynamic>?> fetchWorkflowTemplate(String workflowId) {
    final name = comfyTemplateNameFor(workflowId);
    if (name == null) return Future.value();
    return fetchTemplateJson(
      name,
      preferUserdata: comfyTemplatePrefersUserdata(workflowId),
    );
  }

  Future<Object?> _getJson(String path) async {
    try {
      final r = await http
          .get(Uri.parse('$_root$path'))
          .timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return null;
      return jsonDecode(r.body);
    } catch (e) {
      debugPrint('ComfyUI: GET $path failed: $e');
      return null;
    }
  }
}
