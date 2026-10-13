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

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/capability/capability.dart';
import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/image_prompt/image_prompt.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/image/image_desk_rules.dart';
import 'package:front_porch_ai/services/web/facade/image/image_pack_rules.dart';
import 'package:front_porch_ai/services/web/facade/image/image_pack_workspace.dart';
import 'package:front_porch_ai/services/web/facade/image/image_studio_desk.dart';

/// Expression packs on the phone: the same pack, the same decision and the
/// same lock as the desktop dialog. The phone sends what the person chose; the
/// computer decides how the pictures are made (or why they cannot be).
class ImageStudioPacks {
  ImageStudioPacks(
    this._image,
    this._storage,
    this._characters,
    this._board, {
    required ImageStudioPackWorkspace workspace,
    required ImageStudioPackRules rules,
    required ImageStudioDesk desk,
  }) : _ws = workspace,
       _rules = rules,
       _desk = desk;

  final ImageGenService _image;
  final StorageService _storage;
  final CharacterRepository? _characters;
  final ExpressionPackBoard _board;
  final ImageStudioPackWorkspace _ws;
  final ImageStudioPackRules _rules;
  final ImageStudioDesk _desk;

  /// The pack on the board, or null.
  Map<String, Object?>? packView() => _board.view();

  /// Starts a pack for [f]`['characterId']`. It answers at once with the
  /// pack's state; the pictures are made in the background.
  Future<Map<String, Object?>> startPack(Map<String, dynamic> f) async {
    _ws.requireIdlePackImport();
    if (f['workspace'] == true && _board.run != null) {
      throw const DeskRefused(
        'existing_pack',
        'Choose New pack to discard the current results first.',
        409,
      );
    }
    if (f['workspace'] == true && _image.isGenerating) {
      throw const DeskRefused('busy', kAlreadyGeneratingMessage, 409);
    }
    final rules = _rules.readPromptRules(f);
    final intensity = _rules.readIntensity(f);
    final repo = _characters;
    if (repo == null) {
      throw const DeskRefused(
        'unavailable',
        'The character library is not available.',
        503,
      );
    }
    final id = '${f['characterId'] ?? ''}';
    CharacterCard? card;
    for (final c in repo.characters) {
      if (c.dbId == id) card = c;
    }
    if (card == null) {
      throw const DeskRefused(
        'no_character',
        'Pick a character from the library.',
        404,
      );
    }
    final plan = await planExpressionPack(_storage);
    if (!plan.canStart) throw DeskRefused('not_ready', plan.refusal!, 409);

    final raw =
        await _desk.reference(f) ??
        await packBaseImage(repo, _storage, id, card.name);
    if (raw == null) {
      throw DeskRefused(
        'no_base',
        '${card.name} has no portrait yet. Pick a picture to build from.',
      );
    }
    PackBaseRefusal? refused;
    final base = await preparePackBase(raw, onRefused: (r) => refused = r);
    if (base == null) {
      final why = refused;
      throw why == null
          ? const DeskRefused('bad_picture', 'That is not a picture.')
          : DeskRefused(
              why.tooLarge ? 'too_large' : 'bad_picture',
              why.message,
              why.tooLarge ? 413 : 400,
            );
    }
    var prompt = '${f['prompt'] ?? ''}'.trim();
    if (!plan.edit && prompt.isEmpty && f['workspace'] == true) {
      prompt = await _ws.craftPackPrompt(id);
    }
    if (!plan.edit && prompt.isEmpty) {
      throw const DeskRefused(
        'needs_prompt',
        'Describe the character first: this computer makes the pack from '
            'the picture and a description.',
      );
    }

    final set = f['set'] == 'full' ? kFullExpressionSet : kCuratedExpressionSet;
    final existing = {
      for (final a in await repo.getAvatarImages(id))
        (a.label ?? '').toLowerCase(),
    };
    final emotions = f['skipExisting'] == false
        ? set
        : [
            for (final e in set)
              if (!existing.contains(e)) e,
          ];
    if (emotions.isEmpty) {
      throw DeskRefused(
        'nothing_to_do',
        '${card.name} already has all of these expressions.',
        409,
      );
    }

    try {
      for (final emotion in emotions) {
        composeExpressionPrompt(
          emotion: emotion,
          basePrompt: '$prompt, $kExpressionFraming',
          editMode: plan.edit,
          rules: rules,
          intensity: intensity,
        );
      }
    } on FormatException catch (e) {
      throw DeskRefused('bad_prompt_rules', e.message);
    }
    final denoise = ((f['denoise'] as num?)?.toDouble() ?? 0.7).clamp(
      0.30,
      0.85,
    );
    if (f['workspace'] == true && _board.run != null) {
      throw const DeskRefused(
        'existing_pack',
        'Choose New pack to discard the current results first.',
        409,
      );
    }
    _ws.requireIdlePackImport();
    final flight = await withoutCity96Ask(
      () => beginExpressionPack(
        imageGen: _image,
        promptRules: rules,
        intensity: intensity,
        plan: plan,
        emotions: emotions,
        basePrompt: '$prompt, $kExpressionFraming',
        negativePrompt: _storage.imageGenSettings.imageGenNegativePrompt,
        denoise: denoise,
        size: '${base.width}x${base.height}',
        baseImage: base.bytes,
        characterName: card!.name,
        characterId: id,
        origin: PackOrigin.phone,
        replaceExisting: f['replaceExisting'] != false,
        note: base.converted ? kPackConvertedNote : null,
        board: _board,
      ),
    );
    if (flight.session == null) {
      throw flight.busy
          ? const DeskRefused('busy', kAlreadyGeneratingMessage, 409)
          : DeskRefused(
              'failed',
              flight.error ?? 'The expression pack could not start.',
              500,
            );
    }
    return _board.view()!;
  }

  /// Stops the pack: no more pictures, and the one being made is stopped on
  /// ComfyUI too. Works on a pack the desktop started as well.
  Map<String, Object?> cancelPack() {
    final run = _board.run;
    if (run == null) {
      throw const DeskRefused('no_pack', 'No expression pack.', 404);
    }
    if (run.session.isRunning) run.session.cancel();
    return _board.view()!;
  }

  /// Puts the pack's kept pictures into the character's expressions. Only a
  /// pack the phone started, once it has stopped; [f]`['keep']` lists the
  /// emotions to keep (the rest are left out).
  Future<Map<String, Object?>> importPack(Map<String, dynamic> f) async {
    final run = _board.run;
    final repo = _characters;
    if (run == null || repo == null) {
      throw const DeskRefused('no_pack', 'No expression pack.', 404);
    }
    if (run.origin != PackOrigin.phone) {
      throw const DeskRefused(
        'desktop_pack',
        'That pack was started on the computer. Import it there.',
        409,
      );
    }
    if (run.importing) {
      throw const DeskRefused(
        'importing',
        'Wait for the pack import to finish.',
        409,
      );
    }
    if (run.session.isRunning) {
      throw const DeskRefused('running', 'It is still making pictures.', 409);
    }
    if (run.imported != null) {
      throw const DeskRefused(
        'already_imported',
        'Those pictures are already imported.',
        409,
      );
    }
    final keep = f['keep'];
    if (keep is List) {
      final wanted = {for (final e in keep) '$e'};
      final slots = run.session.slots;
      for (var i = 0; i < slots.length; i++) {
        run.session.setKeep(i, wanted.contains(slots[i].emotion));
      }
    }
    if (run.session.keptCount == 0) {
      throw const DeskRefused(
        'nothing_to_import',
        'There is nothing kept to import.',
        409,
      );
    }
    _board.setImporting(run, true);
    try {
      run.imported = await ExpressionPackImporter.importPack(
        repository: repo,
        storage: _storage,
        characterDbId: run.characterId!,
        characterName: run.characterName,
        slots: run.session.slots,
        replaceSameLabel: run.replaceExisting,
      );
    } finally {
      _board.setImporting(run, false);
    }
    return _board.view()!;
  }

  Future<Map<String, Object?>> continuePack(
    Map<String, dynamic> f, {
    bool reroll = false,
  }) async {
    final run = _board.run;
    if (run == null) {
      throw const DeskRefused('no_pack', 'No expression pack.', 404);
    }
    if (run.origin != PackOrigin.phone) {
      throw const DeskRefused(
        'desktop_pack',
        'Continue this pack on the computer.',
        409,
      );
    }
    if (run.imported != null) {
      throw const DeskRefused(
        'already_imported',
        'Those pictures are already imported.',
        409,
      );
    }
    if (run.importing) {
      throw const DeskRefused(
        'importing',
        'Wait for the pack import to finish.',
        409,
      );
    }
    if (run.session.isRunning) {
      throw const DeskRefused('running', 'It is still making pictures.', 409);
    }
    final index = run.session.slots.indexWhere(
      (s) => s.emotion == f['emotion'],
    );
    if (reroll && index < 0) {
      throw const DeskRefused('no_slot', 'Pick an expression in this pack.');
    }
    if (!reroll && run.session.pendingCount == 0) {
      throw const DeskRefused(
        'nothing_to_do',
        'There are no pending expressions.',
        409,
      );
    }
    final intensity = f.containsKey('intensity')
        ? _rules.readIntensity(f)
        : null;
    if (f.containsKey('followPackIntensity') &&
        f['followPackIntensity'] is! bool) {
      throw const DeskRefused('bad_iteration', 'Follow pack must be boolean.');
    }
    if (f.containsKey('newSeed') && f['newSeed'] is! bool ||
        f.containsKey('useIntensityPrompt') &&
            f['useIntensityPrompt'] is! bool) {
      throw const DeskRefused(
        'bad_iteration',
        'Seed and prompt options must be boolean.',
      );
    }
    final prompt = f['promptOverride'];
    if (prompt != null && (prompt is! String || prompt.length > 16384)) {
      throw const DeskRefused(
        'bad_prompt',
        'Prompt must be text of at most 16384 characters.',
      );
    }
    final ready = Completer<bool>();
    final work = ImageGenService.startExpressionPackOn(
      _image,
      reroll
          ? [run.session.slots[index].emotion]
          : [
              for (final s in run.session.slots)
                if (s.state == ExpressionSlotState.pending) s.emotion,
            ],
      (_) async {
        final generating = reroll
            ? run.session.reroll(
                index,
                newSeed: f['newSeed'] as bool? ?? true,
                intensityOverride: intensity,
                followPackIntensity: f['followPackIntensity'] == true,
                useIntensityPrompt: f['useIntensityPrompt'] == true,
                promptOverride: prompt as String?,
              )
            : run.session.run();
        ready.complete(true);
        await generating;
        return const <String>[];
      },
    );
    unawaited(
      work.then(
        (_) {
          if (!ready.isCompleted) ready.complete(false);
        },
        onError: (Object e, StackTrace st) {
          debugPrint('[ExpressionPack] Could not continue: $e');
          if (!ready.isCompleted) ready.complete(false);
        },
      ),
    );
    if (!await ready.future) {
      throw const DeskRefused('busy', kAlreadyGeneratingMessage, 409);
    }
    return _board.view()!;
  }

  /// A finished picture of the pack, or null.
  Uint8List? packPicture(String? emotion) => _board.picture(emotion ?? '');
}
