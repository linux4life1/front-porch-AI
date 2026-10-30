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

import 'package:front_porch_ai/models/avatar_image.dart';
import 'package:front_porch_ai/models/greeting_realism_seed.dart';
import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/models/lorebook_export.dart';
import 'package:front_porch_ai/services/macro_resolver.dart';

import 'package:front_porch_ai/models/character/front_porch_extensions.dart';

export 'package:front_porch_ai/models/character/front_porch_extensions.dart';

class CharacterCard {
  String name;
  String description;
  String personality;
  String scenario;
  String firstMessage;
  String mesExample;
  String systemPrompt;
  String postHistoryInstructions;
  List<String> alternateGreetings;
  List<String> tags;
  String? imagePath;
  String? folderId;
  Lorebook? lorebook;
  List<String> worldNames;

  /// Lore-only worlds for new chats; [worldNames] then holds at most the
  /// Setting. Null means the card was never split: new chats seed
  /// [worldNames] the legacy way, where climate picks the Setting.
  List<String>? loreWorldNames;

  /// Per-character TTS voice assignment.
  ///
  /// This must be a valid voice key for the *currently selected* TTS engine
  /// (e.g. 'af_heart' for Kokoro, 'en_US-lessac-medium' for Piper, etc.).
  /// The UI now prevents (and warns about) cross-engine assignments.
  String? ttsVoice;

  /// V2 spec credits — round-trip so Stoop/Chub author names survive import.
  String creator;
  String creatorNotes;
  String characterVersion;
  String? dbId; // UUID primary key (runtime only, not serialized)
  DateTime?
  createdAt; // library "date added" from DB (runtime only, not serialized)
  FrontPorchExtensions? frontPorchExtensions; // V2.5 Realism Engine defaults
  Map<String, dynamic>?
  rawExtensions; // Preserve unknown third-party extension keys
  List<AvatarImage>? avatarImages; // Multiple avatar images for the character
  int primeAvatarIndex = 1; // 1-based index of the prime (default) avatar

  CharacterCard({
    this.dbId,
    this.creator = '',
    this.creatorNotes = '',
    this.characterVersion = '',
    required this.name,
    this.description = '',
    this.personality = '',
    this.scenario = '',
    this.firstMessage = '',
    this.mesExample = '',
    this.systemPrompt = '',
    this.postHistoryInstructions = '',
    this.alternateGreetings = const [],
    this.tags = const [],
    this.imagePath,
    this.folderId,
    this.lorebook,
    this.worldNames = const [],
    this.loreWorldNames,
    this.ttsVoice,
    this.frontPorchExtensions,
    this.rawExtensions,
    this.avatarImages,
    int? primeAvatarIndex,
  }) : primeAvatarIndex = primeAvatarIndex ?? 1;

  /// All greetings: primary first message + alternates
  List<String> get allGreetings {
    final greetings = <String>[firstMessage];
    greetings.addAll(alternateGreetings);
    return greetings.where((g) => g.trim().isNotEmpty).toList();
  }

  /// Replace [alternateGreetings] with rewritten [alts].
  ///
  /// Seeds not authored with the rewrite compact against empty so leftover
  /// source seeds cannot land on the new alts. A `copyWith` that only
  /// replaces alts must pass the compacted seeds (or `[]`) — never silently
  /// keep source [greetingSeeds]. Pass [authoredSeeds] when the rewrite
  /// wrote seeds alongside the new alts.
  void assignRewrittenAlternateGreetings(
    List<String> alts, {
    List<GreetingRealismSeed?>? authoredSeeds,
  }) {
    final paired = compactRewrittenGreetingAlts(alts, authoredSeeds);
    alternateGreetings = paired.greetings;
    final ext = frontPorchExtensions;
    if (ext != null) {
      ext.greetingSeeds = paired.seeds;
    } else if (paired.seeds.isNotEmpty) {
      frontPorchExtensions = FrontPorchExtensions(greetingSeeds: paired.seeds);
    }
  }

  Map<String, dynamic> toJson() {
    // Build extensions map: merge raw (third-party) keys with our namespace
    Map<String, dynamic>? extensions;
    if (frontPorchExtensions != null ||
        (rawExtensions != null && rawExtensions!.isNotEmpty)) {
      extensions = <String, dynamic>{};
      // Preserve any third-party extension keys first
      if (rawExtensions != null) extensions.addAll(rawExtensions!);
      // Add/overwrite our namespace
      if (frontPorchExtensions != null) {
        extensions['front_porch'] = frontPorchExtensions!.toJson();
      }
    }

    return {
      'name': name,
      'description': description,
      'personality': personality,
      'scenario': scenario,
      'first_mes': firstMessage,
      'mes_example': mesExample,
      'system_prompt': systemPrompt,
      'post_history_instructions': postHistoryInstructions,
      'alternate_greetings': alternateGreetings,
      'tags': tags,
      'character_book': lorebook == null
          ? null
          : encodeCharacterBook(lorebook!),
      'world_names': worldNames,
      'lore_world_names': ?loreWorldNames,
      if (ttsVoice != null) 'tts_voice': ttsVoice,
      if (creator.isNotEmpty) 'creator': creator,
      if (creatorNotes.isNotEmpty) 'creator_notes': creatorNotes,
      if (characterVersion.isNotEmpty) 'character_version': characterVersion,
      'extensions': ?extensions,
    };
  }

  String replacePlaceholders(String text, {String userName = 'You'}) {
    return MacroResolver().resolve(
      text,
      MacroContext(userName: userName, characterName: name),
    );
  }

  String get formattedDescription => replacePlaceholders(description);

  /// Whether this card has any Front Porch extensions configured.
  bool get hasFrontPorchExtensions => frontPorchExtensions != null;

  /// Whether this card is a Scene Guest (Lite NPC): a real library character
  /// that can join a 1:1 scene as its own bubble but carries no Realism/Needs
  /// state. Determined by `frontPorchExtensions.tier == 'lite'`.
  bool get isLite => frontPorchExtensions?.tier == 'lite';
}
