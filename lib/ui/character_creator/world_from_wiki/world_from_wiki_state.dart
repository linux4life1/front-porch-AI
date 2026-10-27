// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/lore_extraction_service.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/world_from_wiki/world_from_wiki.dart';
import 'package:front_porch_ai/ui/character_creator/character_creator.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/world_character_pick.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/world_from_wiki_mint.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/world_from_wiki_shelf_actions.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/world_from_wiki_source_actions.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/world_from_wiki_wizard_gate.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/world_progress_log.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/world_wizard_source.dart';

/// The wizard's context for one run: the Book step's own pick, or chat's
/// when the pick is "Same as chat". Read at Scout and Write time, never
/// cached, so a changed setting is the one that runs.
int worldWizardContextTokens(StorageService storage) => worldWikiContextTokens(
  setting: storage.webSearchSettings.worldWikiContextSize,
  chatContext: storage.backendSettings.contextSize,
);

/// The wizard's depth for one run, from the Book step's stored pick.
WorldWikiDepth worldWizardDepth(StorageService storage) =>
    WorldWikiDepthX.fromIndex(storage.webSearchSettings.worldWikiDepth);

/// Wizard state for World from wiki. Setup reuses [CreatorState].
class WorldFromWikiState extends ChangeNotifier with WorldWizardGate {
  WorldFromWikiState({DateTime Function()? now})
    : progress = WorldProgressLog(now: now);

  int currentStep = 0;

  /// What the run has been doing, line by line, with the time taken; the
  /// panel under the spinner reads it. [status] stays the current line.
  final WorldProgressLog progress;
  Timer? _ticker;

  /// The Review step: entries the author pinned (a send-back never touches
  /// them), by lowercase name; the direction note; whether it is running.
  final Set<String> pinned = {};

  /// The shelf reviewer's findings from the scout, for the Review step.
  List<String> shelfNotes = const [];
  bool shelfRevised = false;
  final directionController = TextEditingController();
  bool directionWholeWorld = false;
  bool reviewing = false;

  /// A scout, write or review run begins: the log restarts and a
  /// once-a-second tick keeps the elapsed time moving.
  void beginRun(String first) {
    progress.start();
    status = first;
    progress.note(first);
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => notify());
  }

  void finishRun() {
    _ticker?.cancel();
    _ticker = null;
    progress.stop();
  }

  /// One line from the engine: shown now, and kept for the panel.
  void noteProgress(String msg) {
    status = msg;
    progress.note(msg);
    notify();
  }

  final nameController = TextEditingController();
  final premiseController = TextEditingController();
  final descController = TextEditingController();

  /// The Moment: when in the story the scene starts. Every card is
  /// written as things stand then; later events are unknown.
  final momentController = TextEditingController();

  /// What this run builds from; the Book step's second card follows it.
  WorldWizardSource wizardSource = WorldWizardSource.wiki;
  final characterPick = WorldCharacterPick();

  String wikiUrl = '';
  bool lorebooksOn = true;
  bool climateEnabled = false;
  @override
  WorldToolsGate toolsGate = WorldToolsGate.notRunning;
  bool scouting = false;
  bool writing = false;
  String status = '';
  @override
  String? error;
  int catalogTitleCount = 0;

  /// The wiki's own article count and whether the catalog is its
  /// most-linked pages (a big wiki) rather than a complete listing.
  int? catalogArticleCount;
  bool catalogRanked = false;

  List<WorldProposedCard> proposed = [];
  final Set<int> signed = {};

  /// The Shelf step's kind filter: '' shows every card.
  String shelfFilter = '';
  List<LorebookEntry> entries = [];

  /// Slice 8 (design §9): scout-named places (empty on an untagged wiki
  /// — the flat path), the per-place "own climate" switches (defaults
  /// follow the scout's climate hints), and the written tree.
  List<WorldProposedPlace> places = [];
  final Set<String> placeClimate = {};
  WorldWriteTree? tree;
  final List<PlatformFile> loreFiles = [];
  String extraLore = '';

  WorldFromWikiEngine? engine;

  /// Test seams.
  WikiSearchService Function(String url)? wikiFactory;
  Future<http.Response> Function(http.BaseRequest request)? sendRequest;
  @override
  LLMService? llmOverride;

  @override
  void notify() => notifyListeners();

  bool get busy => scouting || writing || reviewing;

  /// Chat's tool check passed for this wizard's model.
  @override
  bool get toolsReady => toolsGate == WorldToolsGate.ready;

  /// Anything the Review step may act on is running.
  bool get busyReviewing => reviewing;

  bool get canSave =>
      worldFromWikiCanSave(
        aborted: engine?.aborted ?? false,
        lorebooksOn: lorebooksOn,
        entries: entries,
      ) &&
      startPick.problem(writtenPlaceNames) == null;

  void abortWrite() {
    engine?.abort();
    status = 'Stopped.';
    notify();
  }

  List<WorldProposedCard> get signedCards => [
    for (var i = 0; i < proposed.length; i++)
      if (signed.contains(i)) proposed[i],
  ];

  void togglePlaceClimate(String placeKey, bool on) {
    if (on) {
      placeClimate.add(placeKey);
    } else {
      placeClimate.remove(placeKey);
    }
    notify();
  }

  /// Review shelf order: root cards first, then each place's. Cards
  /// naming an unknown place ride the root bucket, never vanish.
  Map<String, List<int>> get indicesByPlace {
    final out = <String, List<int>>{'': []};
    for (final p in places) {
      out.putIfAbsent(p.key, () => []);
    }
    final known = out.keys.where((k) => k.isNotEmpty).toSet();
    for (var i = 0; i < proposed.length; i++) {
      final pk = proposed[i].place.trim().toLowerCase();
      out[pk.isNotEmpty && known.contains(pk) ? pk : '']!.add(i);
    }
    return out;
  }

  void toggleSigned(int index, bool on) {
    if (on) {
      signed.add(index);
    } else {
      signed.remove(index);
    }
    notify();
  }

  void disposeControllers() {
    _ticker?.cancel();
    directionController.dispose();
    nameController.dispose();
    premiseController.dispose();
    descController.dispose();
    momentController.dispose();
    startPick.dispose();
  }

  Future<void> scout({
    required LLMProvider llm,
    required CreatorState creator,
    required int contextTokens,
    WorldWikiDepth depth = kWorldWikiDepthDefault,
  }) async {
    final pickError = sourcePickError;
    if (pickError != null) {
      error = pickError;
      notify();
      return;
    }
    if (!toolsReady) {
      error = worldFromWikiToolsCopy(toolsGate);
      notify();
      return;
    }
    final svc = llmFor(llm, creator);
    if (svc == null || !svc.isReady) {
      error = 'The backend is not ready.';
      notify();
      return;
    }
    scouting = true;
    error = null;
    beginRun('Scouting wiki…');
    notify();
    try {
      engine = await engineFor(svc, contextTokens: contextTokens, depth: depth);
      final result = await engine!.scout(
        worldName: nameController.text,
        premise: premiseController.text,
      );
      takeShelf(result);
      status =
          '${proposed.length} cards from $catalogTitleCount pages'
          '${places.isNotEmpty ? ', ${places.length} places' : ''}'
          '${result.catalog.skipped > 0 ? ', skipped ${result.catalog.skipped}' : ''}'
          '${worldScoutPartsNote(parts: result.parts, partsCut: result.partsCut)}'
          '${worldScoutShelfNote(revised: result.revised, auditNotes: result.auditNotes)}';
      if (proposed.isEmpty) {
        // The engine says why when the model never answered (token limit,
        // busy server, unreadable call); the premise line is for a real
        // empty answer only.
        error =
            result.failure ??
            'The scout returned no cards. Try a clearer premise, or another wiki.';
      } else {
        currentStep = 2;
      }
    } catch (e) {
      error = 'Scout failed: $e';
      debugPrint('[World] scout miss/fail reason=$e');
    } finally {
      finishRun();
      scouting = false;
      notify();
    }
  }

  Future<void> write({
    required LLMProvider llm,
    required CreatorState creator,
    required int contextTokens,
    WorldWikiDepth depth = kWorldWikiDepthDefault,
  }) async {
    if (!toolsReady) {
      error = worldFromWikiToolsCopy(toolsGate);
      notify();
      return;
    }
    final svc = llmFor(llm, creator);
    if (svc == null || !svc.isReady) {
      error = 'The backend is not ready.';
      notify();
      return;
    }
    final picked = signedCards;
    if (picked.isEmpty) {
      error = 'Sign at least one card.';
      notify();
      return;
    }
    extraLore = await _extractFiles();
    writing = true;
    error = null;
    beginRun('Writing 0/${picked.length}');
    currentStep = 3;
    notify();
    try {
      engine = await engineFor(svc, contextTokens: contextTokens, depth: depth);
      final t = await engine!.writeTree(
        picked,
        places: places,
        worldName: nameController.text,
        premise: premiseController.text,
        extraLore: extraLore,
        climateEnabled: climateEnabled,
        climatePlaces: Set<String>.from(placeClimate),
      );
      if (engine!.aborted) {
        entries = [];
        tree = null;
        status = 'Stopped.';
      } else {
        tree = t;
        entries = t.root.entries.followedBy([
          for (final p in t.places) ...p.entries,
        ]).toList();
        if (descController.text.trim().isEmpty) {
          descController.text = t.root.description.isNotEmpty
              ? t.root.description
              : premiseController.text.trim();
        }
        currentStep = 4;
      }
    } catch (e) {
      error = 'Write failed: $e';
      debugPrint('[World] write miss/fail reason=$e');
    } finally {
      finishRun();
      writing = false;
      notify();
    }
  }

  World previewWorld() =>
      characterPick.stamp(_previewRoot(), active: wizardSource.isCharacter);

  World _previewRoot() {
    final t = tree;
    if (t == null || t.isFlat) {
      return worldFromWikiDraft(
        name: nameController.text,
        description: descController.text,
        entries: entries,
        climateEnabled: climateEnabled,
        biome: engine?.biome,
      );
    }
    return worldFromWikiDraft(
      name: nameController.text,
      description: descController.text,
      entries: t.root.entries,
      climateEnabled: climateEnabled,
      biome: t.root.biome,
    );
  }

  /// Preview rows for the tree: root first, then places in build order
  /// — what Save will create, names and depths visible.
  List<World> previewTreeWorlds() {
    final t = tree;
    if (t == null || t.isFlat) return [previewWorld()];
    return [
      previewWorld(),
      for (final p in t.places)
        worldFromWikiDraft(
          name: p.name,
          description: p.description,
          entries: p.entries,
          climateEnabled: p.hasClimate,
          biome: p.biome,
        ),
    ];
  }

  /// Where chats in the minted world start; Mint waits for it.
  final startPick = WorldStartPick();

  /// The written places' names, for the starting-place pick.
  List<String> get writtenPlaceNames => [
    for (final p in tree?.places ?? const <WorldPlaceWrite>[]) p.name,
  ];

  Future<bool> save(WorldRepository repo) async {
    if (!canSave) {
      error =
          startPick.problem(writtenPlaceNames) ?? 'Write a signed shelf first.';
      notify();
      return false;
    }
    final why = await mintWorldFromWiki(
      repo,
      root: previewWorld(),
      tree: tree,
      start: startPick,
      placeWorld: (p, parentId) => worldFromWikiDraft(
        name: p.name,
        description: p.description,
        entries: p.entries,
        climateEnabled: p.hasClimate,
        biome: p.biome,
        parentWorldId: parentId,
      ),
    );
    if (why == null) return true;
    error = why;
    notify();
    return false;
  }

  Future<String> _extractFiles() async {
    if (loreFiles.isEmpty) return '';
    try {
      final raw = await LoreExtractionService.extractAll(
        urls: const [],
        files: loreFiles,
      );
      if (raw.length <= 4000) return raw;
      return raw.substring(0, 4000);
    } catch (e) {
      debugPrint('[World] lore files miss/fail reason=$e');
      return '';
    }
  }
}

/// "(478 index pages)" or, for a big wiki, "(top 478 of 3,005 pages by
/// links)" — one wording for the desktop header and the phone.
String worldCatalogCountCopy({
  required int titles,
  required int? articles,
  required bool ranked,
}) {
  if (titles <= 0) return '';
  if (ranked && articles != null && articles > titles) {
    return ' (top $titles of ${worldWikiThousands(articles)} pages by links).';
  }
  return ' ($titles index pages).';
}

/// 3005 → "3,005".
String worldWikiThousands(int n) {
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}
