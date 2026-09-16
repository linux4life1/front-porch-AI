// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:path/path.dart' as p;

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/capability/capability.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/streaming/stream_hub.dart';
import 'package:front_porch_ai/services/web/util/lorebook_json.dart';
import 'package:front_porch_ai/services/world_from_wiki/world_from_wiki.dart';

/// Web twin of the desktop World-from-wiki wizard. Scout is request/response.
/// Write reports over the hub; save is the existing POST /api/worlds.
class WorldFromWikiFacade {
  WorldFromWikiFacade(this._llm, this._storage, this._hub);

  final LLMProvider _llm;
  final StorageService _storage;
  final StreamHub? _hub;

  WorldFromWikiEngine? _live;
  bool _writing = false;

  bool get available => _llm.activeService.isReady;

  Future<Map<String, dynamic>> status() async {
    return {
      'available': available,
      'toolsAdvertised': await _toolsOk(),
      'savedWikis': _storage.webSearchSettings.savedWikiUrls,
    };
  }

  Future<Map<String, dynamic>> scout(Map<String, dynamic> body) async {
    final wikiUrl = body['wikiUrl']?.toString().trim() ?? '';
    if (parseWikiBaseUrl(wikiUrl) == null) {
      return {'ok': false, 'error': 'wikiUrl is required'};
    }
    if (!await _toolsOk()) {
      return {'ok': false, 'error': kWorldFromWikiToolsCopy};
    }
    final svc = _llm.activeService;
    if (!svc.isReady) {
      return {'ok': false, 'error': 'the LLM backend is not ready'};
    }
    final wiki = WikiSearchService(getBaseUrl: () => wikiUrl);
    final engine = WorldFromWikiEngine(wiki: wiki, llm: svc);
    final result = await engine.scout(
      worldName: body['name']?.toString() ?? '',
      premise: body['premise']?.toString() ?? '',
    );
    return {
      'ok': true,
      'backend': result.catalog.backend.name,
      'titles': result.catalog.titles.length,
      'skipped': result.catalog.skipped,
      'parsed': result.catalog.parsed,
      'proposed': [for (final c in result.proposed) c.toJson()],
    };
  }

  Map<String, dynamic> startWrite(Map<String, dynamic> body) {
    if (_writing) return {'ok': false, 'error': 'already writing'};
    final wikiUrl = body['wikiUrl']?.toString().trim() ?? '';
    if (parseWikiBaseUrl(wikiUrl) == null) {
      return {'ok': false, 'error': 'wikiUrl is required'};
    }
    final cards = parseSignedWorldWriteCards(body['cards'] ?? body['signed']);
    if (cards.isEmpty) {
      return {'ok': false, 'error': 'signed cards are required'};
    }
    final svc = _llm.activeService;
    if (!svc.isReady) {
      return {'ok': false, 'error': 'the LLM backend is not ready'};
    }
    unawaited(_runWrite(wikiUrl, cards, body, svc));
    return {'ok': true};
  }

  void abort() {
    _live?.abort();
  }

  Future<void> _runWrite(
    String wikiUrl,
    List<WorldProposedCard> cards,
    Map<String, dynamic> body,
    LLMService svc,
  ) async {
    _writing = true;
    final wiki = WikiSearchService(getBaseUrl: () => wikiUrl);
    final engine = _live = WorldFromWikiEngine(
      wiki: wiki,
      llm: svc,
      onProgress: (msg) {
        _hub?.broadcast({'event': 'world_wiki_status', 'data': msg});
      },
    );
    try {
      if (!await _toolsOk()) {
        _hub?.broadcast({
          'event': 'world_wiki_error',
          'error': kWorldFromWikiToolsCopy,
        });
        return;
      }
      final entries = await engine.write(
        cards,
        worldName: body['name']?.toString() ?? '',
        premise: body['premise']?.toString() ?? '',
        climateEnabled: body['climateEnabled'] == true,
      );
      if (engine.aborted) {
        _hub?.broadcast({'event': 'world_wiki_abort', 'data': 'Stopped.'});
        return;
      }
      final book = Lorebook(
        entries: entries,
        recursiveScanning: true,
        scanDepth: kWorldFromWikiScanDepth,
        tokenBudget: kWorldFromWikiTokenBudget,
      );
      final climateOn = body['climateEnabled'] == true && engine.biome != null;
      _hub?.broadcast({
        'event': 'world_wiki_done',
        'name': body['name']?.toString() ?? '',
        'description': body['premise']?.toString() ?? '',
        'climateEnabled': climateOn,
        if (climateOn) 'biome': engine.biome,
        'recursiveScanning': true,
        'scanDepth': kWorldFromWikiScanDepth,
        'tokenBudget': kWorldFromWikiTokenBudget,
        'entries': lorebookEntriesToJson(book),
      });
    } catch (e) {
      _hub?.broadcast({'event': 'world_wiki_error', 'error': e.toString()});
    } finally {
      _writing = false;
      _live = null;
    }
  }

  Future<bool> _toolsOk() async {
    if (_llm.hasManagedProcess) {
      return worldFromWikiToolsOk(
        isLocalBackend: true,
        modelId: p.basename(_storage.lastUsedModelPath ?? ''),
      );
    }
    final remote = _llm.openRouterService;
    ModelApiCapabilities? caps;
    try {
      caps = await VisionSupportResolver.instance.capabilitiesForRemote(
        apiUrl: remote.apiUrl,
        apiKey: remote.apiKey,
        modelName: remote.modelName,
      );
    } catch (_) {
      caps = null;
    }
    return worldFromWikiToolsOk(
      remoteCaps: caps,
      isLocalBackend: caps == null,
      modelId: remote.modelName,
    );
  }
}
