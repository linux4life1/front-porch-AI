// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/capability/capability.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/lore_extraction_service.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/world_from_wiki/world_from_wiki.dart';
import 'package:front_porch_ai/ui/character_creator/character_creator.dart';

/// Wizard state for World from wiki. Setup reuses [CreatorState].
class WorldFromWikiState extends ChangeNotifier {
  int currentStep = 0;
  final nameController = TextEditingController();
  final premiseController = TextEditingController();
  final descController = TextEditingController();

  String wikiUrl = '';
  bool lorebooksOn = true;
  bool climateEnabled = false;
  bool toolsAdvertised = false;
  bool scouting = false;
  bool writing = false;
  String status = '';
  String? error;
  int catalogTitleCount = 0;

  List<WorldProposedCard> proposed = [];
  final Set<int> signed = {};
  List<LorebookEntry> entries = [];
  final List<PlatformFile> loreFiles = [];
  String extraLore = '';

  WorldFromWikiEngine? engine;

  /// Test seams.
  WikiSearchService Function(String url)? wikiFactory;
  Future<http.Response> Function(http.BaseRequest request)? sendRequest;
  LLMService? llmOverride;

  void notify() => notifyListeners();

  bool get busy => scouting || writing;

  bool get canSave => worldFromWikiCanSave(
    aborted: engine?.aborted ?? false,
    lorebooksOn: lorebooksOn,
    entries: entries,
  );

  void abortWrite() {
    engine?.abort();
    status = 'Stopped.';
    notify();
  }

  List<WorldProposedCard> get signedCards => [
    for (var i = 0; i < proposed.length; i++)
      if (signed.contains(i)) proposed[i],
  ];

  void toggleSigned(int index, bool on) {
    if (on) {
      signed.add(index);
    } else {
      signed.remove(index);
    }
    notify();
  }

  void disposeControllers() {
    nameController.dispose();
    premiseController.dispose();
    descController.dispose();
  }

  Future<void> refreshToolsGate({
    required LLMProvider llm,
    required CreatorState creator,
  }) async {
    if (llm.hasManagedProcess) {
      toolsAdvertised = worldFromWikiToolsOk(
        isLocalBackend: true,
        modelId: p.basename(creator.selectedLocalModelPath),
      );
    } else {
      final remote = llm.openRouterService;
      final modelId = creator.selectedModelId.isEmpty
          ? remote.modelName
          : creator.selectedModelId;
      ModelApiCapabilities? caps;
      try {
        caps = await VisionSupportResolver.instance.capabilitiesForRemote(
          apiUrl: remote.apiUrl,
          apiKey: remote.apiKey,
          modelName: modelId,
        );
      } catch (_) {
        caps = null;
      }
      toolsAdvertised = worldFromWikiToolsOk(
        remoteCaps: caps,
        isLocalBackend: caps == null,
        modelId: modelId,
      );
    }
    notify();
  }

  WikiSearchService _wiki() {
    final url = wikiUrl;
    final factory = wikiFactory;
    if (factory != null) return factory(url);
    return WikiSearchService(
      getBaseUrl: () => wikiUrl,
      sendRequest: sendRequest,
    );
  }

  LLMService? _llm(LLMProvider llm, CreatorState creator) {
    return llmOverride ?? llm.serviceForModel(creator.selectedModelId);
  }

  Future<void> scout({
    required LLMProvider llm,
    required CreatorState creator,
  }) async {
    if (wikiUrl.trim().isEmpty) {
      error = 'Pick a wiki first.';
      notify();
      return;
    }
    if (!toolsAdvertised) {
      error = kWorldFromWikiToolsCopy;
      notify();
      return;
    }
    final svc = _llm(llm, creator);
    if (svc == null || !svc.isReady) {
      error = 'The backend is not ready.';
      notify();
      return;
    }
    scouting = true;
    error = null;
    status = 'Scouting wiki…';
    notify();
    try {
      engine = WorldFromWikiEngine(
        wiki: _wiki(),
        llm: svc,
        onProgress: (msg) {
          status = msg;
          notify();
        },
      );
      final result = await engine!.scout(
        worldName: nameController.text,
        premise: premiseController.text,
      );
      catalogTitleCount = result.catalog.titles.length;
      proposed = result.proposed;
      signed.clear();
      status =
          '${proposed.length} cards from $catalogTitleCount pages'
          '${result.catalog.skipped > 0 ? ', skipped ${result.catalog.skipped}' : ''}';
      if (proposed.isEmpty) {
        error =
            'The scout returned no cards. Try a clearer premise, or another wiki.';
      } else {
        currentStep = 2;
      }
    } catch (e) {
      error = 'Scout failed: $e';
      debugPrint('[World] scout miss/fail reason=$e');
    } finally {
      scouting = false;
      notify();
    }
  }

  Future<void> write({
    required LLMProvider llm,
    required CreatorState creator,
  }) async {
    if (!toolsAdvertised) {
      error = kWorldFromWikiToolsCopy;
      notify();
      return;
    }
    final svc = _llm(llm, creator);
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
    status = 'Writing 0/${picked.length}';
    currentStep = 3;
    notify();
    engine = WorldFromWikiEngine(
      wiki: _wiki(),
      llm: svc,
      onProgress: (msg) {
        status = msg;
        notify();
      },
    );
    try {
      final written = await engine!.write(
        picked,
        worldName: nameController.text,
        premise: premiseController.text,
        extraLore: extraLore,
        climateEnabled: climateEnabled,
      );
      if (engine!.aborted) {
        entries = [];
        status = 'Stopped.';
      } else {
        entries = written;
        if (descController.text.trim().isEmpty) {
          descController.text = premiseController.text.trim();
        }
        currentStep = 4;
      }
    } catch (e) {
      error = 'Write failed: $e';
      debugPrint('[World] write miss/fail reason=$e');
    } finally {
      writing = false;
      notify();
    }
  }

  World previewWorld() {
    return worldFromWikiDraft(
      name: nameController.text,
      description: descController.text,
      entries: entries,
      climateEnabled: climateEnabled,
      biome: engine?.biome,
    );
  }

  Future<bool> save(WorldRepository repo) async {
    if (!canSave) {
      error = 'Write a signed shelf first.';
      notify();
      return false;
    }
    final world = previewWorld();
    try {
      await repo.saveWorld(world);
      return true;
    } catch (e) {
      error = 'Save failed: $e';
      notify();
      return false;
    }
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
