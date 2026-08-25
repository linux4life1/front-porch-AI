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
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/utils/utils.dart';

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
    } catch (_) {
      // Corrupt / non-image bytes (or a format decoder that throws): fall
      // through to the synthetic placeholder rather than failing the whole
      // card write. Callers that bootstrap a portrait then re-embed via
      // updateCharacter must not lose extensions over a bad decode.
      avatar = null;
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
    // Seek through the chunk table first. The card JSON is a few KB in a header
    // chunk, but the file around it is megabytes of artwork — opening a library
    // of 120 cards used to pull ~142 MB off disk (501-743 ms measured, and
    // worse on Windows where AV inspects every megabyte read). Skipping IDAT
    // measured ~9x faster and, unlike the byte path, does not get slower as
    // people use higher-resolution art.
    String? charaData = await PngMetadataUtils.extractTextChunkFromFile(
      path,
      'chara',
    );

    if (charaData != null) {
      return parseCardJson(
        utf8.decode(base64Decode(charaData)),
        imagePath: path,
      );
    }

    // Fall back to the whole-file paths for anything the chunk walk could not
    // satisfy — a malformed chunk table, or metadata the `image` package can
    // reach but our parser cannot. Unchanged from before, so no card that
    // loaded yesterday stops loading today; it just no longer runs for the
    // overwhelmingly common case.
    final bytes = await File(path).readAsBytes();

    // Manual PNG chunk parsing - the `image` package doesn't reliably
    // extract tEXt/iTXt chunks from externally-created character cards.
    // We use the shared utility so group cards and future card types also benefit.
    charaData = PngMetadataUtils.extractTextChunk(bytes, 'chara');

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
      final decoded = jsonDecode(jsonStr);
      // Not an object at all (a bare array/string) is genuinely "not a card" —
      // stay null so the importer's own fallback decides what to do.
      if (decoded is! Map) return null;
      final jsonMap = Map<String, dynamic>.from(decoded);

      // Support both V1 and V2 card formats
      // V2 cards nest data under 'data', V1 cards have it at top level
      final nestedData = jsonMap['data'];
      final data = nestedData is Map
          ? Map<String, dynamic>.from(nestedData)
          : jsonMap;

      // THE INPUT IS A STRANGER'S UPLOAD — same doctrine as GroupCard.fromJson.
      // Every read below is type-CHECKED instead of implicitly cast, because an
      // implicit cast on ONE wrong-typed field ("tags": ["romance", null], a
      // numeric name, a bare-string tags list) threw out of this whole factory,
      // and the file importer then persisted a filename-named EMPTY character
      // while telling the user the import succeeded.
      String text(Object? v) =>
          (v == null || v is Map || v is List) ? '' : v.toString();
      List<String> strList(Object? v) {
        if (v is List) {
          return v.whereType<Object>().map((e) => e.toString()).toList();
        }
        return v is String && v.isNotEmpty ? [v] : const [];
      }

      final rawAlts = greetingSlotsFromRaw(
        data['alternate_greetings'] ?? jsonMap['alternate_greetings'],
      );

      // Parse V2.5 extensions (front_porch namespace + raw third-party keys)
      FrontPorchExtensions? fpExtensions;
      Map<String, dynamic>? rawExtensions;
      final extensionsMap = data['extensions'] ?? jsonMap['extensions'];
      if (extensionsMap is Map<String, dynamic>) {
        final fp = extensionsMap['front_porch'];
        if (fp is Map) {
          try {
            fpExtensions = FrontPorchExtensions.fromJson(
              Map<String, dynamic>.from(fp),
              alternateGreetings: rawAlts,
            );
          } catch (e) {
            print('Card parse: ignoring malformed front_porch extensions: $e');
          }
        }
        // Preserve all non-front_porch keys for round-trip safety
        final otherKeys = Map<String, dynamic>.from(extensionsMap)
          ..remove('front_porch');
        if (otherKeys.isNotEmpty) rawExtensions = otherKeys;
      }

      final book = data['character_book'] ?? jsonMap['character_book'];
      Lorebook? lorebook;
      if (book is Map) {
        try {
          lorebook = Lorebook.fromJson(Map<String, dynamic>.from(book));
        } catch (e) {
          print('Card parse: ignoring malformed character_book: $e');
        }
      }
      final voice = data['tts_voice'] ?? jsonMap['tts_voice'];

      return CharacterCard(
        name: text(data['name'] ?? jsonMap['name']),
        description: text(data['description'] ?? jsonMap['description']),
        personality: text(data['personality'] ?? jsonMap['personality']),
        scenario: text(data['scenario'] ?? jsonMap['scenario']),
        firstMessage: text(data['first_mes'] ?? jsonMap['first_mes']),
        mesExample: text(data['mes_example'] ?? jsonMap['mes_example']),
        systemPrompt: text(data['system_prompt'] ?? jsonMap['system_prompt']),
        postHistoryInstructions: text(
          data['post_history_instructions'] ??
              jsonMap['post_history_instructions'],
        ),
        alternateGreetings: compactGreetingPairs(
          rawAlts,
          fpExtensions?.greetingSeeds ?? const [],
        ).greetings,
        tags: strList(data['tags'] ?? jsonMap['tags']),
        lorebook: lorebook,
        worldNames: strList(data['world_names'] ?? jsonMap['world_names']),
        ttsVoice: voice is String ? voice : null,
        creator: text(data['creator'] ?? jsonMap['creator']),
        creatorNotes: text(data['creator_notes'] ?? jsonMap['creator_notes']),
        characterVersion: text(
          data['character_version'] ?? jsonMap['character_version'],
        ),
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
