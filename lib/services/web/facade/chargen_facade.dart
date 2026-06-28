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

import 'package:front_porch_ai/services/character_gen_service.dart';
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/services/llm_service.dart';
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
  ChargenFacade(this._llm, this._characters, this._hub, [this._imageGen]);

  final LLMProvider _llm;
  final CharacterFacade _characters;
  final StreamHub? _hub;
  final ImageGenService? _imageGen;

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

  /// Scrape + clean one or more wiki/lore URLs into plain text (the web mirror of
  /// the desktop lore input). Reuses the shared [LoreExtractionService] so the
  /// scraping/cleaning behaves identically to the desktop creator.
  Future<Map<String, dynamic>> extractLoreFromUrls(List<String> urls) async {
    final text = await LoreExtractionService.extractAll(urls: urls, files: const []);
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
    final text = await LoreExtractionService.extractAll(urls: const [], files: [file]);
    return {'lore': text, 'chars': text.length};
  }

  /// Coerce a JSON value to a `List<String>`, dropping blanks; falls back to
  /// [fallback] when absent or empty. Used for greeting tones / lore categories.
  List<String> _strList(dynamic v, List<String> fallback) {
    if (v is List) {
      final out = v.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
      return out.isEmpty ? fallback : out;
    }
    return fallback;
  }

  /// Render a portrait via the configured image backend, or null if there is no
  /// backend / prompt / on failure (generation never blocks on the image step).
  /// Mirrors the desktop generateAvatar: strip the character name from the
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
    _hub?.broadcast({'event': 'chargen_status', 'data': 'Generating portrait...'});
    try {
      return await svc.generateImage(
        prompt: clean,
        size: '512x512',
        isPortrait: true,
      );
    } catch (_) {
      _hub?.broadcast(
        {'event': 'chargen_status', 'data': 'Portrait generation skipped'},
      );
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
        onStatus: (s) => _hub?.broadcast({'event': 'chargen_status', 'data': s}),
      );
      if (card != null && mode == 'automated' && concept.isNotEmpty) {
        card.description = concept;
      }
      if (card == null) {
        _hub?.broadcast(
          {'event': 'chargen_error', 'error': 'generation produced no card'},
        );
        return;
      }
      // Auto-render a portrait when an image backend is configured — the web
      // mirror of the desktop's end-of-generation generateAvatar (creator_state_
      // engine.dart). The LLM authored the prompt during generation; strip the
      // name (image models render names as text) and render a 512² portrait.
      final portrait = await _renderPortrait(name, gen.generatedImagePrompt);
      final saved = await _characters.persistNewCard(card, portraitBytes: portrait);
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
