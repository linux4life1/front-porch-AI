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

import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/byaf_chat.dart';
import 'package:front_porch_ai/services/persona/user_persona.dart';

export 'package:front_porch_ai/services/byaf_chat.dart'
    show ByafChat, ByafChatMessage, recommendByafPersonaId;

/// Preview data from a parsed .byaf file.
class ByafImportPreview {
  final String name;
  final String persona;
  final List<ByafLoreItem> loreItems;

  /// Every extracted archive image, in listed order. Index 0 is the portrait.
  final List<String> galleryImagePaths;

  /// The portrait's bytes, held in memory so the preview never opens the
  /// temp extract. On Windows an open or mapped file cannot be deleted, so a
  /// preview reading [extractedImagePath] would leave it behind on Cancel.
  final Uint8List? portraitBytes;
  final String? firstMessage;
  final String? narrative;
  final String? formattingInstructions;
  final List<String> exampleMessages; // raw example-dialogue texts
  /// Every turn of every chat, in archive order (counts and the persona
  /// guess read this; the import itself goes chat by chat via [chats]).
  final List<ByafChatMessage> messages;

  /// The first chat's sampler values.
  final Map<String, double> modelSettings;

  /// Every chat in the archive, one per Backyard scenario. Built from
  /// [firstMessage], [messages] and [modelSettings] when not given.
  final List<ByafChat> chats;

  ByafImportPreview({
    required this.name,
    required this.persona,
    this.loreItems = const [],
    this.galleryImagePaths = const [],
    this.portraitBytes,
    this.firstMessage,
    this.narrative,
    this.formattingInstructions,
    this.exampleMessages = const [],
    this.messages = const [],
    this.modelSettings = const {},
    List<ByafChat>? chats,
  }) : chats =
           chats ??
           [
             ByafChat(
               firstMessage: firstMessage,
               messages: messages,
               modelSettings: modelSettings,
             ),
           ];

  /// Portrait extract, or null when the archive carried no usable image.
  String? get extractedImagePath =>
      galleryImagePaths.isNotEmpty ? galleryImagePaths.first : null;
}

class ByafLoreItem {
  final String key;
  final String value;
  ByafLoreItem({required this.key, required this.value});
}

typedef TemporaryDirectoryProvider = Future<Directory> Function();

/// Service to parse and import Backyard AI .byaf archive files.
class ByafService {
  ByafService({TemporaryDirectoryProvider? getTemporaryDirectory})
    : _getTemporaryDirectory =
          getTemporaryDirectory ?? path_provider.getTemporaryDirectory;

  final TemporaryDirectoryProvider _getTemporaryDirectory;

  /// Every chat's history in a .byaf, without extracting any images (a
  /// batch import reads every file's chats before asking who the user was).
  /// Empty when the archive has no scenario or cannot be read.
  Future<List<ByafChatMessage>> readChat(String filePath) async {
    try {
      final archive = ZipDecoder().decodeBytes(
        await File(filePath).readAsBytes(),
      );
      final manifest = archive.findFile('manifest.json');
      if (manifest == null) return const [];
      final scenarios =
          (jsonDecode(utf8.decode(manifest.content as List<int>))
              as Map)['scenarios'];
      if (scenarios is! List) return const [];
      final out = <ByafChatMessage>[];
      for (final path in scenarios) {
        final scenario = archive.findFile(path.toString());
        if (scenario == null) continue;
        final json = jsonDecode(utf8.decode(scenario.content as List<int>));
        if (json is Map) out.addAll(parseByafChatMessages(json['messages']));
      }
      return out;
    } on Exception catch (e) {
      debugPrint('[BYAF] Could not read the chat in $filePath: $e');
      return const [];
    }
  }

  /// Parse a .byaf file and return a preview of the character data.
  Future<ByafImportPreview> parseByaf(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    // 1. Read manifest.json
    final manifestFile = archive.findFile('manifest.json');
    if (manifestFile == null) {
      throw FormatException('Invalid .byaf file: missing manifest.json');
    }
    final manifest =
        jsonDecode(utf8.decode(manifestFile.content as List<int>))
            as Map<String, dynamic>;

    // 2. Read character JSON
    final characterPaths =
        (manifest['characters'] as List?)?.cast<String>() ?? [];
    if (characterPaths.isEmpty) {
      throw FormatException('Invalid .byaf file: no characters defined');
    }
    final characterPath = characterPaths.first;
    final characterFile = archive.findFile(characterPath);
    if (characterFile == null) {
      throw FormatException(
        'Invalid .byaf file: character file not found at $characterPath',
      );
    }
    final charJson =
        jsonDecode(utf8.decode(characterFile.content as List<int>))
            as Map<String, dynamic>;

    // 3. Extract character fields
    final name = (charJson['displayName'] ?? charJson['name'] ?? 'Unknown')
        .toString();
    final persona = (charJson['persona'] ?? '').toString();

    // Parse lore items
    final loreItems = <ByafLoreItem>[];
    if (charJson['loreItems'] is List) {
      for (final item in charJson['loreItems']) {
        if (item is Map<String, dynamic>) {
          loreItems.add(
            ByafLoreItem(
              key: item['key']?.toString() ?? '',
              value: item['value']?.toString() ?? '',
            ),
          );
        }
      }
    }

    // 4. Extract the archive's image set. First listed image is the
    // portrait; the rest become gallery looks at confirm time.
    final galleryImagePaths = <String>[];
    Uint8List? portraitBytes;
    if (charJson['images'] is List && (charJson['images'] as List).isNotEmpty) {
      final tempDir = await _getTemporaryDirectory();
      if (!await tempDir.exists()) await tempDir.create(recursive: true);
      final rawImages = charJson['images'] as List;
      for (var i = 0; i < rawImages.length; i++) {
        final img = rawImages[i];
        if (img is! Map) continue;
        final imgRelPath = img['path']?.toString();
        if (imgRelPath == null || imgRelPath.isEmpty) continue;
        final charDir = path.dirname(characterPath);
        final fullImgPath = '$charDir/$imgRelPath';
        final imgFile = archive.findFile(fullImgPath);
        if (imgFile == null) continue;
        final ext = path.extension(imgRelPath).isNotEmpty
            ? path.extension(imgRelPath)
            : '.png';
        final tempPath =
            '${tempDir.path}/byaf_import_${i}_${DateTime.now().millisecondsSinceEpoch}$ext';
        final bytes = Uint8List.fromList(imgFile.content as List<int>);
        await File(tempPath).writeAsBytes(bytes);
        portraitBytes ??= bytes;
        galleryImagePaths.add(tempPath);
      }
    }

    // 5. Read scenarios: each one is a separate chat. The card's own
    // fields (narrative, formatting, examples) come from the first.
    String? narrative;
    String? formattingInstructions;
    final exampleMessages = <String>[];
    final chats = <ByafChat>[];
    final scenarioPaths = (manifest['scenarios'] as List?) ?? const [];
    for (final scenarioPath in scenarioPaths) {
      final scenarioFile = archive.findFile(scenarioPath.toString());
      if (scenarioFile == null) continue;
      final scenarioJson = jsonDecode(
        utf8.decode(scenarioFile.content as List<int>),
      );
      if (scenarioJson is! Map) continue;
      if (chats.isEmpty) {
        narrative = scenarioJson['narrative']?.toString();
        formattingInstructions = scenarioJson['formattingInstructions']
            ?.toString();
        // Example dialogue: BYAF spec items are {characterID, text}. The
        // speaker attribution (including any #{user}:/#{character}: turn
        // markers Backyard authors used) lives inside the text itself.
        final examples = scenarioJson['exampleMessages'];
        if (examples is List) {
          for (final ex in examples) {
            final text = ex is Map ? ex['text']?.toString() ?? '' : '';
            if (text.isNotEmpty) exampleMessages.add(text);
          }
        }
      }
      chats.add(parseByafScenario(scenarioJson));
    }
    final first = chats.isEmpty ? const ByafChat() : chats.first;

    return ByafImportPreview(
      name: name,
      persona: persona,
      loreItems: loreItems,
      galleryImagePaths: galleryImagePaths,
      portraitBytes: portraitBytes,
      firstMessage: first.firstMessage,
      narrative: narrative,
      formattingInstructions: formattingInstructions,
      exampleMessages: exampleMessages,
      messages: [for (final c in chats) ...c.messages],
      modelSettings: first.modelSettings,
      chats: chats.isEmpty ? null : chats,
    );
  }

  String _convertPlaceholders(String text) => convertByafPlaceholders(text);

  /// Build a V2 `mes_example` block from BYAF example-dialogue texts.
  ///
  /// Backyard authors example dialogue as `#{character}:` / `#{user}:` turns;
  /// after placeholder conversion those become `#{{char}}:` / `#{{user}}:`,
  /// so the leading `#` turn marker is stripped to match V2 conventions. Texts
  /// with no speaker marker at all are attributed to the character. The block
  /// opens with `<START>` per the V2 spec (the prompt builder renders
  /// mes_example verbatim).
  String _buildMesExample(List<String> exampleMessages) {
    if (exampleMessages.isEmpty) return '';
    final lines = <String>['<START>'];
    for (final raw in exampleMessages) {
      var text = _convertPlaceholders(raw)
          .replaceAll('#{{char}}:', '{{char}}:')
          .replaceAll('#{{user}}:', '{{user}}:');
      if (!text.contains('{{char}}:') && !text.contains('{{user}}:')) {
        text = '{{char}}: $text';
      }
      lines.add(text.trim());
    }
    return lines.join('\n');
  }

  /// Map the scenario's Backyard sampler values onto per-session overrides.
  /// Returns null when the archive carried no model settings.
  ChatGenerationSettings? toGenerationSettings(ByafImportPreview preview) =>
      _samplerOverrides(preview.modelSettings);

  ChatGenerationSettings? _samplerOverrides(Map<String, double> s) {
    if (s.isEmpty) return null;
    return ChatGenerationSettings(
      temperature: s['temperature'],
      minP: s['minP'],
      topP: s['topP'],
      topK: s['topK']?.toInt(),
      repeatPenalty: s['repeatPenalty'],
      repeatPenaltyTokens: s['repeatLastN']?.toInt(),
    );
  }

  /// Convert a ByafImportPreview into a CharacterCard for import.
  CharacterCard toCharacterCard(ByafImportPreview preview) {
    // Convert lore items to Lorebook (with placeholder conversion)
    Lorebook? lorebook;
    if (preview.loreItems.isNotEmpty) {
      lorebook = Lorebook(
        entries: preview.loreItems
            .map(
              (item) => LorebookEntry(
                name: item.key,
                key: item.key,
                content: _convertPlaceholders(item.value),
                enabled: true,
              ),
            )
            .toList(),
      );
    }

    return CharacterCard(
      name: preview.name,
      description: _convertPlaceholders(preview.persona),
      personality: '',
      scenario: _convertPlaceholders(preview.narrative ?? ''),
      firstMessage: _convertPlaceholders(preview.firstMessage ?? ''),
      mesExample: _buildMesExample(preview.exampleMessages),
      systemPrompt: _convertPlaceholders(preview.formattingInstructions ?? ''),
      postHistoryInstructions: '',
      alternateGreetings: [],
      tags: [],
      imagePath: preview.extractedImagePath,
      lorebook: lorebook,
    );
  }

  /// Save the character card as a PNG with embedded V2 metadata.
  /// Returns the saved file path.
  /// [charactersDirPath] is the absolute path to the Characters directory.
  Future<String> saveCharacterPng(
    CharacterCard card, {
    String? charactersDirPath,
  }) async {
    final String charDirPath;
    if (charactersDirPath != null) {
      charDirPath = charactersDirPath;
    } else {
      final directory = await path_provider.getApplicationDocumentsDirectory();
      charDirPath = '${directory.path}/KoboldManager/Characters';
    }
    final charDir = Directory(charDirPath);
    if (!await charDir.exists()) {
      await charDir.create(recursive: true);
    }

    final safeName = card.name
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '')
        .replaceAll(' ', '_');
    final outputPath =
        '${charDir.path}/${safeName}_${DateTime.now().millisecondsSinceEpoch}.png';

    // If we have an extracted image, copy it as the base PNG
    if (card.imagePath != null && File(card.imagePath!).existsSync()) {
      await File(card.imagePath!).copy(outputPath);
    } else {
      await _createPlaceholderPng(outputPath);
    }

    return outputPath;
  }

  /// Create the imported chats: one session per Backyard scenario that has
  /// a history (when [includeMessages]). Passing [genSettings] applies
  /// Backyard's sampler values, each chat its own scenario's (falling back
  /// to [genSettings]), stored on the session's generation_settings column
  /// so resuming or forking samples like Backyard did; with no history to
  /// import it still makes one empty session carrying [genSettings].
  /// [persona] is who the user's lines were written as; null keeps "User".
  /// Returns how many chats were written.
  Future<int> importSession(
    AppDatabase db,
    ByafImportPreview preview,
    CharacterCard importedCard, {
    bool includeMessages = true,
    ChatGenerationSettings? genSettings,
    UserPersona? persona,
  }) async {
    final characterId = importedCard.dbId;
    if (characterId == null) return 0;
    final chats = includeMessages
        ? [
            for (final c in preview.chats)
              if (c.messages.isNotEmpty) c,
          ]
        : const <ByafChat>[];
    // Session ids are timestamps (the app's convention). Several chats, or
    // a fast batch of files, land in the same millisecond: skip taken ids.
    var next = DateTime.now().millisecondsSinceEpoch;
    Future<String> freshId() async {
      while (await db.getSessionById('$next') != null) {
        next++;
      }
      return '${next++}';
    }

    if (chats.isEmpty) {
      if (genSettings == null) return 0;
      await db.insertSession(
        SessionsCompanion.insert(
          id: await freshId(),
          characterId: Value(characterId),
          name: const Value('Imported from Backyard AI'),
          generationSettings: Value(genSettings.toJsonString()),
          userPersonaId: Value(persona?.id),
        ),
      );
      return 0;
    }
    for (var i = 0; i < chats.length; i++) {
      final chat = chats[i];
      final sessionId = await freshId();
      final settings = genSettings == null
          ? null
          : _samplerOverrides(chat.modelSettings) ?? genSettings;
      await db.insertSession(
        SessionsCompanion.insert(
          id: sessionId,
          characterId: Value(characterId),
          name: Value(
            chat.title ??
                (chats.length == 1
                    ? 'Imported from Backyard AI'
                    : 'Imported from Backyard AI (${i + 1})'),
          ),
          generationSettings: Value(settings?.toJsonString()),
          userPersonaId: Value(persona?.id),
        ),
      );
      await db.insertMessages(
        byafSessionRows(
          sessionId: sessionId,
          messages: chat.messages,
          characterName: importedCard.name,
          persona: persona ?? UserPersona(id: '', name: 'User'),
          firstMessage: chat.firstMessage,
        ),
      );
    }
    return chats.length;
  }

  Future<void> _createPlaceholderPng(String outputPath) async {
    // Minimal blank placeholder written when a BYAF card carries no image.
    final pngBytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAEUlEQVR42mP4/vU9VsQwtCQAafG2wXWW5mYAAAAASUVORK5CYII=',
    );
    await File(outputPath).writeAsBytes(pngBytes);
  }
}
