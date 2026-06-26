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

import 'package:front_porch_ai/services/character_gen_service.dart';
import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/web/facade/character_facade.dart';
import 'package:front_porch_ai/services/web/streaming/stream_hub.dart';

/// Web adapter for the AI character creator. The generator itself
/// ([CharacterGenService.generateCharacter]) is already fully headless — the
/// desktop `creator_state_engine` is just a UI wrapper around it — so this is a
/// thin driver: kick off generation, stream its step-by-step progress over the
/// WebSocket hub, and persist the result through the shared [CharacterFacade]
/// save path. No desktop code is reimplemented.
class ChargenFacade {
  ChargenFacade(this._llm, this._characters, this._hub);

  final LLMProvider _llm;
  final CharacterFacade _characters;
  final StreamHub? _hub;

  /// Whether an LLM backend is ready to generate.
  bool get available => _llm.activeService.isReady;

  /// Begin generating a character and return immediately. Progress and the
  /// final result arrive over the hub as `chargen_status` / `chargen_done` /
  /// `chargen_error` events, so the client never holds a multi-minute HTTP
  /// request open on a flaky mobile link. Returns `{ok:false, error}` only for
  /// synchronous pre-flight failures (no name / backend not ready).
  Map<String, dynamic> startCreate(Map<String, dynamic> fields) {
    final name = fields['name']?.toString().trim() ?? '';
    if (name.isEmpty) return {'ok': false, 'error': 'name is required'};
    final svc = _llm.activeService;
    if (!svc.isReady) {
      return {'ok': false, 'error': 'the LLM backend is not ready'};
    }
    unawaited(_run(name, fields, svc));
    return {'ok': true};
  }

  Future<void> _run(
    String name,
    Map<String, dynamic> fields,
    LLMService svc,
  ) async {
    try {
      final card = await CharacterGenService(svc).generateCharacter(
        name: name,
        concept: fields['concept']?.toString() ?? '',
        personalityKeywords: fields['personalityKeywords']?.toString() ?? '',
        nsfwEnabled: fields['nsfwEnabled'] == true,
        onStatus: (s) => _hub?.broadcast({'event': 'chargen_status', 'data': s}),
      );
      if (card == null) {
        _hub?.broadcast(
          {'event': 'chargen_error', 'error': 'generation produced no card'},
        );
        return;
      }
      final saved = await _characters.persistNewCard(card);
      if (saved == null) {
        _hub?.broadcast({
          'event': 'chargen_error',
          'error': 'failed to save the generated character',
        });
        return;
      }
      _hub?.broadcast({
        'event': 'chargen_done',
        'id': saved['id'],
        'name': saved['name'],
      });
    } catch (e) {
      _hub?.broadcast({'event': 'chargen_error', 'error': '$e'});
    }
  }
}
