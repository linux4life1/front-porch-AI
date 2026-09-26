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

part of 'comfy_ui_service.dart';

extension _ComfyCatalog on ComfyUiService {
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
}

/// Discovery: checkpoints AND diffusion_models so ZIT/Flux/Qwen appear.
extension ComfyUiCatalogApi on ComfyUiService {
  Future<List<String>> fetchModels() async {
    final cat = await fetchCatalog();
    return cat.createDiscovery;
  }

  Future<ComfyFileCatalog> fetchCatalog() async {
    final info = await _objectInfo();
    if (info == null) return const ComfyFileCatalog();
    return ComfyFileCatalog(
      checkpoints: ComfyUiService.optionsFromObjectInfo(
        info,
        'CheckpointLoaderSimple',
        'ckpt_name',
      ),
      diffusionModels: ComfyUiService.optionsFromObjectInfo(
        info,
        'UNETLoader',
        'unet_name',
      ),
      textEncoders: ComfyUiService.optionsFromObjectInfo(
        info,
        'CLIPLoader',
        'clip_name',
      ),
      vaes: ComfyUiService.optionsFromObjectInfo(info, 'VAELoader', 'vae_name'),
      loras: ComfyUiService.optionsFromObjectInfo(
        info,
        'LoraLoader',
        'lora_name',
      ),
    );
  }

  /// The model files this ComfyUI offers for a loader slot.
  Future<List<String>> fetchModelFilesFor(
    String loaderClass,
    String inputName,
  ) async {
    final info = await _objectInfo();
    if (info == null) return const [];
    return ComfyUiService.optionsFromObjectInfo(info, loaderClass, inputName);
  }

  /// Default frontend templates (ZIT / Qwen / Flux / …) when this Comfy
  /// install serves `/templates/index.json`. Empty if the API isn't there.
  Future<List<ComfyTemplateEntry>> fetchCreateTemplates() async {
    final raw = await _getJson('/templates/index.json');
    return comfyCreateTemplates(parseComfyTemplateIndex(raw));
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

  /// UI or API JSON for a default template, then a userdata workflow.
  Future<Map<String, dynamic>?> fetchTemplateJson(String name) async {
    final stem = name.replaceAll('.json', '');
    final savedPath = Uri.encodeComponent('workflows/$stem.json');
    for (final path in [
      '/templates/${Uri.encodeComponent(stem)}.json',
      '/userdata/$savedPath',
      '/api/userdata/$savedPath',
    ]) {
      final raw = await _getJson(path);
      if (raw is Map) return raw.cast<String, dynamic>();
    }
    return null;
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
