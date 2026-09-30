// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of 'image_facade.dart';

/// Expression packs on the phone: the same pack, the same decision and the
/// same lock as the desktop dialog. The phone sends what the person chose; the
/// computer decides how the pictures are made (or why they cannot be).
extension ImageStudioPacks on ImageFacade {
  ExpressionPackBoard get _board => _packBoard;

  /// The pack on the board, or null.
  Map<String, Object?>? packView() => _board.view();

  /// Starts a pack for [f]`['characterId']`. It answers at once with the
  /// pack's state; the pictures are made in the background.
  Future<Map<String, Object?>> startPack(Map<String, dynamic> f) async {
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
        await _reference(f) ??
        await packBaseImage(repo, _storage, id, card.name);
    if (raw == null) {
      throw DeskRefused(
        'no_base',
        '${card.name} has no portrait yet. Pick a picture to build from.',
      );
    }
    PackBaseRefusal? refused;
    final base = normalizePackBase(raw, onRefused: (r) => refused = r);
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
    final prompt = '${f['prompt'] ?? ''}'.trim();
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

    final denoise = ((f['denoise'] as num?)?.toDouble() ?? 0.7).clamp(
      0.30,
      0.85,
    );
    final flight = await withoutCity96Ask(
      () => beginExpressionPack(
        imageGen: _image,
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
    run.imported = await ExpressionPackImporter.importPack(
      repository: repo,
      storage: _storage,
      characterDbId: run.characterId!,
      characterName: run.characterName,
      slots: run.session.slots,
      replaceSameLabel: run.replaceExisting,
    );
    return _board.view()!;
  }

  /// A finished picture of the pack, or null.
  Uint8List? packPicture(String? emotion) => _board.picture(emotion ?? '');
}
