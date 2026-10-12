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

import 'package:front_porch_ai/services/capability/capability.dart';
import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/storage.dart';
import 'package:front_porch_ai/services/web/facade/image/image_desk_rules.dart';
import 'package:front_porch_ai/services/web/facade/image/image_pack_workspace.dart';

/// Read/write of the Image Studio config for the web panel. The API key is
/// never returned (presence only).
class ImageStudioConfig {
  ImageStudioConfig(this._image, this._storage, this._ws);

  final ImageGenService _image;
  final StorageService _storage;
  final ImageStudioPackWorkspace _ws;

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
      'packConfigMode': _ws.packConfigMode,
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
    _ws.requireIdleImageSettings();
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
      _ws.requireIdleImageSettings();
      await img.setImageGenBackend(f['backend'] as String);
    }
    if (f['size'] is String) {
      _ws.requireIdleImageSettings();
      await img.setImageGenSize(snappedStudioSize(f['size'] as String));
    }
    if (f['style'] is String) {
      _ws.requireIdleImageSettings();
      await img.setImageGenStyle(f['style'] as String);
    }
    if (f['negativePrompt'] is String) {
      _ws.requireIdleImageSettings();
      await img.setImageGenNegativePrompt(f['negativePrompt'] as String);
    }
    if (f['steps'] is int) {
      _ws.requireIdleImageSettings();
      await img.setImageGenSteps(f['steps'] as int);
    }
    if (f['cfgScale'] is num) {
      _ws.requireIdleImageSettings();
      await img.setImageGenCfgScale((f['cfgScale'] as num).toDouble());
    }
    if (f['sampler'] is String) {
      _ws.requireIdleImageSettings();
      await img.setImageGenSampler(f['sampler'] as String);
    }
    if (f['scheduler'] is String) {
      _ws.requireIdleImageSettings();
      await img.setImageGenScheduler(f['scheduler'] as String);
    }
    if (f['lora'] is String) {
      _ws.requireIdleImageSettings();
      await img.setImageGenLora(f['lora'] as String);
    }
    if (f['loraWeight'] is num) {
      _ws.requireIdleImageSettings();
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
      _ws.requireIdleImageSettings();
      await img.setImageGenLoraSlots(parsed);
    }
    if (f['localUrl'] is String) {
      _ws.requireIdleImageSettings();
      await img.setLocalImageGenUrl(f['localUrl'] as String);
    }
    if (f['comfyUrl'] is String) {
      _ws.requireIdleImageSettings();
      await img.setComfyUiUrl(f['comfyUrl'] as String);
    }
    if (f['promptReview'] is bool) {
      _ws.requireIdleImageSettings();
      await img.setImageGenPromptReview(f['promptReview'] as bool);
    }
    if (f['drawThingsHost'] is String) {
      _ws.requireIdleImageSettings();
      await img.setDrawThingsGrpcHost(f['drawThingsHost'] as String);
    }
    if (f['drawThingsPort'] is int) {
      _ws.requireIdleImageSettings();
      await img.setDrawThingsGrpcPort(
        (f['drawThingsPort'] as int).clamp(1, 65535),
      );
    }
    if (f['drawThingsSampler'] is int) {
      _ws.requireIdleImageSettings();
      await img.setDrawThingsSampler(f['drawThingsSampler'] as int);
    }
    if (f['loraOverrideFamily'] is String) {
      _ws.requireIdleImageSettings();
      await img.prefs?.setString(
        img.k('image_studio_lora_override_family'),
        f['loraOverrideFamily'] as String,
      );
      img.notify();
    }
    if (f['editModel'] is String) {
      _ws.requireIdleImageSettings();
      await img.setImageGenEditModel(f['editModel'] as String);
    }
    // Studio-scoped host only. `imageRemoteHost` is the chip id; a raw
    // `remoteApiUrl` from older PWAs still parks on Image Studio, never chat.
    final hostUrl = imageRemoteUrlForHostId('${f['imageRemoteHost'] ?? ''}');
    if (hostUrl != null) {
      _ws.requireIdleImageSettings();
      await applyImageRemoteHost(
        image: img,
        url: hostUrl,
        chatRemoteApiUrl: b.remoteApiUrl,
        editScoped: f['mode'] == 'edit',
        canWrite: () {
          _ws.requireIdleImageSettings();
          return true;
        },
      );
    } else if (f['remoteApiUrl'] is String) {
      _ws.requireIdleImageSettings();
      await applyImageRemoteHost(
        image: img,
        url: f['remoteApiUrl'] as String,
        chatRemoteApiUrl: b.remoteApiUrl,
        editScoped: f['mode'] == 'edit',
        canWrite: () {
          _ws.requireIdleImageSettings();
          return true;
        },
      );
    }
    if (f['model'] is String) {
      final id = f['model'] as String;
      if (!looksLikeLocalImageModel(id)) {
        _ws.requireIdleImageSettings();
        await img.setImageGenModel(id);
        final url = resolveImageStudioRemoteAccount(
          imageRemoteApiUrl: img.imageRemoteApiUrl,
          chatRemoteApiUrl: b.remoteApiUrl,
          keyFor: b.remoteApiKeyFor,
        ).url;
        _ws.requireIdleImageSettings();
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
      _ws.requireIdleImageSettings();
      await b.setRemoteApiKeyFor(url, apiKey);
    }
    if (f['comfyCreateUploadedWorkflow'] is String) {
      _ws.requireIdleImageSettings();
      await img.setComfyCreateUploadedWorkflow(
        graphs['comfyCreateUploadedWorkflow'] ?? '',
        title: f['comfyCreateUploadedTitle']?.toString() ?? '',
      );
    }
    if (f['comfyEditUploadedWorkflow'] is String) {
      _ws.requireIdleImageSettings();
      await img.setComfyEditUploadedWorkflow(
        graphs['comfyEditUploadedWorkflow'] ?? '',
        title: f['comfyEditUploadedTitle']?.toString() ?? '',
      );
    }
    if (f['comfyEditWorkflowId'] is String) {
      _ws.requireIdleImageSettings();
      await img.setComfyEditWorkflowId(f['comfyEditWorkflowId'] as String);
    }
    final editChoices = f['comfyEditModelChoices'];
    if (editChoices is Map) {
      for (final entry in editChoices.entries) {
        final key = entry.key.toString();
        final slash = key.indexOf('/');
        if (slash <= 0) continue;
        _ws.requireIdleImageSettings();
        await img.setComfyEditModelChoice(
          key.substring(0, slash),
          key.substring(slash + 1),
          entry.value.toString(),
        );
      }
    }
    if (f['comfyCreateWorkflowId'] is String) {
      _ws.requireIdleImageSettings();
      await img.setComfyCreateWorkflowId(f['comfyCreateWorkflowId'] as String);
    }
    final choices = f['comfyCreateModelChoices'];
    if (choices is Map) {
      for (final e in choices.entries) {
        final key = e.key.toString();
        final slash = key.indexOf('/');
        if (slash <= 0) continue;
        _ws.requireIdleImageSettings();
        await img.setComfyCreateModelChoice(
          key.substring(0, slash),
          key.substring(slash + 1),
          e.value.toString(),
        );
      }
    }
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
