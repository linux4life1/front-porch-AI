// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/world_from_wiki/world_craft_mechanics.dart';
import 'package:front_porch_ai/services/world_from_wiki/world_from_wiki_ops.dart';
import 'package:front_porch_ai/services/world_from_wiki/world_from_wiki_tools.dart';

/// Scout result: index size plus proposed cards (default unsigned).
class WorldScoutResult {
  const WorldScoutResult({required this.catalog, required this.proposed});

  final WikiStudioCatalog catalog;
  final List<WorldProposedCard> proposed;
}

/// Headless scout + write. Not ChatService. Signed-card count is the loop cap.
class WorldFromWikiEngine {
  WorldFromWikiEngine({required this.wiki, required this.llm, this.onProgress});

  final WikiSearchService wiki;
  final LLMService llm;
  final void Function(String message)? onProgress;

  bool _aborted = false;
  final List<LorebookEntry> entries = [];
  final Set<String> _written = {};
  Map<String, dynamic>? biome;

  bool get aborted => _aborted;

  void abort() {
    _aborted = true;
    llm.abortGeneration();
    debugPrint('[World] abort');
  }

  Future<WikiStudioCatalog> scan({String? seedQuery}) async {
    final catalog = await wiki.listStudioTitles(seedQuery: seedQuery);
    debugPrint(
      '[World] scan backend=${catalog.backend.name} '
      'titles=${catalog.titles.length} skipped=${catalog.skipped} '
      'parsed=${catalog.parsed}',
    );
    return catalog;
  }

  /// Index titles → proposed cards. One tool call. Does not write lore.
  Future<WorldScoutResult> scout({
    required String worldName,
    required String premise,
  }) async {
    _aborted = false;
    final catalog = await scan(
      seedQuery: [
        worldName.trim(),
        premise.trim(),
      ].where((s) => s.isNotEmpty).join(' '),
    );
    if (_aborted) {
      return WorldScoutResult(catalog: catalog, proposed: const []);
    }
    onProgress?.call('Scouting ${catalog.titles.length} titles…');
    final proposed = await _propose(
      titles: catalog.titles,
      worldName: worldName,
      premise: premise,
    );
    debugPrint(
      '[World] scout titles=${catalog.titles.length} proposed=${proposed.length}',
    );
    if (proposed.isNotEmpty && proposed.length < kWorldScoutCardMin) {
      debugPrint('[World] scout short proposed=${proposed.length}');
    }
    return WorldScoutResult(catalog: catalog, proposed: proposed);
  }

  /// Signed cards only. One tool call per [kWorldWriteBatchSize] cards.
  Future<List<LorebookEntry>> write(
    List<WorldProposedCard> signed, {
    required String worldName,
    required String premise,
    String extraLore = '',
    bool climateEnabled = false,
  }) async {
    _aborted = false;
    biome = null;
    entries.clear();
    _written.clear();
    final pending = <WorldProposedCard>[];
    for (final card in signed) {
      final name = card.name.trim();
      if (name.isEmpty || !_written.add(name.toLowerCase())) continue;
      pending.add(card);
    }
    final k = pending.length;
    debugPrint('[World] review signed=$k batch=$kWorldWriteBatchSize');
    final drafts = <WorldCraftDraft>[];
    for (var offset = 0; offset < k; offset += kWorldWriteBatchSize) {
      if (_aborted) {
        debugPrint('[World] abort');
        break;
      }
      final end = (offset + kWorldWriteBatchSize).clamp(0, k);
      final chunk = pending.sublist(offset, end);
      debugPrint(
        '[World] write batch ${offset + 1}–$end/$k '
        'names=${chunk.map((c) => c.name).join(', ')}',
      );
      onProgress?.call('Writing ${chunk.length} cards ($end/$k)');
      if (_aborted) break;
      final ready = <WorldProposedCard>[];
      final articles = <String>[];
      for (final card in chunk) {
        final article = await _joinSources(card.sourceTitles);
        if (article.isEmpty) {
          debugPrint('[World] write miss ${card.name}');
          continue;
        }
        ready.add(card);
        articles.add(article);
      }
      if (ready.isEmpty) continue;
      final generated = await _writeBatch(
        cards: ready,
        articles: articles,
        worldName: worldName,
        premise: premise,
        extraLore: extraLore,
      );
      drafts.addAll(matchWorldWriteBatch(ready, generated));
    }
    if (climateEnabled && !_aborted) {
      final climate = await _writeClimate(
        worldName: worldName,
        premise: premise,
      );
      if (climate != null) {
        biome = climate.biome;
        debugPrint(
          '[World] climate biome=${climate.biome['displayName']} '
          'lore=${climate.lore.length}',
        );
        for (final w in climate.lore) {
          if (!_written.add(w.name.toLowerCase())) continue;
          drafts.add(
            WorldCraftDraft(
              name: w.name,
              keys: w.keys,
              content: w.content,
              role: WorldCraftRole.hub,
            ),
          );
        }
      }
    }
    if (_aborted) {
      entries.clear();
      return List<LorebookEntry>.unmodifiable(entries);
    }
    entries.addAll(applyWorldCraftMechanics(drafts));
    return List<LorebookEntry>.unmodifiable(entries);
  }

  Future<List<WorldProposedCard>> _propose({
    required List<String> titles,
    required String worldName,
    required String premise,
  }) async {
    if (titles.isEmpty) return const [];
    final index = titles.map((t) => '- $t').join('\n');
    final prompt =
        'World: ${worldName.trim().isEmpty ? 'Untitled' : worldName.trim()}\n'
        'Premise: ${premise.trim()}\n'
        'INDEX TITLES:\n$index\n\n'
        '$kWorldScoutPrompt\n'
        'Call $kWorldScoutToolName once.';
    try {
      final resp = await llm.generateWithTools(
        GenerationParams(
          prompt: prompt,
          maxLength: 3072,
          minLength: 16,
          temperature: 0.3,
          reasoningEnabled: true,
          toolChoice: kWorldScoutToolName,
        ),
        worldScoutToolSchema(),
      );
      if (resp == null || resp.isUnusableNativeToolCall) return const [];
      return parseWorldScoutToolCalls(resp.calls, catalog: titles);
    } catch (e) {
      debugPrint('[World] scout tools miss ($e)');
      return const [];
    }
  }

  Future<String> _joinSources(List<String> titles) async {
    final buf = StringBuffer();
    for (final title in titles.take(3)) {
      final t = title.trim();
      if (t.isEmpty || skipWikiStudioTitle(t)) continue;
      final article = await wiki.getArticleFull(t);
      if (!article.ok) {
        debugPrint('[World] write miss $t');
        continue;
      }
      if (buf.isNotEmpty) buf.writeln();
      buf.writeln('=== $t ===');
      buf.writeln(article.snippet);
    }
    return buf.toString().trim();
  }

  Future<List<WorldLoreWrite>> _writeBatch({
    required List<WorldProposedCard> cards,
    required List<String> articles,
    required String worldName,
    required String premise,
    required String extraLore,
  }) async {
    final extra = extraLore.trim();
    final extraBlock = extra.isEmpty
        ? ''
        : '\nATTACHED NOTES (optional; do not override the articles):\n$extra\n';
    final buf = StringBuffer();
    buf.writeln(
      'World: ${worldName.trim().isEmpty ? 'Untitled' : worldName.trim()}',
    );
    buf.writeln('Premise: ${premise.trim()}');
    buf.write(extraBlock);
    for (var i = 0; i < cards.length; i++) {
      final card = cards[i];
      final aliases = card.keys.isEmpty ? card.name : card.keys.join(', ');
      buf.writeln();
      buf.writeln('--- CARD ${i + 1}/${cards.length} ---');
      buf.writeln('Name: ${card.name}');
      buf.writeln('Role: ${card.role.name}');
      buf.writeln('Suggested keys: $aliases');
      buf.writeln('ARTICLES:');
      buf.writeln(articles[i]);
    }
    buf.writeln();
    buf.writeln(
      'Call $kWorldLoreBatchToolName once. One entry per card above, '
      'same names. HARD CAP $kWorldLoreContentMax characters — two short '
      'sentences. Alias keys as separate words. they/them for unnamed '
      'people. Do not invent climate, biomes, or facts missing from the '
      'articles.',
    );
    try {
      final resp = await llm.generateWithTools(
        GenerationParams(
          prompt: buf.toString(),
          maxLength: 4096,
          minLength: 16,
          temperature: 0.4,
          reasoningEnabled: true,
          toolChoice: kWorldLoreBatchToolName,
        ),
        worldLoreBatchToolSchema(),
      );
      if (resp == null || resp.isUnusableNativeToolCall) return const [];
      return parseWorldLoreBatchCalls(resp.calls);
    } catch (e) {
      debugPrint('[World] write batch miss ($e)');
      return const [];
    }
  }

  Future<WorldClimateWrite?> _writeClimate({
    required String worldName,
    required String premise,
  }) async {
    onProgress?.call('Writing climate…');
    final catalog = await scan();
    final titles = [
      for (final t in catalog.titles)
        if (wikiTitleLooksClimate(t)) t,
    ].take(4).toList();
    if (titles.isEmpty) {
      debugPrint('[World] climate miss no titles');
      return null;
    }
    final article = await _joinSources(titles);
    if (article.isEmpty) return null;
    final prompt =
        'World: ${worldName.trim().isEmpty ? 'Untitled' : worldName.trim()}\n'
        'Premise: ${premise.trim()}\n'
        'ARTICLES:\n$article\n\n'
        'Call $kWorldClimateToolName once. Custom biome for THIS place, '
        'not Earth temperate Midwest. Optional loreCards (max 3) for the '
        'warm current, boreal winter, or storms — $kWorldLoreContentMin–'
        '$kWorldLoreContentMax characters each.';
    try {
      final resp = await llm.generateWithTools(
        GenerationParams(
          prompt: prompt,
          maxLength: 3072,
          minLength: 16,
          temperature: 0.4,
          reasoningEnabled: true,
          toolChoice: kWorldClimateToolName,
        ),
        worldClimateToolSchema(),
      );
      if (resp == null || resp.isUnusableNativeToolCall) return null;
      return parseWorldClimateCalls(resp.calls);
    } catch (e) {
      debugPrint('[World] climate miss ($e)');
      return null;
    }
  }
}
