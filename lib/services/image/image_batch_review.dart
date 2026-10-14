// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:math';
import 'dart:io';
import 'package:flutter/painting.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/portrait_promotion.dart';
import 'package:front_porch_ai/services/image/image.dart';
import 'image_batch_store.dart';
import '../expression_pack_base.dart';
import '../expression_pack_prepare.dart';

class ImageBatchReview {
  ImageBatchReview(this.store);
  final ImageBatchStore store;

  ImageBatchJob job(String id) => store.jobs.firstWhere((j) => j.id == id);
  Future<Uint8List> picture(String id) async {
    await store.ready;
    store.requireRootStable();
    return store.file(job(id).data['candidate'] as String).readAsBytes();
  }

  Future<void> decide(
    String id,
    String action, {
    String? prompt,
    bool newSeed = true,
  }) async {
    await store.ready;
    store.requireRootStable();
    if (store.working || store.running) {
      throw StateError('Another review operation is busy.');
    }
    store.working = true;
    store.changed();
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
        target.data.addAll({
          'state': 'discarded',
          'kept': false,
          'candidate': null,
        });
      } else if (action == 'redo' &&
          ['review', 'failed', 'interrupted', 'saved'].contains(target.state)) {
        if (prompt != null &&
            (prompt.trim().isEmpty || prompt.length > 16000)) {
          throw ArgumentError('Enter a prompt up to 16000 characters.');
        }
        String? source;
        if (target.edit ||
            target.kind == 'expressions' ||
            target.data['source'] != null) {
          final repository = store.repository;
          if (repository == null) {
            throw StateError(
              'Open this character before preparing another pass.',
            );
          }
          final bytes = await packCurrentPortraitImage(
            repository,
            store.storage,
            target.characterId,
          );
          final base = bytes == null ? null : await preparePackBase(bytes);
          if (base == null) {
            throw StateError(
              'This character needs a readable source portrait.',
            );
          }
          source = '${const Uuid().v4()}.png';
          await store.ensureCapacity(base.bytes.length);
          await store.file(source).writeAsBytes(base.bytes, flush: true);
        }
        store.jobs.add(
          ImageBatchJob({
            ...target.data,
            'id': const Uuid().v4(),
            'state': 'waiting',
            'kept': false,
            'candidate': null,
            'source': source,
            'error': null,
            'config': store.snapshot(),
            'size': store.storage.imageGenSettings.imageGenSize,
            'negativePrompt': imageBatchNegativePrompt(
              store.storage.imageGenSettings.imageGenNegativePrompt,
              target.kind == 'expressions' ? target.label : null,
            ),
            'denoise':
                target.data['denoiseOverride'] ??
                store.storage.imageGenSettings.imageGenDenoise,
            'prompt': prompt ?? target.prompt,
            'seed': newSeed
                ? Random.secure().nextInt(0x7fffffff)
                : target.data['seed'],
          }),
        );
      } else {
        throw StateError('That action is not available for this result.');
      }
      await store.clean();
      await store.persist();
    } finally {
      store.working = false;
      store.changed();
    }
  }

  Future<void> saveKept(CharacterRepository repository) async {
    await store.ready;
    store.requireRootStable();
    if (store.working || store.running) {
      throw StateError('Another review operation is busy.');
    }
    final selected = store.jobs
        .where((j) => j.kept && j.state == 'review')
        .toList();
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
    store.working = true;
    store.changed();
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
          await repository.batchMedia.addLook(
            target.characterId,
            card.name,
            bytes,
            bootstrapMissingPortrait: false,
            mediaId: target.id,
          );
        } else if (target.kind == 'expressions') {
          final previous = await repository.getAvatarImages(target.characterId);
          final added = await repository.batchMedia.addAvatar(
            target.characterId,
            card.name,
            bytes,
            target.label,
            mediaId: target.id,
          );
          for (final old in previous.where(
            (avatar) => avatar.label == target.label && avatar.id != added,
          )) {
            await repository.removeAvatar(target.characterId, old.id);
          }
        } else if (target.kind == 'portrait') {
          final cachedPath = repository.characters
              .where((c) => c.dbId == target.characterId)
              .firstOrNull
              ?.imagePath;
          final lookId = await repository.batchMedia.addLook(
            target.characterId,
            card.name,
            bytes,
            bootstrapMissingPortrait: false,
            mediaId: target.id,
          );
          card.avatarImages = await repository.getAvatarImages(
            target.characterId,
          );
          await promoteLookOverPortrait(
            card: card,
            storage: store.storage,
            candidateId: lookId,
            preserveMetadata: true,
            updateCharacter: repository.updateCharacterImagePathOnly,
            removeAvatar: repository.removeAvatar,
            addLook: (id, name, pixels) => repository.batchMedia.addLook(
              id,
              name,
              pixels,
              bootstrapMissingPortrait: false,
            ),
          );
          if (cachedPath != null) await FileImage(File(cachedPath)).evict();
        } else {
          throw StateError('Unknown image save destination.');
        }
        target.data.addAll({'state': 'saved', 'candidate': null});
        await store.clean();
        await store.persist();
      }
      await repository.loadCharacters();
    } finally {
      store.working = false;
      store.changed();
    }
  }
}
