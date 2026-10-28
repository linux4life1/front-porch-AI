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

// Stories set in Worlds, slice 4 (docs/design/stories-in-worlds.md §5): the
// relay's world summary (by place and by a chat's Setting), Refresh from
// world, and the shelf row's world name, against a real StoryFacade whose
// pipeline reads Greenhollow Estate from the shipped starter asset.

// ignore_for_file: must_call_super

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart' hide StoryProject, World;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/embedding_service.dart';
import 'package:front_porch_ai/services/memory_service.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/story/story.dart';
import 'package:front_porch_ai/services/web/facade/story_facade.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_story_wf_').path;
        }
        return null;
      });
}

({World root, List<World> places}) greenhollow() {
  final raw = jsonDecode(
    File('assets/worlds/starter/greenhollow.fpworld').readAsStringSync(),
  );
  final pkg = decodeFpWorld(Map<String, dynamic>.from(raw as Map));
  final root = pkg.world..biomeId = pkg.biome?['id']?.toString();
  return (
    root: root,
    places: [
      for (final child in pkg.locations)
        decodeFpWorld(child).world..parentWorldId = root.id,
    ],
  );
}

/// Never asked to generate anything here.
class _MuteLlm extends LLMService {
  @override
  bool get isReady => true;
  @override
  String get backendName => 'mute';
  @override
  Stream<String> generateStream(GenerationParams params) async* {}
  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
  @override
  bool get hasListeners => false;
  @override
  void notifyListeners() {}
  @override
  void dispose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final g = greenhollow();
  final all = [g.root, ...g.places];
  World? byId(String id) => all.where((w) => w.id == id).firstOrNull;
  StoryWorldBrief brief(String id) {
    final leaf = byId(id);
    if (leaf == null) return StoryWorldBrief(chain: const [], places: const []);
    return StoryWorldBrief(
      chain: leaf.id == g.root.id ? [g.root] : [leaf, g.root],
      places: g.places,
    );
  }

  late AppDatabase db;
  late StoryRepository repo;
  late StoryFacade facade;

  setUp(() async {
    db = AppDatabase.forTesting(sameIsolate: true);
    repo = StoryRepository(db);
    final storage = StorageService();
    final pipeline = StoryPipelineService(
      repo,
      _MuteLlm(),
      MemoryService(EmbeddingService(storage), storage, db),
      db,
      worldBrief: brief,
    );
    facade = StoryFacade(repo, pipeline, null);
  });
  tearDown(() => db.close());

  test('the summary by place says where the story starts and what the '
      'world holds', () async {
    final start = g.root.defaultPlaceId!;
    final s = await facade.worldSummary(place: start);
    expect(s['ok'], isTrue);
    expect(s['placeId'], start);
    expect(s['worldName'], 'Greenhollow Estate');
    expect(s['startName'], 'The Conservatory');
    expect(s['atLarge'], isFalse);
    expect(s['placeCount'], 3);
    expect(s['factCount'], 11);
    expect(s['constantCount'], 0);
    expect(s['searchableCount'], 11);
    expect(s['climate'], 'Mediterranean');
    expect(
      s['detail'],
      'starts at The Conservatory · 3 places · 11 facts · Mediterranean',
    );
    expect(
      s['briefLine'],
      'World brief: 3 places · 0 always-on facts · 11 searchable facts',
    );
    expect(
      s['setInLine'],
      'Set in Greenhollow Estate · starts at The Conservatory',
    );
    expect((s['places'] as List).map((p) => p['name']), [
      'The Conservatory',
      'The Kitchens',
      'The Old Orchard',
    ]);

    final kitchens = g.places.firstWhere((p) => p.name == 'The Kitchens');
    final k = await facade.worldSummary(place: kitchens.id);
    expect(k['detail'], startsWith('at The Kitchens'));
    final atLarge = await facade.worldSummary(place: g.root.id);
    expect(atLarge['atLarge'], isTrue);
    expect(atLarge['setInLine'], 'Set in Greenhollow Estate');
    expect(atLarge['detail'], startsWith('the world at large'));
  });

  test(
    'an unknown place, no place, and a chat without a Setting are not ok',
    () async {
      expect((await facade.worldSummary(place: 'gone'))['ok'], isFalse);
      expect((await facade.worldSummary())['ok'], isFalse);
      expect(
        (await facade.worldSummary(session: 'no-such-chat'))['ok'],
        isFalse,
      );
    },
  );

  test('the summary by chat reads that chat\'s Setting', () async {
    final kitchens = g.places.firstWhere((p) => p.name == 'The Kitchens');
    await db.setChatWorldAttachments(
      'chat-1',
      primaryId: kitchens.id,
      loreIds: [g.root.id],
    );
    final s = await facade.worldSummary(session: 'chat-1');
    expect(s['ok'], isTrue);
    expect(s['placeId'], kitchens.id);
    expect(s['worldName'], 'Greenhollow Estate');
  });

  test('the shelf row carries the world name; Refresh from world copies the '
      'book again and keeps story lore', () async {
    final created = await facade.create('The Locked Library');
    final id = created['id'] as String;
    final p = repo.getById(id)!
      ..worldId = g.root.defaultPlaceId
      ..worldName = 'Greenhollow Estate'
      ..lore = [StoryLoreEntry(topic: 'The key', detail: 'Two keys.')];
    await repo.saveProject(p);

    final row = (await facade.list()).firstWhere((s) => s['id'] == id);
    expect(row['worldName'], 'Greenhollow Estate');

    final r = await facade.refreshWorld(id);
    expect(r, {'ok': true, 'copied': 11});
    expect(p.lore, hasLength(12));
    expect(p.lore.last.topic, 'The key');

    p.worldId = 'gone';
    await repo.saveProject(p);
    expect(await facade.refreshWorld(id), {'ok': false, 'copied': 0});
    expect(await facade.refreshWorld('no-such-story'), isNull);
  });
}
