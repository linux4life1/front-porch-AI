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
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:front_porch_ai/utils/picker_prefs.dart';

import 'package:front_porch_ai/database/database.dart' hide World;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/chargen/chargen.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/lore_extraction_service.dart';
import 'package:front_porch_ai/services/web/facade/character_facade.dart';
import 'package:front_porch_ai/services/web/streaming/stream_hub.dart';
import 'package:front_porch_ai/services/web/facade/chargen/chargen.dart';

/// Web adapter for the AI character creator. The generator itself
/// ([CharacterGenService.generateCharacter]) is already fully headless — the
/// desktop `creator_state_engine` is just a UI wrapper around it — so this is a
/// thin driver: kick off generation, stream its step-by-step progress over the
/// WebSocket hub, and persist the result through the shared [CharacterFacade]
/// save path. No desktop code is reimplemented.
class ChargenFacade {
  ChargenFacade(
    this._llm,
    this._characters,
    this._hub, [
    this._imageGen,
    this._storage,
    this._chat,
  ]);

  final LLMProvider _llm;
  final CharacterFacade _characters;
  final StreamHub? _hub;
  final ImageGenService? _imageGen;
  final StorageService? _storage;
  final ChatService? _chat;

  /// Creating and saving a whole character.
  late final ChargenCreate _create = ChargenCreate(
    _llm,
    _characters,
    _hub,
    _imageGen,
  )..onSaved = (id, recipe) => _greetings.rememberRecipe(id, recipe);

  /// The Greetings step: rewrite, add, delete or stop one greeting.
  late final ChargenGreetings _greetings = ChargenGreetings(
    _llm,
    _characters,
    _hub,
    busyReason: () => _busyReason(greetings: false),
  );

  /// The Profile step: the paused create, its rewrites and Next.
  late final ChargenProfile _profile = ChargenProfile(
    _characters,
    _hub,
    _storage,
    _create,
    busyReason: () => _busyReason(profile: false),
  );

  /// The review rewrites: example dialogue and lorebook.
  late final ChargenRewrites _rewrites = ChargenRewrites(
    _characters,
    _hub,
    _create,
    recipeFor: _greetings.recipeFor,
    busyReason: () => _busyReason(rewrites: false),
  );

  /// Why a new model call must wait, or null. One call at a time across
  /// the creator; each part checks its own job itself, so it is left out.
  String? _busyReason({
    bool greetings = true,
    bool profile = true,
    bool rewrites = true,
  }) {
    if (_create.creating) {
      return 'A character is still being created. Wait for it.';
    }
    if (profile && _profile.busy) {
      return 'The profile is being written. Wait for it.';
    }
    if (greetings && _greetings.busy) {
      return 'A greeting is being written. Wait for it.';
    }
    if (rewrites && _rewrites.busy) {
      return 'Something is being rewritten. Wait for it.';
    }
    return null;
  }

  /// See [ChargenGreetings.startGreeting].
  Map<String, dynamic> startGreeting(
    Map<String, dynamic> body, {
    bool add = false,
  }) => _greetings.startGreeting(body, add: add);

  /// See [ChargenGreetings.writingGreeting].
  int? writingGreeting(String characterId) =>
      _greetings.writingGreeting(characterId);

  /// See [ChargenGreetings.stopGreeting].
  bool stopGreeting(String characterId) => _greetings.stopGreeting(characterId);

  /// See [ChargenGreetings.deleteGreeting].
  Future<Map<String, dynamic>> deleteGreeting(String characterId, int index) =>
      _greetings.deleteGreeting(characterId, index);

  /// Whether an LLM backend is ready to generate.
  bool get available => _llm.activeService.isReady;

  /// Begin generating a character and return immediately. Progress and the
  /// final result arrive over the hub as `chargen_status` / `chargen_done` /
  /// `chargen_error` events, so the client never holds a multi-minute HTTP
  /// request open on a flaky mobile link. Returns `{ok:false, error}` only for
  /// synchronous pre-flight failures (no name / backend not ready).
  ///
  /// With `pauseAtProfile: true` the run stops after the profile
  /// (`chargen_profile`) and waits for [startContinue]; a refusal then may
  /// carry a `status` (409 while another model call runs).
  Map<String, dynamic> startCreate(Map<String, dynamic> fields) {
    final name = fields['name']?.toString().trim() ?? '';
    if (name.isEmpty) return {'ok': false, 'error': 'name is required'};
    final svc = _llm.activeService;
    if (!svc.isReady) {
      return {'ok': false, 'error': 'the LLM backend is not ready'};
    }
    if (fields['pauseAtProfile'] == true) {
      return _profile.startPaused(name, fields, svc);
    }
    _create.startOneShot(name, fields, svc);
    return {'ok': true};
  }

  /// See [ChargenProfile.profile].
  Future<Map<String, dynamic>> profile({String characterId = ''}) =>
      _profile.profile(characterId: characterId);

  /// See [ChargenProfile.startRewrite].
  Future<Map<String, dynamic>> startProfileRewrite(Map<String, dynamic> b) =>
      _profile.startRewrite(b);

  /// See [ChargenProfile.stop].
  bool stopProfile(Map<String, dynamic> body) => _profile.stop(body);

  /// See [ChargenProfile.startFacts].
  Future<Map<String, dynamic>> startFacts(Map<String, dynamic> body) =>
      _profile.startFacts(body);

  /// See [ChargenProfile.startContinue].
  Future<Map<String, dynamic>> startContinue(Map<String, dynamic> body) =>
      _profile.startContinue(body);

  /// See [ChargenGreetings.startRewriteAll].
  Map<String, dynamic> startRewriteAll(Map<String, dynamic> body) =>
      _greetings.startRewriteAll(body);

  /// See [ChargenGreetings.profileChanged].
  bool profileChanged(String characterId) =>
      _greetings.profileChanged(characterId);

  /// See [ChargenGreetings.keepProfile].
  Future<bool> keepProfile(String characterId) =>
      _greetings.keepProfile(characterId);

  /// See [ChargenRewrites.start]; [field] is `mesExample` or `lorebook`.
  Map<String, dynamic> startRewrite(String field, Map<String, dynamic> b) =>
      _rewrites.start(field, b);

  /// See [ChargenRewrites.stop].
  bool stopRewrite(String characterId) => _rewrites.stop(characterId);

  /// What the review cards show for a saved character: its example
  /// dialogue, its lorebook entries (hand-edited ones marked), the field
  /// being rewritten and the sex the subtitle's pronoun reads.
  Map<String, dynamic>? review(String characterId) {
    final card = _characters.cardByDbId(characterId);
    if (card == null) return null;
    return {
      'mesExample': card.mesExample,
      'lorebook': lorebookRows(card.lorebook),
      'writing': _rewrites.writing(characterId),
      'sex': readNarrativeVoice(card).sex,
    };
  }

  /// See [ChargenCreate.renderPortrait].
  @visibleForTesting
  Future<List<int>?> renderPortrait(String name, String? imagePrompt) =>
      _create.renderPortrait(name, imagePrompt);

  /// Begin an AI Enhance run (grow an existing character from one of its
  /// chats) and return immediately. Progress rides the shared
  /// `chargen_status` events; the result arrives as **`chargen_enhance_done`**
  /// — a distinct event, because `chargen_done` means "a card was saved" and
  /// the create page navigates on it. Enhance saves NOTHING server-side: the
  /// payload is a proposal `{characterId, proposal: {field: newValue, ...}}`
  /// the client reviews and applies through the existing duplicate + update
  /// endpoints.
  ///
  /// Body: `{characterId, sessionId, fields: EnhanceSelection JSON,
  /// nsfwEnabled, modelId?, narrativePerspective?, narrativeTense?, sex?}` —
  /// voice fields keep the Create choice; omitted falls back to the card
  /// stamp, then first-person present. `modelId` (remote backends only) runs the
  /// enhance on that model via the same ad-hoc resolver the creator wizard
  /// uses, without switching the app's active model.
  Map<String, dynamic> startEnhance(Map<String, dynamic> body) {
    final id = body['characterId']?.toString().trim() ?? '';
    final sessionId = body['sessionId']?.toString().trim() ?? '';
    if (id.isEmpty || sessionId.isEmpty) {
      return {'ok': false, 'error': 'characterId and sessionId are required'};
    }
    final card = _characters.cardByDbId(id);
    if (card == null) return {'ok': false, 'error': 'character not found'};
    final svc = _llm.serviceForModel(body['modelId']?.toString().trim() ?? '');
    if (svc == null) {
      return {'ok': false, 'error': 'the LLM backend is not ready'};
    }
    final db = AppDatabase.current;
    if (db == null) return {'ok': false, 'error': 'database not ready'};
    final rawFields = body['fields'];
    final selection = EnhanceSelection.fromJson(
      rawFields is Map ? Map<String, dynamic>.from(rawFields) : const {},
    );
    if (!selection.anySelected) {
      return {'ok': false, 'error': 'no fields selected'};
    }
    unawaited(
      _runEnhance(
        card,
        sessionId,
        selection,
        body['nsfwEnabled'] == true,
        svc,
        db,
        narrativePerspective: body['narrativePerspective']?.toString(),
        narrativeTense: body['narrativeTense']?.toString(),
        sex: body['sex']?.toString(),
      ),
    );
    return {'ok': true};
  }

  Future<void> _runEnhance(
    CharacterCard card,
    String sessionId,
    EnhanceSelection selection,
    bool nsfwEnabled,
    LLMService svc,
    AppDatabase db, {
    String? narrativePerspective,
    String? narrativeTense,
    String? sex,
  }) async {
    try {
      final ctx = await buildEnhanceContext(
        db: db,
        card: card,
        sessionId: sessionId,
      );
      final grounding = buildChatExcerptBlock(
        turns: ctx.turns,
        recap: ctx.recap,
        memoryCards: ctx.memoryCards,
        maxChars: enhanceGroundingCharBudget(
          isLocalKobold:
              _llm.activeBackend == BackendType.kobold &&
              _llm.koboldService.isReady,
          contextSize: switch (_storage?.backendSettings) {
            final b? => b.promptContext(b.contextSize),
            null => 8192,
          },
        ),
      );
      final gen = CharacterGenService(svc);
      final result = await gen.enhanceCharacter(
        source: card,
        selection: selection,
        chatGrounding: grounding,
        nsfwEnabled: nsfwEnabled,
        narrativePerspective: narrativePerspective,
        narrativeTense: narrativeTense,
        sex: sex,
        // Same rule as the desktop flow and the Scene Guest mint: never kill
        // evals a live chat may have in flight on the shared backend.
        abortInFlight: false,
        onStatus: (s) =>
            _hub?.broadcast({'event': 'chargen_status', 'data': s}),
      );
      if (result == null) {
        _hub?.broadcast({
          'event': 'chargen_error',
          'error': 'enhance produced no result',
        });
        return;
      }
      final porch = selection.porchLife
          ? porchLifeIdentityOf(result.frontPorchExtensions)
          : null;
      _hub?.broadcast({
        'event': 'chargen_enhance_done',
        'characterId': card.dbId,
        'proposal': {
          if (selection.description) 'description': result.description,
          if (selection.personality) 'personality': result.personality,
          if (selection.exampleDialogue) 'mesExample': result.mesExample,
          if (selection.scenario) 'scenario': result.scenario,
          if (selection.greetings) 'firstMessage': result.firstMessage,
          if (selection.greetings)
            'alternateGreetings': result.alternateGreetings,
          // How those greetings were written; the phone sends it back with
          // them, so the copy does not keep the original's recipe.
          if (selection.greetings)
            'greetingRecipe':
                (readGreetingRecipe(result) ?? const GreetingRecipe())
                    .toStamp(),
          if (selection.lorebook && result.lorebook != null)
            'lorebook': result.lorebook!.toJson(),
          if (porch != null)
            'porchLife': {
              'ambitions': porch.ambitions,
              'likes': porch.likes,
              'dislikes': porch.dislikes,
              'worn': porch.worn,
              'carrying': porch.carrying,
              'intimateInto': porch.intimateInto,
              'intimateNotInto': porch.intimateNotInto,
            },
        },
      });
    } catch (e) {
      _hub?.broadcast({'event': 'chargen_error', 'error': '$e'});
    }
  }

  /// Copy every chat of the base character onto its freshly saved
  /// "(Enhanced)" duplicate — the web twin of the desktop wizard's final
  /// "bring your chats along" step, riding the exact same `.fpchat`
  /// round-trip ([ChatServiceEnhanceChats.copyChatsForEnhance]).
  /// [ChatImportBusy] propagates to the route (→ 409) when a reply is
  /// mid-flight in the open chat.
  Future<Map<String, dynamic>> copyEnhanceChats(
    String fromId,
    String toId,
  ) async {
    final chat = _chat;
    if (chat == null) return {'ok': false, 'error': 'chat is not available'};
    if (fromId == toId) {
      return {'ok': false, 'error': 'from and to must be different characters'};
    }
    final from = _characters.cardByDbId(fromId);
    final to = _characters.cardByDbId(toId);
    if (from == null || to == null) {
      return {'ok': false, 'error': 'character not found'};
    }
    final copied = await chat.copyChatsForEnhance(from: from, to: to);
    return {'ok': true, 'copied': copied};
  }

  /// Scrape + clean one or more wiki/lore URLs into plain text (the web mirror of
  /// the desktop lore input). Reuses the shared [LoreExtractionService] so the
  /// scraping/cleaning behaves identically to the desktop creator.
  Future<Map<String, dynamic>> extractLoreFromUrls(List<String> urls) async {
    final text = await LoreExtractionService.extractAll(
      urls: urls,
      files: const [],
    );
    return {'lore': text, 'chars': text.length};
  }

  /// Extract plain text from an uploaded lore file (.pdf via the PDF extractor,
  /// otherwise UTF-8 text — same handling as the desktop).
  Future<Map<String, dynamic>> extractLoreFromFile(
    List<int> bytes,
    String filename,
  ) async {
    final file = MemoryPlatformFile(
      name: filename,
      bytes: Uint8List.fromList(bytes),
    );
    final text = await LoreExtractionService.extractAll(
      urls: const [],
      files: [file],
    );
    return {'lore': text, 'chars': text.length};
  }
}
