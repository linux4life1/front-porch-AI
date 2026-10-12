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

import 'package:front_porch_ai/services/capability/capability.dart';
import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/image/image_desk_rules.dart';

/// The busy guards, the pack's mode, portrait and prompt, and discarding a
/// phone pack.
class ImageStudioPackWorkspace {
  ImageStudioPackWorkspace(
    this._image,
    this._storage,
    this._characters,
    this._packBoard,
    this._promptLlm,
  );

  final ImageGenService _image;
  final StorageService _storage;
  final CharacterRepository? _characters;
  final ExpressionPackBoard _packBoard;

  /// Read live: the host wires the facade's [promptLlm] after construction.
  final LLMService? Function()? Function() _promptLlm;

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
    final card = repo.characters.where((c) => c.dbId == id).firstOrNull;
    if (card == null) {
      throw const DeskRefused(
        'no_character',
        'Pick a character from the library.',
        404,
      );
    }
    final raw = await packBaseImage(repo, _storage, id, card.name);
    final base = raw == null ? null : await preparePackBase(raw);
    return {
      'characterId': id,
      'image': base == null
          ? null
          : 'data:image/png;base64,${base64Encode(base.bytes)}',
    };
  }

  Future<String> craftPackPrompt(String id, {String? instruction}) async {
    final card = _characters?.characters.where((c) => c.dbId == id).firstOrNull;
    if (card == null) {
      throw const DeskRefused(
        'no_character',
        'Pick a character from the library.',
        404,
      );
    }
    return _image.generateSmartPrompt(
      llmService: _promptLlm()?.call(),
      mode: ImageGenMode.characterPortrait,
      style: _storage.imageGenSettings.imageGenStyle,
      characterName: card.name,
      characterDescription: card.description,
      currentExpression: 'neutral',
      userInstruction: instruction,
    );
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
