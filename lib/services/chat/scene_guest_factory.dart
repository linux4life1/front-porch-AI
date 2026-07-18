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

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/services/character_gen_service.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/chat/chat_command_handler.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/v2_card_service.dart';

/// Mints Scene Guests (Lite NPCs): generates a character from a name + concept,
/// tags it `tier == 'lite'` (no Realism/Needs state), and persists it via the
/// canonical path (PNG with embedded extensions, then repo insert).
///
/// Extracted from `ChatService` so the god file stays thin; it depends only on
/// standalone services. Returns a [GuestMintResult] for the caller to report.
class SceneGuestFactory {
  const SceneGuestFactory(this._repository, this._storage);

  final CharacterRepository _repository;
  final StorageService _storage;

  /// Generate + mark-lite + persist a guest. [host] supplies scene context
  /// (scenario / NSFW intent). [llm] must already be ready.
  ///
  /// [sceneGrounding] is the actual in-chat narration about this character
  /// (the lines where the host portrayed them). It is the single most important
  /// input: without it the generator invents a generic character with nothing
  /// in common with how they appeared in the scene. When present it becomes the
  /// dominant part of the build concept so the card matches the portrayal.
  Future<GuestMintResult> mint({
    required String name,
    required String concept,
    required LLMService? llm,
    required CharacterCard? host,
    String sceneGrounding = '',
    void Function(String step)? onStatus,
  }) async {
    if (llm == null || !llm.isReady) {
      return const GuestMintResult.failure('the LLM backend is not ready');
    }

    CharacterCard? card;
    try {
      card = await CharacterGenService(llm).generateCharacter(
        name: name,
        concept: _buildGroundedConcept(name, concept, sceneGrounding),
        // Surface generation sub-steps (profile → interview → dialogue → …) so
        // the chat banner can show progress instead of a single static spinner.
        onStatus: onStatus,
        // IMPORTANT: do NOT pass the host's scenario as `scenario` — that field
        // is written onto the card VERBATIM (character_gen_service: "use it
        // verbatim"), which made the guest's own card literally describe the
        // host's story (the "model thinks Vanessa IS Rachel" confusion). Pass it
        // only as ephemeral `worldLore` so the guest fits the setting without
        // adopting the host's identity. The guest's scenario is cleared below.
        worldLore: host?.scenario,
        // Inherit the host's NSFW cooldown intent as the best available signal
        // that this scene allows mature content.
        nsfwEnabled: host?.frontPorchExtensions?.nsfwCooldownEnabled ?? false,
      );
    } catch (e) {
      debugPrint('[SceneGuest:mint] generation failed: $e');
      return GuestMintResult.failure('$e');
    }
    if (card == null) {
      return const GuestMintResult.failure(
        'the LLM did not produce a valid card',
      );
    }
    if (card.description.isEmpty && concept.isNotEmpty) {
      card.description = concept;
    }

    // A Scene Guest is a drop-in visitor — it has NO standalone scenario of its
    // own; it joins whatever scene the host is running at turn time. Clearing
    // this guarantees the guest's prompt can never frame it as the protagonist
    // of someone else's story (see the worldLore note above). Identity comes
    // from description + personality only.
    card.scenario = '';

    // Mark as a lite Scene Guest (no Realism/Needs state).
    final ext = (card.frontPorchExtensions ?? FrontPorchExtensions()).copyWith(
      tier: 'lite',
    );
    card.frontPorchExtensions = ext;

    try {
      final charDir = _storage.charactersDir;
      if (!charDir.existsSync()) charDir.createSync(recursive: true);
      final epoch = DateTime.now().millisecondsSinceEpoch;
      var safeName = name.replaceAll(RegExp(r'[^\w\s]'), '').replaceAll(' ', '_');
      // Dart's \w is ASCII-only, so a purely non-Latin or symbol name (e.g.
      // "美咲" or "***") strips to empty → a nameless "_<epoch>.png". Fall back
      // to a stable prefix so the filename is never degenerate.
      if (safeName.replaceAll('_', '').isEmpty) safeName = 'guest';
      final imagePath = p.join(charDir.path, '${safeName}_$epoch.png');
      card.imagePath = imagePath;
      ext.ensureStableId();
      await V2CardService().saveCardAsPng(card, imagePath, null);
      await _repository.addCharacter(card);
    } catch (e) {
      debugPrint('[SceneGuest:mint] persist failed: $e');
      return GuestMintResult.failure(
        'saved generation but failed to store: $e',
      );
    }
    if (card.dbId == null) {
      return const GuestMintResult.failure('created card has no id');
    }
    return GuestMintResult.success(card);
  }

  /// Fold the in-chat portrayal of [name] into the build concept so the
  /// generated card reflects how the character actually appeared in the scene,
  /// not a generic invention from a bare name. The excerpts are dominated by
  /// other characters (the narrator + the user) too, so the instruction is
  /// explicit: build ONLY [name] from what describes them, ignore the rest.
  String _buildGroundedConcept(String name, String concept, String grounding) {
    final g = grounding.trim();
    if (g.isEmpty) return concept;
    final lead = concept.trim().isEmpty ? '' : '${concept.trim()}\n\n';
    return '${lead}Build "$name" to match EXACTLY how they are portrayed in the '
        'roleplay excerpts below — their appearance, manner, role, speech, and '
        'relationships as actually shown. The excerpts also feature other '
        'characters (the narrator and the user); use ONLY the details that '
        'describe "$name" and ignore traits that clearly belong to someone '
        'else. Do not invent a conflicting identity.\n\n'
        'How "$name" has appeared in the scene so far:\n$g';
  }
}
