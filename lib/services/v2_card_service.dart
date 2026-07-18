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
import 'package:image/image.dart' as img;
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/utils/png_metadata_utils.dart';

class V2CardService {
  /// Shared implementation: loads a real image when possible, otherwise synthesizes
  /// a deterministic pleasant colored placeholder from the card name. Always returns
  /// a reasonably-sized image ready for embedding.
  Future<img.Image> _resolveOrCreateAvatar(
    CharacterCard card,
    String? sourceImagePath,
  ) async {
    img.Image? avatar;

    try {
      if (sourceImagePath != null) {
        final bytes = await File(sourceImagePath).readAsBytes();
        avatar = img.decodeImage(bytes);
      }
    } catch (e) {
      if (sourceImagePath != null) {
        rethrow;
      }
    }

    if (avatar == null) {
      // No source image available (character with no avatar, or broken path).
      // Generate a pleasant deterministic placeholder from the name so the
      // character is always visually distinct and never a pure black/gray box.
      final name = card.name.isNotEmpty ? card.name : 'Character';
      final hash = name.codeUnits.fold(0, (a, b) => a + b);
      final r = (80 + (hash % 120)).clamp(60, 200);
      final g = (70 + ((hash * 7) % 130)).clamp(60, 200);
      final b = (90 + ((hash * 13) % 110)).clamp(70, 190);

      avatar = img.Image(width: 400, height: 600);
      img.fill(avatar, color: img.ColorRgb8(r, g, b));
    }

    // Resize if too large to save space/time, optional but good practice
    if (avatar.width > 2048 || avatar.height > 2048) {
      avatar = img.copyResize(avatar, width: 1024);
    }

    return avatar;
  }

  Future<void> saveCardAsPng(
    CharacterCard card,
    String outputPath,
    String? sourceImagePath,
  ) async {
    final avatar = await _resolveOrCreateAvatar(card, sourceImagePath);

    // Encode character data to Base64
    // V2 Spec: 'chara' chunk containing base64 encoded JSON (V2 envelope)
    final jsonStr = jsonEncode(_buildCardV2Envelope(card));
    final base64Str = base64Encode(utf8.encode(jsonStr));

    // Add tEXt chunk
    avatar.textData ??= {};
    avatar.textData!['chara'] = base64Str;

    // Save to file
    final pngBytes = img.encodePng(avatar);
    await File(outputPath).writeAsBytes(pngBytes);
  }

  /// Returns the complete PNG bytes for a character card, with the V2 'chara'
  /// metadata embedded. When no sourceImagePath is supplied (or it fails to load),
  /// a deterministic placeholder image is synthesized from the card name.
  /// This is the preferred API for Group Card export when a member has no
  /// on-disk avatar at export time: the returned bytes can be base64-encoded
  /// directly into avatar_base64 so the exported group always contains 100%
  /// of its members with fully usable, later-extractable data.
  Future<List<int>> encodeCharacterCardToPngBytes(
    CharacterCard card,
    String? sourceImagePath,
  ) async {
    final avatar = await _resolveOrCreateAvatar(card, sourceImagePath);

    final jsonStr = jsonEncode(_buildCardV2Envelope(card));
    final base64Str = base64Encode(utf8.encode(jsonStr));

    avatar.textData ??= {};
    avatar.textData!['chara'] = base64Str;

    return img.encodePng(avatar);
  }

  Future<CharacterCard?> readCard(String path) async {
    final bytes = await File(path).readAsBytes();

    // Manual PNG chunk parsing - the `image` package doesn't reliably
    // extract tEXt/iTXt chunks from externally-created character cards.
    // We use the shared utility so group cards and future card types also benefit.
    String? charaData = PngMetadataUtils.extractTextChunk(bytes, 'chara');

    if (charaData == null) {
      // Fallback: try the image package approach
      try {
        final avatar = img.decodePng(bytes);
        if (avatar?.textData != null &&
            avatar!.textData!.containsKey('chara')) {
          charaData = avatar.textData!['chara']!;
        }
      } catch (e) {
        print('Image package fallback also failed: $e');
      }
    }

    if (charaData == null) return null;

    final jsonStr = utf8.decode(base64Decode(charaData));
    return parseCardJson(jsonStr, imagePath: path);
  }

  /// Reads a Character Card V2 from a plain `.json` file (the same JSON that is
  /// otherwise base64-embedded in a PNG `chara` chunk). No avatar is associated;
  /// callers persist with a generated placeholder image.
  Future<CharacterCard?> readCardFromJsonFile(String path) async {
    final jsonStr = await File(path).readAsString();
    return parseCardJson(jsonStr, imagePath: null);
  }

  /// Canonical Character Card V2 envelope wrapping [card]'s flat data map:
  /// `{ "spec": "chara_card_v2", "spec_version": "2.0", "data": { ... } }`.
  /// Every export path (PNG `chara` chunk + standalone `.json`) goes through
  /// this so all exports carry the standard `spec` marker and decode identically.
  /// `readCard`/`parseCardJson` accept both this envelope and legacy flat data.
  Map<String, dynamic> _buildCardV2Envelope(CharacterCard card) {
    return <String, dynamic>{
      'spec': 'chara_card_v2',
      'spec_version': '2.0',
      'data': card.toJson(),
    };
  }

  /// Writes [card] as a standalone Character Card V2 JSON file. The structure is
  /// identical to what is embedded in exported PNGs and what the importer accepts.
  Future<void> saveCardAsJson(CharacterCard card, String outputPath) async {
    const encoder = JsonEncoder.withIndent('  ');
    final jsonStr = encoder.convert(_buildCardV2Envelope(card));
    await File(outputPath).writeAsString(jsonStr);
  }

  /// Parses a Character Card V2 (or legacy flat V1) JSON string into a
  /// [CharacterCard]. Shared by both the PNG (`chara` chunk) and standalone
  /// `.json` import paths so the two stay byte-for-byte equivalent.
  CharacterCard? parseCardJson(String jsonStr, {String? imagePath}) {
    try {
      final jsonMap = jsonDecode(jsonStr);

      // Support both V1 and V2 card formats
      // V2 cards nest data under 'data', V1 cards have it at top level
      final data = jsonMap.containsKey('data') ? jsonMap['data'] : jsonMap;

      // Parse V2.5 extensions (front_porch namespace + raw third-party keys)
      FrontPorchExtensions? fpExtensions;
      Map<String, dynamic>? rawExtensions;
      final extensionsMap = data['extensions'] ?? jsonMap['extensions'];
      if (extensionsMap is Map<String, dynamic>) {
        if (extensionsMap.containsKey('front_porch') &&
            extensionsMap['front_porch'] is Map<String, dynamic>) {
          fpExtensions = FrontPorchExtensions.fromJson(
            extensionsMap['front_porch'],
          );
        }
        // Preserve all non-front_porch keys for round-trip safety
        final otherKeys = Map<String, dynamic>.from(extensionsMap)
          ..remove('front_porch');
        if (otherKeys.isNotEmpty) rawExtensions = otherKeys;
      }

      return CharacterCard(
        name: data['name'] ?? jsonMap['name'] ?? '',
        description: data['description'] ?? jsonMap['description'] ?? '',
        personality: data['personality'] ?? jsonMap['personality'] ?? '',
        scenario: data['scenario'] ?? jsonMap['scenario'] ?? '',
        firstMessage: data['first_mes'] ?? jsonMap['first_mes'] ?? '',
        mesExample: data['mes_example'] ?? jsonMap['mes_example'] ?? '',
        systemPrompt: data['system_prompt'] ?? jsonMap['system_prompt'] ?? '',
        postHistoryInstructions:
            data['post_history_instructions'] ??
            jsonMap['post_history_instructions'] ??
            '',
        alternateGreetings:
            (data['alternate_greetings'] ?? jsonMap['alternate_greetings']) !=
                null
            ? List<String>.from(
                data['alternate_greetings'] ?? jsonMap['alternate_greetings'],
              )
            : const [],
        tags: (data['tags'] ?? jsonMap['tags']) != null
            ? List<String>.from(data['tags'] ?? jsonMap['tags'])
            : const [],
        lorebook: (data['character_book'] ?? jsonMap['character_book']) != null
            ? Lorebook.fromJson(
                data['character_book'] ?? jsonMap['character_book'],
              )
            : null,
        worldNames: (data['world_names'] ?? jsonMap['world_names']) != null
            ? List<String>.from(data['world_names'] ?? jsonMap['world_names'])
            : const [],
        ttsVoice: data['tts_voice'] ?? jsonMap['tts_voice'],
        imagePath: imagePath,
        frontPorchExtensions: fpExtensions,
        rawExtensions: rawExtensions,
      );
    } catch (e) {
      print('Error parsing card data: $e');
      return null;
    }
  }
}
