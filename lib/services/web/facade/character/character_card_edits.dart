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

import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/util/util.dart';

/// Apply the web editor's [fields] to [card] in place. Only keys present in
/// [fields] change. [needsSimDefault] is the Porch Life Needs default.
void applyCharacterFields(
  CharacterCard card,
  Map<String, dynamic> fields, {
  required bool needsSimDefault,
}) {
  String pick(String key, String current) =>
      fields.containsKey(key) ? (fields[key]?.toString() ?? current) : current;
  card.name = pick('name', card.name);
  card.description = pick('description', card.description);
  card.personality = pick('personality', card.personality);
  card.scenario = pick('scenario', card.scenario);
  card.firstMessage = pick('firstMessage', card.firstMessage);
  card.mesExample = pick('mesExample', card.mesExample);
  card.systemPrompt = pick('systemPrompt', card.systemPrompt);
  card.postHistoryInstructions = pick(
    'postHistoryInstructions',
    card.postHistoryInstructions,
  );
  // Per-character TTS voice (2026-08-14). Only touched when the key is
  // present so a partial edit can't clear it; an explicit empty string
  // means "follow the global voice" and stores null, matching desktop.
  if (fields.containsKey('ttsVoice')) {
    final v = fields['ttsVoice']?.toString().trim() ?? '';
    card.ttsVoice = v.isEmpty ? null : v;
  }
  final tags = fields['tags'];
  if (tags is List) card.tags = tags.map((e) => e.toString()).toList();
  final greetings = fields['alternateGreetings'];
  if (greetings is List) {
    // Seeds omitted + alts present: compact against empty/null, not unpaired
    // base leftovers. Group updateSettings writes both; frontPorchFromFields
    // below writes the compacted seeds so leftover furious cannot land on
    // Get out.
    final paired = compactGreetingPairs(
      greetingSlotsFromRaw(greetings),
      fields.containsKey('greetingSeeds')
          ? parseGreetingSeeds(fields['greetingSeeds'])
          : const [],
    );
    card.alternateGreetings = paired.greetings;
  }
  // Greetings written by AI Enhance come with the recipe they were written
  // with (the Enhance proposal's greetingRecipe); it replaces the one the
  // duplicate brought from the original's creation.
  final recipe = GreetingRecipe.fromStamp(fields['greetingRecipe']);
  if (recipe != null) stampGreetingRecipe(card, recipe);
  // Linked worlds (attach worlds/lorebooks to a character). Worlds are keyed
  // by name; only replace when present so a partial edit doesn't clear them.
  final worlds = fields['worldNames'];
  if (worlds is List) {
    card.worldNames = worlds
        .map((e) => e.toString())
        .where((w) => w.trim().isNotEmpty)
        .toList();
  }
  // Per-character lorebook editing: only replace when the key is present so a
  // partial edit doesn't wipe existing lore. An explicit empty list clears it.
  if (fields.containsKey('lorebook')) {
    card.lorebook = buildLorebookFromJson(fields['lorebook']);
  }
  // Round-trip the Realism Engine + Needs seeds through the shared helper using
  // the current extensions as the base, so editing realism never wipes needs
  // (or chat-appearance) state and vice-versa. Matches the desktop save path
  // which always rebuilds extensions; the realismEnabled flag only gates use.
  // The phone always posts the Needs switch. For a card that says nothing,
  // it showed the Porch Life value (detail's needsSimWhenSilent); posting
  // that same value back is not a choice, so the card stays silent — the
  // desktop editor's rule.
  final silent = card.frontPorchExtensions?.needsSimChoice == null;
  final realismFields = silent && fields['needsSimEnabled'] == needsSimDefault
      ? (Map<String, dynamic>.of(fields)..remove('needsSimEnabled'))
      : fields;
  card.frontPorchExtensions = frontPorchFromFields(
    realismFields,
    base: card.frontPorchExtensions,
  );
}

/// A new card from the web wizard's [fields], or null without a name.
CharacterCard? newCharacterFromFields(Map<String, dynamic> fields) {
  final name = fields['name']?.toString().trim() ?? '';
  if (name.isEmpty) return null;

  List<String> asStrList(dynamic v) =>
      v is List ? v.map((e) => e.toString()).toList() : const [];

  // Always build extensions (even when realism is off) so configured values
  // survive — matching the desktop comment. The flag only gates runtime use.
  // The shared helper round-trips every realism + needs + verifier field so
  // web-created cards get the same baselines as the desktop creator.
  final fpExt = frontPorchFromFields(fields);

  return CharacterCard(
    name: name,
    description: fields['description']?.toString() ?? '',
    personality: fields['personality']?.toString() ?? '',
    scenario: fields['scenario']?.toString() ?? '',
    firstMessage: fields['firstMessage']?.toString() ?? '',
    mesExample: fields['mesExample']?.toString() ?? '',
    systemPrompt: fields['systemPrompt']?.toString() ?? '',
    postHistoryInstructions:
        fields['postHistoryInstructions']?.toString() ?? '',
    alternateGreetings: compactGreetingPairs(
      greetingSlotsFromRaw(fields['alternateGreetings']),
      parseGreetingSeeds(fields['greetingSeeds']),
    ).greetings,
    tags: asStrList(fields['tags']),
    lorebook: buildLorebookFromJson(fields['lorebook']),
    frontPorchExtensions: fpExt,
  );
}

/// Write [card] as a V2 PNG into the characters dir and add it to [repo].
/// Returns {id, name}, or null on failure.
Future<Map<String, dynamic>?> persistCharacterCard(
  CharacterRepository repo,
  StorageService storage,
  CharacterCard card, {
  List<int>? portraitBytes,
}) async {
  try {
    final charDir = storage.charactersDir;
    if (!charDir.existsSync()) charDir.createSync(recursive: true);
    final base = (card.name.isEmpty ? 'character' : card.name)
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .replaceAll(' ', '_');
    final safeName = base.replaceAll('_', '').isEmpty ? 'character' : base;
    card.imagePath = p.join(
      charDir.path,
      '${safeName}_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    // A rendered portrait (e.g. AI chargen) becomes the card's base image;
    // otherwise sourceImagePath stays null → V2CardService synthesizes a
    // placeholder avatar.
    String? sourceImagePath;
    if (portraitBytes != null && portraitBytes.isNotEmpty) {
      sourceImagePath = p.join(
        Directory.systemTemp.path,
        'fpa_portrait_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await File(sourceImagePath).writeAsBytes(portraitBytes);
    }
    await V2CardService().saveCardAsPng(card, card.imagePath!, sourceImagePath);
    await repo.addCharacter(card);
    return {'id': card.dbId, 'name': card.name};
  } catch (_) {
    return null;
  }
}
