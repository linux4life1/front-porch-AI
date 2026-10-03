// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of 'image_facade.dart';

extension ImageStudioPackWorkspace on ImageFacade {
  void requireIdlePackImport() {
    if (_packBoard.run?.importing == true) {
      throw const DeskRefused(
        'importing',
        'Wait for the pack import to finish.',
        409,
      );
    }
  }

  void requireIdleImageSettings() {
    if (_image.isGenerating ||
        _packBoard.run?.session.isRunning == true ||
        _packBoard.run?.importing == true) {
      throw const DeskRefused(
        'busy',
        'Wait for image generation to finish before changing its settings.',
        409,
      );
    }
  }

  String get packConfigMode {
    final settings = _storage.imageGenSettings;
    final backend = ImageGenBackend.fromKey(settings.imageGenBackend);
    return backend == ImageGenBackend.comfyUi ||
            backend == ImageGenBackend.remote ||
            ImageReferenceResolver.packEditMode(settings)
        ? 'edit'
        : 'create';
  }

  Future<Map<String, Object?>> packPortrait(String id) async {
    final repo = _characters;
    if (repo == null) {
      throw const DeskRefused(
        'unavailable',
        'The library is unavailable.',
        503,
      );
    }
    final raw = await packCurrentPortraitImage(repo, _storage, id);
    final base = raw == null ? null : await preparePackBase(raw);
    return {
      'characterId': id,
      'image': base == null
          ? null
          : 'data:image/png;base64,${base64Encode(base.bytes)}',
    };
  }

  void discardPack() {
    final run = _packBoard.run;
    if (run == null) return;
    if (run.importing) {
      throw const DeskRefused(
        'importing',
        'Wait for the pack import to finish.',
        409,
      );
    }
    if (run.session.isRunning) {
      throw const DeskRefused(
        'running',
        'Stop the pack before discarding it.',
        409,
      );
    }
    if (run.origin != PackOrigin.phone) {
      throw const DeskRefused(
        'desktop_pack',
        'Discard this pack in Image Studio on the computer.',
        409,
      );
    }
    _packBoard.clear();
  }
}
