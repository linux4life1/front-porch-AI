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

import 'dart:isolate';
import 'dart:typed_data';

import 'package:front_porch_ai/app_version.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/utils.dart';

import 'porch_format.dart';
import 'porch_open_chat.dart';

/// Builds `.porch` files: the card (portrait, fields, lorebook), every 1:1
/// chat as an `.fpchat` package, the gallery looks and the expression images.
class PorchExporter {
  PorchExporter({
    required this.repo,
    required this.chat,
    required this.storage,
  });

  final CharacterRepository repo;
  final ChatService chat;
  final StorageService storage;

  /// The file for [cards]: one `.porch`, or one `.porchpack` for two or more.
  /// Throws [PorchRefused] with words to show when it cannot run.
  Future<({String fileName, Uint8List bytes})> exportCards(
    List<CharacterCard> cards, {
    void Function(int done, int total, String name)? onProgress,
  }) async {
    if (cards.isEmpty) {
      throw const PorchRefused('Pick at least one character to export.');
    }
    return keepingOpenChat(chat, () async {
      final files = <({String name, Uint8List bytes})>[];
      for (final (i, card) in cards.indexed) {
        onProgress?.call(i, cards.length, card.name);
        files.add((name: card.name, bytes: await _encodeOne(card)));
      }
      onProgress?.call(cards.length, cards.length, '');
      if (files.length == 1) {
        return (
          fileName: porchFileName(cards.first.name),
          bytes: files.first.bytes,
        );
      }
      return (
        fileName: porchPackFileName(files.length),
        bytes: await _packOff(files),
      );
    });
  }

  Future<Uint8List> _encodeOne(CharacterCard card) async {
    // The card's own id is how a later import knows it is already there.
    // An older card without one gets it now, as a card import gives it.
    final ext = card.frontPorchExtensions ??= FrontPorchExtensions();
    if (ext.stableId == null || ext.stableId!.isEmpty) {
      ext.ensureStableId();
      await repo.updateCharacter(card, notify: false);
    }
    final image = card.imagePath;
    final portrait = image == null || image.isEmpty
        ? null
        : storage.resolveCharacterImage(image);
    final cardPng = await V2CardService().encodeCharacterCardToPngBytes(
      card,
      portrait != null && await portrait.exists() ? portrait.path : null,
    );

    final star = card.frontPorchExtensions?.favoriteAvatarId;
    final looks = <PorchImage>[];
    final expressions = <PorchImage>[];
    final dbId = card.dbId;
    if (dbId != null) {
      final base = storage.characterBaseDir(card.name).path;
      for (final a in await repo.getAvatarImages(dbId)) {
        final file = a.resolveFile(base);
        // A row whose file is gone has nothing to carry.
        if (!await file.exists()) continue;
        final img = PorchImage(
          bytes: await file.readAsBytes(),
          label: a.isLook ? null : a.label,
          starred: star != null && a.id == star,
        );
        (a.isLook ? looks : expressions).add(img);
      }
    }

    final character = PorchCharacter(
      name: card.name,
      stableId: card.frontPorchExtensions?.stableId,
      stableGroupId: card.stableGroupId,
      cardPng: Uint8List.fromList(cardPng),
      chats: await chat.exportChatPackagesOf(card),
      looks: looks,
      expressions: expressions,
    );
    return _encodeOff(character);
  }
}

// Top level, so each isolate closure captures only its arguments.
Future<Uint8List> _encodeOff(PorchCharacter c) =>
    Isolate.run(() => encodePorch(c, appVersion: appVersion));

Future<Uint8List> _packOff(List<({String name, Uint8List bytes})> files) =>
    Isolate.run(() => encodePorchPack(files, appVersion: appVersion));
