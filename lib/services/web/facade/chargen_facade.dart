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

import 'package:file_picker/file_picker.dart';

import 'package:front_porch_ai/database/database.dart' hide World;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/chargen/chargen.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/lore_extraction_service.dart';
import 'package:front_porch_ai/services/web/facade/character_facade.dart';
import 'package:front_porch_ai/services/web/streaming/stream_hub.dart';

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

  /// Whether an LLM backend is ready to generate.
  bool get available => _llm.activeService.isReady;

  /// Begin generating a character and return immediately. Progress and the
  /// final result arrive over the hub as `chargen_status` / `chargen_done` /
  /// `chargen_error` events, so the client never holds a multi-minute HTTP
  /// request open on a flaky mobile link. Returns `{ok:false, error}` only for
  /// synchronous pre-flight failures (no name / backend not ready).
  Map<String, dynamic> startCreate(Map<String, dynamic> fields) {
    final name = fields['name']?.toString().trim() ?? '';
    if (name.isEmpty) return {'ok': false, 'error': 'name is required'};
    final svc = _llm.activeService;
    if (!svc.isReady) {
      return {'ok': false, 'error': 'the LLM backend is not ready'};
    }
    unawaited(_run(name, fields, svc));
    return {'ok': true};
  }

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
          contextSize: _storage?.contextSize ?? 8192,
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
    final file = PlatformFile(
      name: filename,
      size: bytes.length,
      bytes: Uint8List.fromList(bytes),
    );
    final text = await LoreExtractionService.extractAll(
      urls: const [],
      files: [file],
    );
    return {'lore': text, 'chars': text.length};
  }

  /// Coerce a JSON value to a `List<String>`, dropping blanks; falls back to
  /// [fallback] when absent or empty. Used for greeting tones / lore categories.
  List<String> _strList(dynamic v, List<String> fallback) {
    if (v is List) {
      final out = v
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
      return out.isEmpty ? fallback : out;
    }
    return fallback;
  }

  /// Render a portrait via the configured image backend, or null if there is no
  /// backend / prompt / on failure (generation never blocks on the image step).
  /// Mirrors the desktop buildPortraitPromptSeed: strip the character name from the
  /// LLM-authored prompt so the image model doesn't render it as text.
  Future<List<int>?> _renderPortrait(String name, String? imagePrompt) async {
    final svc = _imageGen;
    final prompt = imagePrompt?.trim() ?? '';
    if (svc == null || !svc.isConfigured || prompt.isEmpty) return null;
    var clean = prompt;
    for (final part in name.split(RegExp(r'\s+'))) {
      if (part.length > 2) {
        clean = clean.replaceAll(
          RegExp('\\b${RegExp.escape(part)}\\b', caseSensitive: false),
          '',
        );
      }
    }
    clean = clean
        .replaceAll(RegExp(r',\s*,'), ',')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
    if (clean.startsWith(',')) clean = clean.substring(1).trim();
    if (clean.isEmpty) clean = prompt;
    _hub?.broadcast({
      'event': 'chargen_status',
      'data': 'Generating portrait...',
    });
    try {
      // Configured size, oriented portrait, configured default negative —
      // mirrors the desktop creator (the old fixed 512x512 failed on remote
      // models that reject small sizes and capped local quality).
      return await svc.generateImage(prompt: clean, isPortrait: true);
    } catch (_) {
      _hub?.broadcast({
        'event': 'chargen_status',
        'data': 'Portrait generation skipped',
      });
      return null;
    }
  }

  Future<void> _run(
    String name,
    Map<String, dynamic> fields,
    LLMService svc,
  ) async {
    try {
      // Quick / Guided / Automated all flow through the same headless generator;
      // the web wizard assembles concept + characterContext per-mode (mirroring
      // the desktop creator_state_engine) and posts the full param set here. The
      // only mode-specific server step is Automated injecting its assembled
      // description verbatim (the desktop does the same — it doesn't trust the
      // model's rewrite of a user-built description).
      final mode = fields['mode']?.toString() ?? 'quick';
      final concept = fields['concept']?.toString() ?? '';
      final gen = CharacterGenService(svc);
      final card = await gen.generateCharacter(
        name: name,
        concept: concept,
        personalityKeywords: fields['personalityKeywords']?.toString() ?? '',
        artStyle: fields['artStyle']?.toString() ?? '',
        greetingLength:
            fields['greetingLength']?.toString() ?? 'Medium (2-4 paragraphs)',
        altGreetingCount: (fields['altGreetingCount'] as num?)?.toInt() ?? 2,
        greetingTones: _strList(fields['greetingTones'], const ['Neutral']),
        generateLorebook: fields['generateLorebook'] != false,
        loreCategories: _strList(fields['loreCategories'], const []),
        loreDepth: fields['loreDepth']?.toString() ?? 'Standard',
        includeDynamicMacros: fields['includeDynamicMacros'] == true,
        narrativePerspective:
            fields['narrativePerspective']?.toString() ?? 'first',
        narrativeTense: fields['narrativeTense']?.toString() ?? 'present',
        age: fields['age']?.toString() ?? '',
        sex: fields['sex']?.toString() ?? '',
        relationship: fields['relationship']?.toString() ?? '',
        descriptionDetail:
            fields['descriptionDetail']?.toString() ?? '2-3 paragraphs',
        backstory: fields['backstory']?.toString() ?? '',
        scenario: fields['scenario']?.toString() ?? '',
        characterContext: fields['characterContext']?.toString() ?? '',
        generateDescription: mode != 'automated',
        worldLore: (fields['worldLore']?.toString().trim().isNotEmpty ?? false)
            ? fields['worldLore'].toString()
            : null,
        nsfwEnabled: fields['nsfwEnabled'] == true,
        reasoningEnabled: fields['reasoningEnabled'] == true,
        onStatus: (s) =>
            _hub?.broadcast({'event': 'chargen_status', 'data': s}),
      );
      if (card != null && mode == 'automated' && concept.isNotEmpty) {
        card.description = concept;
      }
      if (card == null) {
        _hub?.broadcast({
          'event': 'chargen_error',
          'error': 'generation produced no card',
        });
        return;
      }
      // Auto-render a portrait when an image backend is configured (web-only
      // convenience; desktop generation moved to the explicit Portrait &
      // Avatars panel). The LLM authored the prompt during generation; strip the
      // name (image models render names as text) and render a 512² portrait.
      final portrait = await _renderPortrait(name, gen.generatedImagePrompt);
      final saved = await _characters.persistNewCard(
        card,
        portraitBytes: portrait,
      );
      if (saved == null) {
        _hub?.broadcast({
          'event': 'chargen_error',
          'error': 'failed to save the generated character',
        });
        return;
      }
      _hub?.broadcast({
        'event': 'chargen_done',
        'id': saved['id'],
        'name': saved['name'],
      });
    } catch (e) {
      _hub?.broadcast({'event': 'chargen_error', 'error': '$e'});
    }
  }
}
