// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of 'image_batch_service.dart';

extension ImageBatchReview on ImageBatchService {
  ImageBatchJob job(String id) => _jobs.firstWhere((j) => j.id == id);
  Future<Uint8List> picture(String id) async {
    await ready;
    _requireRootStable();
    return _file(job(id).data['candidate'] as String).readAsBytes();
  }

  Future<void> decide(
    String id,
    String action, {
    String? prompt,
    bool newSeed = true,
  }) async {
    await ready;
    _requireRootStable();
    if (working) {
      throw StateError('Another review operation is busy.');
    }
    working = true;
    _changed();
    try {
      final target = job(id);
      if (action == 'keep' && target.state == 'review') {
        target.data['kept'] = !target.kept;
      } else if (action == 'discard' &&
          [
            'waiting',
            'review',
            'failed',
            'interrupted',
          ].contains(target.state)) {
        target.data.addAll({'state': 'discarded', 'kept': false});
      } else if (action == 'redo' &&
          ['review', 'failed', 'interrupted', 'saved'].contains(target.state)) {
        if (prompt != null &&
            (prompt.trim().isEmpty || prompt.length > 16000)) {
          throw ArgumentError('Enter a prompt up to 16000 characters.');
        }
        _jobs.add(
          ImageBatchJob({
            ...target.data,
            'id': const Uuid().v4(),
            'state': 'waiting',
            'kept': false,
            'candidate': null,
            'error': null,
            'config': snapshot(),
            'prompt': prompt ?? target.prompt,
            'seed': newSeed
                ? Random.secure().nextInt(0x7fffffff)
                : target.data['seed'],
          }),
        );
      } else {
        throw StateError('That action is not available for this result.');
      }
      await _persist();
    } finally {
      working = false;
      _changed();
    }
  }

  Future<void> saveKept(CharacterRepository repository) async {
    await ready;
    _requireRootStable();
    if (working) throw StateError('Another review operation is busy.');
    final selected = _jobs.where((j) => j.kept && j.state == 'review').toList();
    if (selected
            .where((j) => j.kind != 'additional')
            .map((j) => '${j.characterId}/${j.label}')
            .toSet()
            .length !=
        selected.where((j) => j.kind != 'additional').length) {
      throw StateError(
        'Keep only one candidate for each primary portrait or expression.',
      );
    }
    working = true;
    _changed();
    try {
      for (final target in selected) {
        final card = await repository.getActiveCharacterCardById(
          target.characterId,
        );
        if (card == null) {
          throw StateError('${target.characterName} no longer exists.');
        }
        final bytes = await picture(target.id);
        if (target.kind == 'additional') {
          await repository.addLook(
            target.characterId,
            card.name,
            bytes,
            bootstrapMissingPortrait: false,
            mediaId: target.id,
          );
        } else if (target.kind == 'expressions') {
          await repository.addAvatar(
            target.characterId,
            card.name,
            bytes,
            target.label,
            mediaId: target.id,
          );
        } else if (target.kind == 'portrait') {
          final oldPath = card.imagePath;
          final output = oldPath == null || oldPath.isEmpty
              ? portraitWriteTarget(card: card, storage: storage).path
              : storage.resolveCharacterImage(oldPath).path;
          await V2CardService().replacePortraitPixels(
            fallbackCard: card,
            outputPath: output,
            pixels: bytes,
            metadataSourcePath: card.imagePath,
          );
          await FileImage(File(output)).evict();
          card.imagePath = output;
          await repository.updateCharacterImagePathOnly(card);
        } else {
          throw StateError('Unknown image save destination.');
        }
        target.data['state'] = 'saved';
        await _persist();
      }
      await repository.loadCharacters();
    } finally {
      working = false;
      _changed();
    }
  }
}
