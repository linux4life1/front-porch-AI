// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:front_porch_ai/services/capability/capability.dart';
import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/image_gen_settings.dart';
import 'package:front_porch_ai/ui/settings/dialogs/model_search_dialog.dart';

import 'studio_desk_catalog.dart';
import 'studio_desk_host.dart';

/// The Remote API side of the desk: what the panel shows, and the writes
/// its host tiles, key box, model list and size pills ask for.
class StudioDeskRemote {
  StudioDeskRemote(this._host, {required this.catalog, required this.recheck});

  final StudioDeskHost _host;
  final StudioDeskCatalog catalog;

  /// Lists the new host's models and judges Ready again.
  final void Function(ImageGenSettings settings) recheck;

  bool get _locked => _host.configurationLocked;

  RemoteStudioPanel panel(StorageService storage) {
    final settings = storage.imageGenSettings;
    final backend = storage.backendSettings;
    final url = resolveImageStudioRemoteAccount(
      imageRemoteApiUrl: settings.imageRemoteApiUrl,
      chatRemoteApiUrl: backend.remoteApiUrl,
      keyFor: backend.remoteApiKeyFor,
    ).url;
    final modelId = studioPrimaryFor(settings, edit: _host.editing);
    return RemoteStudioPanel.build(
      selectedUrl: url,
      hasKey: (u) => backend.remoteApiKeyFor(u).isNotEmpty,
      signedIn: (u) => backend.bearerOverlay?.call(u) != null,
      models: catalog.remoteModels,
      listed: catalog.reachable('remote', null),
      modelId: modelId,
      storedSize: settings.remoteSizeFor(modelId),
      studioSize: settings.imageGenSize,
      xaiAspect: settings.imageXaiAspect,
      xaiResolution: settings.imageXaiResolution,
    );
  }

  Future<void> pickHost(StorageService storage, String url) async {
    if (_locked) return;
    final settings = storage.imageGenSettings;
    await applyImageRemoteHost(
      image: settings,
      url: url,
      chatRemoteApiUrl: storage.backendSettings.remoteApiUrl,
      editScoped: _host.editing,
      canWrite: () => !_locked,
    );
    recheck(settings);
  }

  /// Saves [key] in the vault slot of the host on the panel.
  Future<void> saveKey(StorageService storage, String key) async {
    if (_locked || key.trim().isEmpty) return;
    final url = panel(storage).url;
    await storage.backendSettings.setRemoteApiKeyFor(url, key.trim());
    recheck(storage.imageGenSettings);
  }

  void openModels(StorageService storage) {
    final settings = storage.imageGenSettings;
    final models = [...catalog.remoteModels]..sort(compareImageModelsForPicker);
    showGenericModelSearchDialog<ImageModelInfo>(
      _host.context,
      models,
      title: 'Select Image Model',
      getTitle: imageModelListLabel,
      getSubtitle: (m) => m.id,
      onSelected: (m) => _pickModel(settings, m.id),
    );
  }

  Future<void> _pickModel(ImageGenSettings settings, String id) async {
    if (_locked || looksLikeLocalImageModel(id)) return;
    final edit = _host.editing;
    if (edit) {
      await settings.setImageGenEditModel(id);
    } else {
      await settings.setImageGenModel(id);
    }
    await settings.setRemoteImageModelFor(
      settings.imageRemoteApiUrl,
      id,
      edit: edit,
    );
  }

  Future<void> pickSize(ImageGenSettings settings, String value) async {
    if (_locked) return;
    await settings.setRemoteSizeFor(
      studioPrimaryFor(settings, edit: _host.editing),
      value,
    );
  }

  Future<void> pickAspect(ImageGenSettings settings, String value) async {
    if (!_locked) await settings.setImageXaiAspect(value);
  }

  Future<void> pickResolution(ImageGenSettings settings, String value) async {
    if (!_locked) await settings.setImageXaiResolution(value);
  }
}
