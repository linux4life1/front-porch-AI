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
import 'package:drift/drift.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/database/database.dart';

/// Preview data from a parsed .byaf file.
class ByafImportPreview {
  final String name;
  final String persona;
  final List<ByafLoreItem> loreItems;
  final List<String> galleryImagePaths; // Every image in the BYAF archive (first is the portrait)
  final String? firstMessage;
  final String? narrative;
  final String? formattingInstructions;
  final List<String> exampleMessages; // raw example-dialogue texts
  final List<ByafChatMessage> messages;
  final Map<String, double> modelSettings;

  ByafImportPreview({
    required this.name,
    required this.persona,
    this.loreItems = const [],
    this.galleryImagePaths = const [],
    this.firstMessage,
    this.narrative,
    this.formattingInstructions,
    this.exampleMessages = const [],
    this.messages = const [],
    this.modelSettings = const {},
  });
}

class ByafLoreItem {
  final String key;
  final String value;
  ByafLoreItem({required this.key, required this.value});
}

class ByafChatMessage {
  final String type; // 'ai' or 'human'
  final String text;
  final DateTime? createdAt;
  ByafChatMessage({required this.type, required this.text, this.createdAt});
}

/// Service to parse and import Backyard AI .byaf archive files.
class ByafService {
  Future<List<String>> _extractGalleryImages(
    Archive archive,
    String characterPath,
    List<dynamic> rawImages,
  ) async {
    final galleryPaths = <String>[];
    if (rawImages.isEmpty) return galleryPaths;

    final tempDir = await Directory.systemTemp.createTemp('byaf_import_');

    final charDir = path.dirname(characterPath);
    for (int index = 0; index < rawImages.length; index++) {
      final item = rawImages[index];
      if (item is! Map<String, dynamic>) continue;
      final relPath = item['path']?.toString();
      if (relPath == null || relPath.trim().isEmpty) continue;

      final fullImgPath = charDir.isEmpty ? relPath : '$charDir/$relPath';
      final imgFile = archive.findFile(fullImgPath);
      if (imgFile == null) continue;

      final extension = path.extension(relPath).isNotEmpty
          ? path.extension(relPath)
          : '.png';
      final tempPath =
          '${tempDir.path}/byaf_import_${DateTime.now().millisecondsSinceEpoch}_$index$extension';
      await File(tempPath).writeAsBytes(imgFile.content as List<int>);
      galleryPaths.add(tempPath);
    }
    return galleryPaths;
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

    // 4. Extract the archive's image set. The first image remains the
    // portrait/cover, and the rest become gallery "looks" for the imported card.
    final galleryImagePaths = charJson['images'] is List
        ? await _extractGalleryImages(
            archive,
            characterPath,
            (charJson['images'] as List).cast<dynamic>(),
          )
        : <String>[];

    // 5. Read scenarios
    String? firstMessage;
    String? narrative;
    String? formattingInstructions;
    final exampleMessages = <String>[];
    final messages = <ByafChatMessage>[];
    final modelSettings = <String, double>{};

    final scenarioPaths =
        (manifest['scenarios'] as List?)?.cast<String>() ?? [];
    if (scenarioPaths.isNotEmpty) {
      final scenarioFile = archive.findFile(scenarioPaths.first);
      if (scenarioFile != null) {
        final scenarioJson =
            jsonDecode(utf8.decode(scenarioFile.content as List<int>))
                as Map<String, dynamic>;

        narrative = scenarioJson['narrative']?.toString();
        formattingInstructions = scenarioJson['formattingInstructions']
            ?.toString();

        // First message
        if (scenarioJson['firstMessages'] is List &&
            (scenarioJson['firstMessages'] as List).isNotEmpty) {
          final fm = (scenarioJson['firstMessages'] as List).first;
          if (fm is Map<String, dynamic>) {
            firstMessage = fm['text']?.toString();
          }
        }

        // Example dialogue: BYAF spec items are {characterID, text}. The
        // speaker attribution (including any #{user}:/#{character}: turn
        // markers Backyard authors used) lives inside the text itself.
        if (scenarioJson['exampleMessages'] is List) {
          for (final ex in scenarioJson['exampleMessages'] as List) {
            if (ex is Map<String, dynamic>) {
              final text = ex['text']?.toString() ?? '';
              if (text.isNotEmpty) exampleMessages.add(text);
            }
          }
        }

        // Model settings
        for (final key in [
          'temperature',
          'minP',
          'topP',
          'topK',
          'repeatPenalty',
          'repeatLastN',
        ]) {
          if (scenarioJson[key] is num) {
            modelSettings[key] = (scenarioJson[key] as num).toDouble();
          }
        }
        // Backyard disables min-p via a separate flag rather than zeroing the
        // value; carry that semantics over (0 = disabled downstream).
        if (scenarioJson['minPEnabled'] == false) {
          modelSettings['minP'] = 0.0;
        }

        // Chat history
        if (scenarioJson['messages'] is List) {
          for (final msg in scenarioJson['messages']) {
            if (msg is Map<String, dynamic>) {
              final type = msg['type']?.toString() ?? '';
              String text = '';
              DateTime? createdAt;

              if (type == 'human') {
                text = msg['text']?.toString() ?? '';
                createdAt = DateTime.tryParse(
                  msg['createdAt']?.toString() ?? '',
                );
              } else if (type == 'ai') {
                // AI messages have outputs array — use first/active one
                if (msg['outputs'] is List &&
                    (msg['outputs'] as List).isNotEmpty) {
                  final output = (msg['outputs'] as List).first;
                  if (output is Map<String, dynamic>) {
                    text = output['text']?.toString() ?? '';
                    createdAt = DateTime.tryParse(
                      output['createdAt']?.toString() ?? '',
                    );
                  }
                }
              }

              if (text.isNotEmpty) {
                messages.add(
                  ByafChatMessage(type: type, text: text, createdAt: createdAt),
                );
              }
            }
          }
        }
      }
    }

    return ByafImportPreview(
      name: name,
      persona: persona,
      loreItems: loreItems,
      galleryImagePaths: galleryImagePaths,
      firstMessage: firstMessage,
      narrative: narrative,
      formattingInstructions: formattingInstructions,
      exampleMessages: exampleMessages,
      messages: messages,
      modelSettings: modelSettings,
    );
  }

  /// Convert Backyard AI placeholders {character}/{user} to V2 spec {{char}}/{{user}}.
  String _convertPlaceholders(String text) {
    return text
        .replaceAll('{character}', '{{char}}')
        .replaceAll('{Character}', '{{char}}')
        .replaceAll('{CHARACTER}', '{{char}}')
        .replaceAll('{user}', '{{user}}')
        .replaceAll('{User}', '{{user}}')
        .replaceAll('{USER}', '{{user}}');
  }

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
  ChatGenerationSettings? toGenerationSettings(ByafImportPreview preview) {
    final s = preview.modelSettings;
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
      imagePath: preview.galleryImagePaths.isNotEmpty
          ? preview.galleryImagePaths.first
          : null,
      lorebook: lorebook,
    );
  }

  /// Add the remaining BYAF images to the imported character's avatar gallery.
  /// The first image stays as the portrait on the card; subsequent images are
  /// stored as gallery looks so the user can browse the full BYAF pack.
  Future<void> importGalleryImages({
    required CharacterRepository repo,
    required CharacterCard importedCard,
    required ByafImportPreview preview,
  }) async {
    if (importedCard.dbId == null || preview.galleryImagePaths.length <= 1) {
      return;
    }

    for (int i = 1; i < preview.galleryImagePaths.length; i++) {
      final imagePath = preview.galleryImagePaths[i];
      if (!File(imagePath).existsSync()) continue;
      final bytes = await File(imagePath).readAsBytes();
      await repo.addLook(importedCard.dbId!, importedCard.name, bytes);
    }
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
      final directory = await getApplicationDocumentsDirectory();
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

  /// Create the imported chat session: BYAF message history (when
  /// [includeMessages]) and/or Backyard sampler overrides ([genSettings],
  /// stored on the session's generation_settings column so resuming the chat
  /// — or forking it — samples like Backyard did). No-ops when there is
  /// nothing to persist.
  Future<void> importSession(
    AppDatabase db,
    ByafImportPreview preview,
    CharacterCard importedCard, {
    bool includeMessages = true,
    ChatGenerationSettings? genSettings,
  }) async {
    final withMessages = includeMessages && preview.messages.isNotEmpty;
    final settingsJson = genSettings?.toJsonString();
    if ((!withMessages && settingsJson == null) || importedCard.dbId == null) {
      return;
    }

    // Create a session ID (timestamp-based, matching the app's convention)
    final sessionId = DateTime.now().millisecondsSinceEpoch.toString();

    // Insert the session
    await db.insertSession(
      SessionsCompanion.insert(
        id: sessionId,
        characterId: Value(importedCard.dbId!),
        name: Value('Imported from Backyard AI'),
        generationSettings: Value(settingsJson),
      ),
    );

    if (!withMessages) return;

    // Build message list
    final msgs = <MessagesCompanion>[];
    for (int i = 0; i < preview.messages.length; i++) {
      final msg = preview.messages[i];
      final isUser = msg.type == 'human';
      final sender = isUser ? 'User' : importedCard.name;

      msgs.add(
        MessagesCompanion(
          sessionId: Value(sessionId),
          position: Value(i),
          sender: Value(sender),
          isUser: Value(isUser),
          swipes: Value(jsonEncode([_convertPlaceholders(msg.text)])),
          swipeIndex: Value(0),
        ),
      );
    }

    // Batch insert all messages
    await db.insertMessages(msgs);
  }

  Future<void> _createPlaceholderPng(String outputPath) async {
    // Minimal blank placeholder written when a BYAF card carries no image.
    final pngBytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAEUlEQVR42mP4/vU9VsQwtCQAafG2wXWW5mYAAAAASUVORK5CYII=',
    );
    await File(outputPath).writeAsBytes(pngBytes);
  }
}
