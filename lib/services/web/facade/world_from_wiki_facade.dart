// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/streaming/stream_hub.dart';
import 'package:front_porch_ai/services/web/util/lorebook_json.dart';
import 'package:front_porch_ai/services/world_from_wiki/world_from_wiki.dart';

/// Web twin of the desktop World-from-wiki wizard. Scout is request/response.
/// Write reports over the hub; save is the existing POST /api/worlds.
/// The tools gate is chat's own tool check on the chat model, which is the
/// model scout and write run on here.
class WorldFromWikiFacade {
  WorldFromWikiFacade(this._llm, this._storage, this._hub, this._chat);

  final LLMProvider _llm;
  final StorageService _storage;
  final StreamHub? _hub;
  final ChatService _chat;

  WorldFromWikiEngine? _live;
  bool _writing = false;

  bool get available => _llm.activeService.isReady;

  Future<Map<String, dynamic>> status() async {
    final gate = _toolsGate();
    return {
      'available': available,
      'toolsAdvertised': gate == WorldToolsGate.ready,
      'toolsGate': gate.name,
      'savedWikis': _storage.webSearchSettings.savedWikiUrls,
    };
  }

  /// The wizard's "Check now": ask the chat model again, then report.
  Future<Map<String, dynamic>> testTools() async {
    await _chat.retestToolsFor();
    return status();
  }

  Future<Map<String, dynamic>> scout(Map<String, dynamic> body) async {
    final wikiUrl = body['wikiUrl']?.toString().trim() ?? '';
    if (parseWikiBaseUrl(wikiUrl) == null) {
      return {'ok': false, 'error': 'wikiUrl is required'};
    }
    final gate = _toolsGate();
    if (gate != WorldToolsGate.ready) {
      return {
        'ok': false,
        'error': worldFromWikiToolsCopy(gate, onPhone: true),
      };
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
      final gate = _toolsGate();
      if (gate != WorldToolsGate.ready) {
        _hub?.broadcast({
          'event': 'world_wiki_error',
          'error': worldFromWikiToolsCopy(gate, onPhone: true),
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

  WorldToolsGate _toolsGate() => worldFromWikiToolsGate(_chat.toolCheckFor());
}
