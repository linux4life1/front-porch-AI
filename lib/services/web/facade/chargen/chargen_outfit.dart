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
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chargen/chargen.dart';
import 'package:front_porch_ai/services/chat/pockets/pockets_record.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/character_facade.dart';
import 'package:front_porch_ai/services/web/streaming/stream_hub.dart';

/// Where a creator-made card records which first message its outfit
/// (Wearing / Carrying) was read from: the desktop keeps this in the
/// wizard's memory (`CreatorGreetings.outfitReadFrom`); the web wizard
/// reloads, so it rides on the card, as the greeting recipe does.
const kOutfitSourceExtensionKey = 'outfit_read_from';

/// A fingerprint of [firstMessage], the same whether [name] is written out
/// or as `{{char}}`.
String outfitSourceOf(String firstMessage, {String name = ''}) => sha1
    .convert(utf8.encode(applyCharMacro(firstMessage, name).trim()))
    .toString();

/// The outfit on [card] now stands for its first message as it reads today.
void stampOutfitSource(CharacterCard card) {
  final raw = Map<String, dynamic>.from(card.rawExtensions ?? {});
  raw[kOutfitSourceExtensionKey] = outfitSourceOf(
    card.firstMessage,
    name: card.name,
  );
  card.rawExtensions = raw;
}

/// The first message changed since the outfit was read (#370). A card with
/// no record (not made by the creator here) never asks.
bool outfitSourceChanged(CharacterCard card) {
  final from = card.rawExtensions?[kOutfitSourceExtensionKey];
  if (from is! String || from.isEmpty) return false;
  return from != outfitSourceOf(card.firstMessage, name: card.name);
}

/// The Realism step's outfit hint on the web: whether the first message
/// changed since the outfit was read, a re-read with the extraction the
/// creator ran (`CharacterGenService.rereadOpeningWardrobe`, the desktop's
/// own call), and Keep. The re-read answers at once; its end arrives over
/// the hub as `chargen_outfit_done` (the outfit saved) or
/// `chargen_outfit_error`. On no answer nothing is changed.
class ChargenOutfit {
  ChargenOutfit(
    this._llm,
    this._characters,
    this._hub, {
    required String? Function() busyReason,
    required GreetingRecipe Function(String id, CharacterCard card) recipeFor,
  }) : _busyReason = busyReason,
       _recipeFor = recipeFor;

  final LLMProvider _llm;
  final CharacterFacade _characters;
  final StreamHub? _hub;
  final String? Function() _busyReason;
  final GreetingRecipe Function(String id, CharacterCard card) _recipeFor;

  /// The character whose outfit is being read, and its run.
  ({String id, CharacterGenService gen})? _job;

  /// The last re-read that came back empty, by character, until the next
  /// try or Keep (the desktop's `outfitError`).
  final Map<String, String> _errors = {};

  bool get busy => _job != null;

  static const _noAnswer =
      'The outfit could not be read from the new first message. Nothing '
      'was changed. Try again, or edit it below.';

  /// `{changed, reading, error}` for [id], or null when there is no such
  /// character.
  Map<String, dynamic>? status(String id) {
    final card = _characters.cardByDbId(id);
    if (card == null) return null;
    return {
      'changed': outfitSourceChanged(card),
      'reading': _job?.id == id,
      'error': _errors[id],
    };
  }

  /// Start the re-read for `characterId`. `{ok: true}`, or `{ok: false,
  /// status, error}` to refuse at once (one model call at a time).
  Map<String, dynamic> startReread(Map<String, dynamic> body) {
    final id = body['characterId']?.toString().trim() ?? '';
    if (id.isEmpty) return _refuse(400, 'characterId is required');
    final card = _characters.cardByDbId(id);
    if (card == null) return _refuse(404, 'character not found');
    if (busy) return _refuse(409, 'The outfit is already being read.');
    final reason = _busyReason();
    if (reason != null) return _refuse(409, reason);
    if (!_llm.activeService.isReady) {
      return _refuse(400, 'the LLM backend is not ready');
    }
    final job = _job = (id: id, gen: CharacterGenService(_llm.activeService));
    _errors.remove(id);
    unawaited(_read(job, card));
    return {'ok': true};
  }

  /// "Keep this outfit": it now stands for the first message as it reads.
  Future<Map<String, dynamic>> keep(Map<String, dynamic> body) async {
    final id = body['characterId']?.toString().trim() ?? '';
    if (id.isEmpty) return _refuse(400, 'characterId is required');
    final card = _characters.cardByDbId(id);
    if (card == null) return _refuse(404, 'character not found');
    if (_job?.id == id) return _refuse(409, 'The outfit is being read.');
    _errors.remove(id);
    stampOutfitSource(card);
    final ok = await _characters.update(id, const {});
    if (!ok) return _refuse(500, 'The outfit could not be kept.');
    return {'ok': true, ...?status(id)};
  }

  Future<void> _read(
    ({String id, CharacterGenService gen}) job,
    CharacterCard card,
  ) async {
    PorchLifeIdentity? read;
    try {
      read = await job.gen.rereadOpeningWardrobe(
        card: card,
        recipe: _recipeFor(job.id, card),
        // Never kill evals a live chat may have in flight (the chargen rule).
        abortInFlight: false,
      );
    } catch (e) {
      debugPrint('[chargen] outfit re-read failed: $e');
    }
    if (!identical(_job, job)) return;
    _job = null;
    if (read == null) {
      _errors[job.id] = _noAnswer;
      _hub?.broadcast({
        'event': 'chargen_outfit_error',
        'characterId': job.id,
        'error': _noAnswer,
      });
      return;
    }
    final ext = card.frontPorchExtensions ?? FrontPorchExtensions();
    card.frontPorchExtensions = ext.copyWith(
      inventory: Pockets.cardJsonFrom(worn: read.worn, carrying: read.carrying),
    );
    stampOutfitSource(card);
    final ok = await _characters.update(job.id, const {});
    _hub?.broadcast(
      ok
          ? {'event': 'chargen_outfit_done', 'characterId': job.id}
          : {
              'event': 'chargen_outfit_error',
              'characterId': job.id,
              'error': 'The outfit was read but could not be saved.',
            },
    );
  }

  Map<String, dynamic> _refuse(int status, String error) => {
    'ok': false,
    'status': status,
    'error': error,
  };
}
