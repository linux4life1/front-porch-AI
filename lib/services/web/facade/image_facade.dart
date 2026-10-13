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
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/capability/capability.dart';
import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/image/image.dart';

export 'package:front_porch_ai/services/web/facade/image/image_desk_rules.dart';
export 'package:front_porch_ai/services/web/facade/image/phone_lora_facts.dart';

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
  LLMService? Function()? promptLlm;

  /// How the ready check looks for ComfyUI; tests point it at their servers.
  @visibleForTesting
  ComfyUrlFinder? comfyFinder;

  late final ImageStudioPackWorkspace _ws = ImageStudioPackWorkspace(
    _image,
    _storage,
    _characters,
    _packBoard,
    () => promptLlm,
  );
  late final ImageStudioConfig _config = ImageStudioConfig(
    _image,
    _storage,
    _ws,
  );
  late final ImageStudioDesk _desk = ImageStudioDesk(
    _image,
    _storage,
    _ws,
    savedImageFile,
  );
  late final ImageComfyCatalog _catalog = ImageComfyCatalog(_image, _storage);
  late final ImageStudioReady _ready = ImageStudioReady(
    _image,
    _storage,
    () => comfyFinder,
  );
  late final ImageStudioPackRules _rules = ImageStudioPackRules(
    _storage,
    _packBoard,
  );
  late final ImageStudioPacks _packs = ImageStudioPacks(
    _image,
    _storage,
    _characters,
    _packBoard,
    workspace: _ws,
    rules: _rules,
    desk: _desk,
  );

  /// Current image-gen config for the web panel. The API key is never returned
  /// (presence only), matching the text-backend settings facade.
  Map<String, dynamic> config() => _config.config();

  /// Apply any subset of the image-gen config (only present keys change).
  Future<void> updateConfig(Map<String, dynamic> f) => _config.updateConfig(f);

  /// Generate an image from [prompt] using the configured backend. Returns the
  /// image as a base64 data URL plus the on-disk save path, or null on failure.
  Future<Map<String, dynamic>?> generate(Map<String, dynamic> f) async {
    final prompt = f['prompt']?.toString().trim() ?? '';
    if (prompt.isEmpty) return null;
    // Edit changes a picture: it needs one, and it runs the Edit graph and
    // model. A Create with a picture varies it (img2img).
    final edit = f['mode'] == 'edit';
    final reference = await _desk.reference(f);
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

  /// What the Remote panel shows, judged by the desktop's own rules.
  /// [refresh] lists the host's models again; otherwise the last list is
  /// used, so a size pick does not wait on the network.
  Future<Map<String, Object?>> remotePanel({
    required bool edit,
    bool refresh = false,
  }) async {
    final cached = _image.cachedImageModels;
    final models = refresh || cached.isEmpty
        ? await _image.fetchImageModels()
        : cached;
    final settings = _storage.imageGenSettings;
    final backend = _storage.backendSettings;
    final url = resolveImageStudioRemoteAccount(
      imageRemoteApiUrl: settings.imageRemoteApiUrl,
      chatRemoteApiUrl: backend.remoteApiUrl,
      keyFor: backend.remoteApiKeyFor,
    ).url;
    final modelId = studioPrimaryFor(settings, edit: edit);
    return RemoteStudioPanel.build(
      selectedUrl: url,
      hasKey: (u) => backend.remoteApiKeyFor(u).isNotEmpty,
      signedIn: (u) => backend.bearerOverlay?.call(u) != null,
      models: models,
      listed: models.isNotEmpty,
      modelId: modelId,
      storedSize: settings.remoteSizeFor(modelId),
      studioSize: settings.imageGenSize,
      xaiAspect: settings.imageXaiAspect,
      xaiResolution: settings.imageXaiResolution,
    ).toJson();
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

  // ── Comfy catalog ───────────────────────────────────────────────────────
  Future<Map<String, dynamic>> comfyCatalog({
    bool edit = false,
    String token = '',
    bool loraFacts = false,
  }) => _catalog.comfyCatalog(edit: edit, token: token, loraFacts: loraFacts);

  Future<Map<String, dynamic>> comfyWorkflowSlots(
    String workflowId, {
    bool edit = false,
  }) => _catalog.comfyWorkflowSlots(workflowId, edit: edit);

  // ── Readiness ───────────────────────────────────────────────────────────
  void setExistingLoaderSupport({
    required String comfyUrl,
    required bool confirmed,
  }) =>
      _ready.setExistingLoaderSupport(comfyUrl: comfyUrl, confirmed: confirmed);

  Future<Map<String, dynamic>> localCatalog({String model = ''}) =>
      _ready.localCatalog(model: model);

  Future<Map<String, dynamic>> studioReady({required bool edit}) =>
      _ready.studioReady(edit: edit);

  Future<Map<String, Object?>> installedChoice({
    required String workflowId,
    required String file,
    required bool lora,
  }) => _ready.installedChoice(workflowId: workflowId, file: file, lora: lora);

  // ── Desk picks ──────────────────────────────────────────────────────────
  Future<void> pickModel({required bool edit, required String file}) =>
      _desk.pickModel(edit: edit, file: file);

  Future<void> pickGraph({required bool edit, required String id}) =>
      _desk.pickGraph(edit: edit, id: id);

  Future<void> pickSupport({
    required bool edit,
    required String token,
    required String file,
  }) => _desk.pickSupport(edit: edit, token: token, file: file);

  Future<Map<String, dynamic>> saveGraphFile({
    required List<int> bytes,
    required String name,
    required bool edit,
    String? useFor,
  }) =>
      _desk.saveGraphFile(bytes: bytes, name: name, edit: edit, useFor: useFor);

  // ── Expression packs ────────────────────────────────────────────────────
  Map<String, Object?>? packView() => _packs.packView();

  Future<Map<String, Object?>> startPack(Map<String, dynamic> f) =>
      _packs.startPack(f);

  Map<String, Object?> cancelPack() => _packs.cancelPack();

  Future<Map<String, Object?>> importPack(Map<String, dynamic> f) =>
      _packs.importPack(f);

  Future<Map<String, Object?>> continuePack(
    Map<String, dynamic> f, {
    bool reroll = false,
  }) => _packs.continuePack(f, reroll: reroll);

  Uint8List? packPicture(String? emotion) => _packs.packPicture(emotion);

  Map<String, Object?> packPromptDefaults() => _rules.packPromptDefaults();

  Future<Map<String, Object?>> savePackPromptDefaults(Map<String, dynamic> f) =>
      _rules.savePackPromptDefaults(f);

  Map<String, Object?> previewPackPrompts(Map<String, dynamic> f) =>
      _rules.previewPackPrompts(f);

  Map<String, Object?> updatePackPromptRules(Map<String, dynamic> f) =>
      _rules.updatePackPromptRules(f);

  void requireIdlePackImport() => _ws.requireIdlePackImport();

  void requireIdleImageSettings() => _ws.requireIdleImageSettings();

  String get packConfigMode => _ws.packConfigMode;

  Future<Map<String, Object?>> packPortrait(String id) => _ws.packPortrait(id);

  Future<String> craftPackPrompt(String id, {String? instruction}) =>
      _ws.craftPackPrompt(id, instruction: instruction);

  void discardPack() => _ws.discardPack();
}
