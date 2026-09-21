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

part of 'character_facade.dart';

/// Write half of the web character adapter: update, create, persist, import.
extension CharacterFacadeImport on CharacterFacade {
  Future<bool> _updateImpl(String id, Map<String, dynamic> fields) async {
    final repo = _repo;
    if (repo == null) return false;
    final card = cardByDbId(id);
    if (card == null) return false;

    String pick(String key, String current) => fields.containsKey(key)
        ? (fields[key]?.toString() ?? current)
        : current;
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
    card.frontPorchExtensions = frontPorchFromFields(
      fields,
      base: card.frontPorchExtensions,
    );

    await repo.updateCharacter(card);
    return true;
  }

  Future<Map<String, dynamic>?> _createImpl(Map<String, dynamic> fields) async {
    final repo = _repo;
    if (repo == null) return null;
    final name = fields['name']?.toString().trim() ?? '';
    if (name.isEmpty) return null;

    List<String> asStrList(dynamic v) =>
        v is List ? v.map((e) => e.toString()).toList() : const [];

    // Always build extensions (even when realism is off) so configured values
    // survive — matching the desktop comment. The flag only gates runtime use.
    // The shared helper round-trips every realism + needs + verifier field so
    // web-created cards get the same baselines as the desktop creator.
    final fpExt = frontPorchFromFields(fields);

    final card = CharacterCard(
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

    return persistNewCard(card);
  }

  Future<Map<String, dynamic>?> _persistNewCardImpl(
    CharacterCard card, {
    List<int>? portraitBytes,
  }) async {
    final repo = _repo;
    if (repo == null) return null;
    try {
      final charDir = _storage.charactersDir;
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
      await V2CardService().saveCardAsPng(
        card,
        card.imagePath!,
        sourceImagePath,
      );
      await repo.addCharacter(card);
      return {'id': card.dbId, 'name': card.name};
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _importBytesImpl(
    List<int> bytes,
    String filename, {
    String collision = 'keepBoth',
    String? replaceId,
  }) async {
    final repo = _repo;
    if (repo == null) return null;
    final ext = p.extension(filename).isNotEmpty
        ? p.extension(filename)
        : '.png';
    final tmp = File(
      p.join(
        Directory.systemTemp.path,
        'fpa_import_${DateTime.now().microsecondsSinceEpoch}$ext',
      ),
    );
    try {
      await tmp.writeAsBytes(bytes, flush: true);

      if (filename.toLowerCase().endsWith('.byaf')) {
        return await _importByafFile(
          tmp,
          filename,
          collision: collision,
          replaceId: replaceId,
        );
      }

      // Peek identity for collision policy (same rules as desktop single-import).
      CharacterCard? peeked;
      try {
        final isJson = tmp.path.toLowerCase().endsWith('.json');
        final v2 = V2CardService();
        peeked = isJson
            ? await v2.readCardFromJsonFile(tmp.path)
            : await v2.readCard(tmp.path);
      } catch (_) {
        peeked = null;
      }
      final name = peeked?.name ?? p.basenameWithoutExtension(filename);
      final stableId = peeked?.frontPorchExtensions?.stableId;
      final stableMatch = repo.findByStableId(stableId);

      if (stableMatch == null) {
        final existing = repo.charactersWithName(name);
        if (existing.isNotEmpty) {
          if (collision == 'ask') {
            return {
              'status': 'name_collision',
              'name': name,
              'existing': [
                for (final c in existing) {'id': c.dbId, 'name': c.name},
              ],
            };
          }
          if (collision == 'replace') {
            CharacterCard? target;
            if (replaceId != null && replaceId.isNotEmpty) {
              for (final c in existing) {
                if (c.dbId == replaceId) {
                  target = c;
                  break;
                }
              }
            }
            target ??= existing.first;
            final card = await repo.importCharacter(
              tmp,
              forceReplaceTarget: target,
            );
            if (card == null) return null;
            return {'id': card.dbId, 'name': card.name, 'replaced': true};
          }
          // keepBoth: fall through to plain import (insert)
        }
      }

      final card = await repo.importCharacter(tmp);
      if (card == null) return null;
      return {'id': card.dbId, 'name': card.name};
    } catch (_) {
      return null;
    } finally {
      try {
        if (tmp.existsSync()) await tmp.delete();
      } catch (_) {}
    }
  }
}
