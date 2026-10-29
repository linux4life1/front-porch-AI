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

import 'package:front_porch_ai/services/chat/weather_biomes.dart';
import 'package:front_porch_ai/services/group_opening_generator.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/world_store/world_store.dart';

/// The web wizard's Generate buttons: a scenario or first message for a
/// group that does not exist yet, written by the same generator, setting
/// brief and dynamics text the desktop wizard uses.
class GroupDraftOpening {
  GroupDraftOpening(this._llm, this._characters, this._worlds);

  final LLMProvider _llm;
  final CharacterRepository? _characters;
  final WorldRepository? _worlds;

  /// Body: {memberIds: [library ids], scenario?, directorMode?,
  /// worlds?: {settingId, loreIds}, relationships?: {id: {id: score}}}.
  /// Returns the text, or a plain reason it could not be written.
  Future<({String? text, String? error})> generate(
    Map<String, dynamic> body, {
    required bool firstMessage,
  }) async {
    final service = _llm.activeService;
    if (!service.isReady) {
      return (
        text: null,
        error: 'No model is ready. Start KoboldCpp or set up an API first.',
      );
    }
    final ids = body['memberIds'] is List
        ? [for (final e in body['memberIds'] as List) e.toString()]
        : const <String>[];
    final members = [
      for (final id in ids)
        ?_characters?.characters.where((c) => c.dbId == id).firstOrNull,
    ];
    if (members.length < 2) {
      return (text: null, error: 'Pick at least 2 characters first.');
    }
    final generator = GroupOpeningGenerator(service);
    final brief = _brief(body['worlds']);
    final dynamics = groupDynamicsContext([
      for (final c in members) (id: c.dbId!, name: c.name),
    ], _relationships(body['relationships']));
    try {
      final text = firstMessage
          ? await generator.firstMessage(
              members: members,
              scenario: body['scenario'] is String
                  ? body['scenario'] as String
                  : '',
              isDirector: body['directorMode'] == true,
              dynamicsContext: dynamics,
              settingBrief: brief,
            )
          : await generator.scenario(
              members: members,
              dynamicsContext: dynamics,
              settingBrief: brief,
            );
      return (text: text, error: null);
    } catch (e) {
      return (text: null, error: 'Generation failed: $e');
    }
  }

  String _brief(Object? raw) {
    final w = _worlds;
    if (w == null || raw is! Map || raw['settingId'] is! String) return '';
    return groupSettingBrief(
      GroupWorldChoice(settingId: raw['settingId'] as String),
      lookup: w.worldById,
      weatherOf: (id) {
        final author = w.climateAuthorFor(id);
        return author == null
            ? null
            : Biome.resolve(
                biomeId: author.biomeId,
                biomeJson: author.biomeJson,
              ).displayName;
      },
    );
  }

  static Map<String, Map<String, int>> _relationships(Object? raw) => {
    if (raw is Map)
      for (final e in raw.entries)
        if (e.value is Map)
          e.key.toString(): {
            for (final t in (e.value as Map).entries)
              if (t.value is num) t.key.toString(): (t.value as num).toInt(),
          },
  };
}
