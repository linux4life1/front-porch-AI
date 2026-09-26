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

import 'package:front_porch_ai/services/capability/image_reference_role.dart';
import 'package:front_porch_ai/services/comfy_ui_service.dart';
import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/storage.dart';

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
    final surface = imageSurfaceFor(
      backend: ImageGenBackend.fromKey(img.imageGenBackend),
      modelName: img.imageGenModel,
    );
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
      'scheduler': img.imageGenScheduler,
      'lora': img.imageGenLora,
      'loraWeight': img.imageGenLoraWeight,
      'loras': [
        for (final slot in img.imageGenLoraSlots)
          {'file': slot.file, 'weight': slot.weight},
      ],
      'surface': surface.toJson(),
      'localUrl': img.localImageGenUrl,
      'comfyUrl': img.comfyUiUrl,
      'promptReview': img.imageGenPromptReview,
      'drawThingsHost': img.drawThingsGrpcHost,
      'drawThingsPort': img.drawThingsGrpcPort,
      // Studio-scoped remote host (chips). `remoteApiUrl` is the resolved
      // Studio URL — flipping it here must not rewrite chat's mouth.
      ..._remoteHostConfig(img, b),
      'comfyCreateWorkflowId': img.comfyCreateWorkflowId,
      'comfyCreateModelChoices': img.comfyCreateModelChoices,
      'comfyCreateUploadedWorkflow': img.comfyCreateUploadedWorkflow
          .trim()
          .isNotEmpty,
      'comfyEditWorkflowId': img.comfyEditWorkflowId,
      'comfyEditModelChoices': img.comfyEditModelChoices,
      'comfyEditUploadedWorkflow': img.comfyEditUploadedWorkflow
          .trim()
          .isNotEmpty,
      'comfyEditPresets': [
        for (final preset in kComfyEditPresets)
          {
            'id': preset.id,
            'label': preset.label,
            'slots': [
              for (final slot in preset.modelSlots)
                {
                  'token': slot.token,
                  'label': slot.label,
                  'loaderClass': slot.loaderClass,
                  'inputName': slot.inputName,
                  'folderHint': slot.folderHint,
                },
            ],
          },
      ],
      'comfyCreatePresets': [
        for (final p in kComfyCreatePresets)
          {
            'id': p.id,
            'label': p.label,
            'comfyTemplateName': p.comfyTemplateName,
            'usesCheckpointBuilder': p.usesCheckpointBuilder,
            'slots': [
              for (final s in p.modelSlots)
                {
                  'token': s.token,
                  'label': s.label,
                  'loaderClass': s.loaderClass,
                  'inputName': s.inputName,
                  'folderHint': s.folderHint,
                },
            ],
          },
      ],
    };
  }

  /// Live Comfy drawers + template names for Create / pack slot dropdowns.
  Future<Map<String, dynamic>> comfyCatalog() async {
    final url = _storage.imageGenSettings.comfyUiUrl;
    final cat = await _image.fetchComfyCatalog(url);
    final comfy = ComfyUiService(baseUrl: url);
    final templates = [
      ...await comfy.fetchCreateTemplates(),
      ...await comfy.fetchUserWorkflows(),
    ];
    final editTemplates = [
      ...await comfy.fetchEditTemplates(),
      ...await comfy.fetchUserWorkflows(),
    ];
    return {
      'checkpoints': cat.checkpoints,
      'diffusionModels': cat.diffusionModels,
      'textEncoders': cat.textEncoders,
      'vaes': cat.vaes,
      'loras': cat.loras,
      'createDiscovery': cat.createDiscovery,
      'templates': [
        for (final t in templates)
          {
            'id': t.pickerId,
            'name': t.name,
            'title': t.title,
            'source': t.source,
          },
      ],
      'editTemplates': [
        for (final t in editTemplates)
          {
            'id': t.pickerId,
            'name': t.name,
            'title': t.title,
            'source': t.source,
          },
      ],
    };
  }

  /// Resolve slots from the selected live or uploaded workflow.
  Future<Map<String, dynamic>> comfyWorkflowSlots(
    String workflowId, {
    bool edit = false,
  }) async {
    final img = _storage.imageGenSettings;
    final comfy = ComfyUiService(baseUrl: img.comfyUiUrl);
    final name = comfyTemplateNameFor(workflowId);
    final live = name == null
        ? null
        : await comfy.fetchTemplateJson(
            name,
            preferUserdata: comfyTemplatePrefersUserdata(workflowId),
          );
    Map<String, dynamic>? source;
    if (edit && workflowId == kComfyUploadedWorkflowId) {
      try {
        final decoded = jsonDecode(img.comfyEditUploadedWorkflow);
        if (decoded is Map) source = decoded.cast<String, dynamic>();
      } catch (_) {}
    } else if (edit) {
      source = live;
    } else {
      source = loadComfyCreateSource(
        workflowId: workflowId,
        uploadedWorkflowJson: img.comfyCreateUploadedWorkflow,
        liveTemplate: live,
      );
    }
    final graph = source == null ? null : ensureComfyApiGraph(source);
    final presetSlots = edit
        ? comfyEditPresetById(workflowId)?.modelSlots
        : comfyCreatePresetById(workflowId)?.modelSlots;
    final slots = presetSlots != null && presetSlots.isNotEmpty
        ? presetSlots
        : graph == null
        ? const <ComfyModelSlot>[]
        : adaptComfyApiWorkflow(graph).slots;
    return {
      'slots': [
        for (final slot in slots)
          {
            'token': slot.token,
            'label': slot.label,
            'loaderClass': slot.loaderClass,
            'inputName': slot.inputName,
            'folderHint': slot.folderHint,
            'files': await comfy.fetchModelFilesFor(
              slot.loaderClass,
              slot.inputName,
            ),
          },
      ],
    };
  }

  /// Apply any subset of the image-gen config (only present keys change).
  Future<void> updateConfig(Map<String, dynamic> f) async {
    final img = _storage.imageGenSettings;
    final b = _storage.backendSettings;
    if (f['backend'] is String) {
      await img.setImageGenBackend(f['backend'] as String);
    }
    if (f['size'] is String) await img.setImageGenSize(f['size'] as String);
    if (f['style'] is String) await img.setImageGenStyle(f['style'] as String);
    if (f['negativePrompt'] is String) {
      await img.setImageGenNegativePrompt(f['negativePrompt'] as String);
    }
    if (f['steps'] is int) await img.setImageGenSteps(f['steps'] as int);
    if (f['cfgScale'] is num) {
      await img.setImageGenCfgScale((f['cfgScale'] as num).toDouble());
    }
    if (f['sampler'] is String) {
      await img.setImageGenSampler(f['sampler'] as String);
    }
    if (f['scheduler'] is String) {
      await img.setImageGenScheduler(f['scheduler'] as String);
    }
    if (f['lora'] is String) {
      await img.setImageGenLora(f['lora'] as String);
    }
    if (f['loraWeight'] is num) {
      await img.setImageGenLoraWeight((f['loraWeight'] as num).toDouble());
    }
    if (f['loras'] is List) {
      final parsed = <ImageGenLoraSlot>[];
      for (final row in f['loras'] as List) {
        if (row is! Map) continue;
        parsed.add(
          ImageGenLoraSlot(
            file: row['file']?.toString() ?? '',
            weight: (row['weight'] as num?)?.toDouble() ?? 0.8,
          ),
        );
      }
      await img.setImageGenLoraSlots(parsed);
    }
    if (f['localUrl'] is String) {
      await img.setLocalImageGenUrl(f['localUrl'] as String);
    }
    if (f['comfyUrl'] is String) {
      await img.setComfyUiUrl(f['comfyUrl'] as String);
    }
    if (f['promptReview'] is bool) {
      await img.setImageGenPromptReview(f['promptReview'] as bool);
    }
    if (f['drawThingsHost'] is String) {
      await img.setDrawThingsGrpcHost(f['drawThingsHost'] as String);
    }
    if (f['drawThingsPort'] is int) {
      await img.setDrawThingsGrpcPort(f['drawThingsPort'] as int);
    }
    // Studio-scoped host only. `imageRemoteHost` is the chip id; a raw
    // `remoteApiUrl` from older PWAs still parks on Image Studio, never chat.
    final hostUrl = imageRemoteUrlForHostId('${f['imageRemoteHost'] ?? ''}');
    if (hostUrl != null) {
      await applyImageRemoteHost(
        image: img,
        url: hostUrl,
        chatRemoteApiUrl: b.remoteApiUrl,
        editScoped: false,
      );
    } else if (f['remoteApiUrl'] is String) {
      await applyImageRemoteHost(
        image: img,
        url: f['remoteApiUrl'] as String,
        chatRemoteApiUrl: b.remoteApiUrl,
        editScoped: false,
      );
    }
    if (f['model'] is String) {
      final id = f['model'] as String;
      if (!looksLikeLocalImageModel(id)) {
        await img.setImageGenModel(id);
        final url = resolveImageStudioRemoteAccount(
          imageRemoteApiUrl: img.imageRemoteApiUrl,
          chatRemoteApiUrl: b.remoteApiUrl,
          keyFor: b.remoteApiKeyFor,
        ).url;
        await img.setRemoteImageModelFor(url, id);
      }
    }
    final apiKey = f['apiKey']?.toString();
    if (apiKey != null && apiKey.isNotEmpty) {
      final url = resolveImageStudioRemoteAccount(
        imageRemoteApiUrl: img.imageRemoteApiUrl,
        chatRemoteApiUrl: b.remoteApiUrl,
        keyFor: b.remoteApiKeyFor,
      ).url;
      await b.setRemoteApiKeyFor(url, apiKey);
    }
    if (f['comfyCreateUploadedWorkflow'] is String) {
      await img.setComfyCreateUploadedWorkflow(
        f['comfyCreateUploadedWorkflow'] as String,
      );
    }
    if (f['comfyEditUploadedWorkflow'] is String) {
      await img.setComfyEditUploadedWorkflow(
        f['comfyEditUploadedWorkflow'] as String,
      );
    }
    if (f['comfyEditWorkflowId'] is String) {
      await img.setComfyEditWorkflowId(f['comfyEditWorkflowId'] as String);
    }
    final editChoices = f['comfyEditModelChoices'];
    if (editChoices is Map) {
      for (final entry in editChoices.entries) {
        final key = entry.key.toString();
        final slash = key.indexOf('/');
        if (slash <= 0) continue;
        await img.setComfyEditModelChoice(
          key.substring(0, slash),
          key.substring(slash + 1),
          entry.value.toString(),
        );
      }
    }
    if (f['comfyCreateWorkflowId'] is String) {
      await img.setComfyCreateWorkflowId(f['comfyCreateWorkflowId'] as String);
    }
    final choices = f['comfyCreateModelChoices'];
    if (choices is Map) {
      for (final e in choices.entries) {
        final key = e.key.toString();
        final slash = key.indexOf('/');
        if (slash <= 0) continue;
        await img.setComfyCreateModelChoice(
          key.substring(0, slash),
          key.substring(slash + 1),
          e.value.toString(),
        );
      }
    }
  }

  /// Generate an image from [prompt] using the configured backend. Returns the
  /// image as a base64 data URL plus the on-disk save path, or null on failure.
  Future<Map<String, dynamic>?> generate(Map<String, dynamic> f) async {
    final prompt = f['prompt']?.toString().trim() ?? '';
    if (prompt.isEmpty) return null;
    // negativePrompt: absent → null → generateImage falls back to the user's
    // configured default (the web panel sends only a prompt). An explicit
    // value — including '' — is respected as-is.
    final bytes = await _image.generateImage(
      prompt: prompt,
      negativePrompt: f['negativePrompt']?.toString(),
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

  /// Image models for the Studio-scoped remote host (Nano snapshot or
  /// OpenRouter listing). Labels include Pro / paid / pricing.
  Future<Map<String, dynamic>> remoteModels() async {
    final models = [...await _image.fetchImageModels()]
      ..sort(compareImageModelsForPicker);
    return {
      'models': [
        for (final m in models)
          {
            'id': m.id,
            'name': m.displayName,
            'label': imageModelListLabel(m),
            'isPaid': m.isPaid,
            'pricingInfo': m.pricingInfo,
          },
      ],
    };
  }
}

Map<String, dynamic> _remoteHostConfig(
  ImageGenSettings img,
  BackendSettings b,
) {
  final account = resolveImageStudioRemoteAccount(
    imageRemoteApiUrl: img.imageRemoteApiUrl,
    chatRemoteApiUrl: b.remoteApiUrl,
    keyFor: b.remoteApiKeyFor,
  );
  return {
    'remoteApiUrl': account.url,
    'imageRemoteHost': imageRemoteHostIdFor(account.url) ?? '',
    'hasApiKey': account.key.isNotEmpty,
    'imageRemoteHosts': [
      for (final h in kImageStudioRemoteHosts)
        {
          'id': h.id,
          'label': h.label,
          'url': h.url,
          'hasKey': b.remoteApiKeyFor(h.url).isNotEmpty,
        },
    ],
  };
}
