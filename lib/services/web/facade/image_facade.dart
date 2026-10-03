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

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/capability/capability.dart';
import 'package:front_porch_ai/services/comfy_ui_service.dart';
import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/image_prompt/image_prompt.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/storage.dart';

part 'image_facade_catalog.dart';
part 'image_facade_desk.dart';
part 'image_facade_pack.dart';
part 'image_facade_pack_rules.dart';
part 'image_facade_ready.dart';

/// Web adapter for image generation: read/flip the backend config (Local A1111 /
/// Draw Things ↔ remote API) and generate an image. Reuses [ImageGenService]
/// (which routes to whichever backend is configured) and the existing settings.
class ImageFacade {
  ImageFacade(
    this._image,
    this._storage, [
    this._characters,
    ExpressionPackBoard? packBoard,
  ]) : _packBoard = packBoard ?? expressionPackBoard;

  final ImageGenService _image;
  final StorageService _storage;

  /// The library a pack is made for and imported into; null where there is none.
  final CharacterRepository? _characters;
  final ExpressionPackBoard _packBoard;

  /// How the ready check looks for ComfyUI; tests point it at their servers.
  @visibleForTesting
  ComfyUrlFinder? comfyFinder;

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
      'editModel': img.imageGenEditModel,
      'genProgress': _image.genProgress,
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
      // Whether adult CivitAI results may be asked for: the app's own adult
      // setting, which the phone cannot change.
      'adultAllowed': _storage.realismSettings.adultThemesEnabled,
      'drawThingsHost': img.drawThingsGrpcHost,
      'drawThingsPort': img.drawThingsGrpcPort,
      'drawThingsSampler': img.drawThingsSampler,
      'drawThingsSamplers': [
        for (final s in kDrawThingsSamplers)
          {'label': s.label, 'value': s.value},
      ],
      // Studio-scoped remote host (chips). `remoteApiUrl` is the resolved
      // Studio URL — flipping it here must not rewrite chat's mouth.
      ..._remoteHostConfig(img, b),
      'comfyCreateWorkflowId': img.comfyCreateWorkflowId,
      'comfyCreateModelChoices': img.comfyCreateModelChoices,
      'comfyCreateUploadedWorkflow': img.comfyCreateUploadedWorkflow
          .trim()
          .isNotEmpty,
      'comfyCreateUploadedTitle': img.comfyCreateUploadedTitle,
      'comfyEditWorkflowId': img.comfyEditWorkflowId,
      'comfyEditModelChoices': img.comfyEditModelChoices,
      'comfyEditUploadedWorkflow': img.comfyEditUploadedWorkflow
          .trim()
          .isNotEmpty,
      'comfyEditUploadedTitle': img.comfyEditUploadedTitle,
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

  /// Apply any subset of the image-gen config (only present keys change).
  Future<void> updateConfig(Map<String, dynamic> f) async {
    final img = _storage.imageGenSettings;
    final b = _storage.backendSettings;
    // A graph is checked before anything in this write is stored, so a
    // refused one leaves the config as it was. Clearing one ('') is fine.
    final graphs = <String, String>{
      for (final key in [
        'comfyCreateUploadedWorkflow',
        'comfyEditUploadedWorkflow',
      ])
        if (f[key] is String && (f[key] as String).trim().isNotEmpty)
          key: checkedDeskGraph(f[key] as String),
    };
    if (f['backend'] is String) {
      await img.setImageGenBackend(f['backend'] as String);
    }
    if (f['size'] is String) {
      await img.setImageGenSize(snappedStudioSize(f['size'] as String));
    }
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
      await img.setDrawThingsGrpcPort(
        (f['drawThingsPort'] as int).clamp(1, 65535),
      );
    }
    if (f['drawThingsSampler'] is int) {
      await img.setDrawThingsSampler(f['drawThingsSampler'] as int);
    }
    if (f['loraOverrideFamily'] is String) {
      await img.prefs?.setString(
        img.k('image_studio_lora_override_family'),
        f['loraOverrideFamily'] as String,
      );
      img.notify();
    }
    if (f['editModel'] is String) {
      await img.setImageGenEditModel(f['editModel'] as String);
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
        graphs['comfyCreateUploadedWorkflow'] ?? '',
        title: f['comfyCreateUploadedTitle']?.toString() ?? '',
      );
    }
    if (f['comfyEditUploadedWorkflow'] is String) {
      await img.setComfyEditUploadedWorkflow(
        graphs['comfyEditUploadedWorkflow'] ?? '',
        title: f['comfyEditUploadedTitle']?.toString() ?? '',
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
    // Edit changes a picture: it needs one, and it runs the Edit graph and
    // model. A Create with a picture varies it (img2img).
    final edit = f['mode'] == 'edit';
    final reference = await _reference(f);
    if (edit && reference == null) {
      throw const DeskRefused('needs_picture', 'Pick a picture to edit.');
    }
    // negativePrompt: absent → null → generateImage falls back to the user's
    // configured default (the web panel sends only a prompt). An explicit
    // value — including '' — is respected as-is.
    // The phone or web caller cannot answer the desktop's loader dialog, so
    // the gate answers "confirm on the desktop" at once instead of waiting.
    final bytes = await withoutCity96Ask(
      () => _image.generateImage(
        prompt: prompt,
        negativePrompt: f['negativePrompt']?.toString(),
        size: f['size']?.toString(),
        referenceImage: reference,
        intent: edit ? StudioIntent.edit : StudioIntent.create,
        editStrength: (f['editStrength'] as num?)?.toDouble(),
      ),
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
