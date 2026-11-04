// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Slice 7 guards (design §3 "Minted places"): PlaceFactory turns a
// name+descriptor+scene-grounding into a child World with lore, persisted
// through WorldRepository.saveWorld. Parent choice, inclusion groups,
// depth cap, name collisions, and transport failures are pinned here.
//
// Proven red:
//   * tool schema missing → no usableEvalJsonText salvage of text replies
//   * success path missing → no world created
//   * depth cap missing → level-3 worlds created (illegal)
//   * inclusion group missing → minted entries get their own group instead
//     of joining the ancestor's
//   * name refusal missing → a duplicate mint renamed to "Salt Garden (2)"
//   * LLM not ready missing → throws instead of failure result
//   * malformed JSON missing → partial world row created

import 'dart:convert';

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/models/world.dart' as model;
import 'package:front_porch_ai/services/services.dart'
    show LlmToolResponse, StorageService;
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/place_factory.dart';
import 'package:front_porch_ai/services/world_repository.dart';

const _id = 'Kobold|model-a';

/// A [PlaceFactory] backed by a real [WorldRepository] over an in-memory DB.
/// The transport callbacks are wired so tests can script tool or text answers.
class _Harness {
  _Harness._(this.db, this.repo, this.factory);

  final AppDatabase db;
  final WorldRepository repo;
  final PlaceFactory factory;

  static Future<_Harness> build() async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting();
    final storage = StorageService();
    await storage.initialized;
    final repo = WorldRepository(storage, db);
    await repo.ready;
    final factory = PlaceFactory(
      repo,
      fireToolEval: null,
      fireTextEval: null,
      probe: null,
      getBackendIdentity: () => _id,
    );
    return _Harness._(db, repo, factory);
  }

  Future<void> dispose() async {
    await db.close();
  }
}

/// Build a [PlaceFactory] with scripted transport callbacks.
PlaceFactory _scriptedFactory({
  required WorldRepository repo,
  required Future<LlmToolResponse?> Function() toolAnswer,
  required String textAnswer,
  ToolTransportProbe? probe,
}) {
  return PlaceFactory(
    repo,
    fireToolEval: (_, _) => toolAnswer(),
    fireTextEval: (prompt, {onChunk}) async => textAnswer,
    probe: probe ?? ToolTransportProbe(),
    getBackendIdentity: () => _id,
  );
}

/// A valid flat-JSON text answer for the place-mint tool.
String _placeDraftText({
  String description = 'A small courtyard of salt-bleached stone.',
  List<Map<String, dynamic>>? entries,
}) {
  return jsonEncode({
    'short_description': description,
    'lore_entries':
        entries ??
        [
          {
            'name': 'Salt walls',
            'keys': 'salt,wall',
            'content': 'The walls weep brine.',
          },
          {
            'name': 'Well',
            'keys': 'well,water',
            'content': 'A stone well in the centre.',
          },
          {
            'name': 'Gate',
            'keys': 'gate,iron',
            'content': 'An iron gate to the harbour.',
          },
        ],
  });
}

/// Insert a root world and return it.
Future<model.World> _root(_Harness h, String name) async {
  final w = model.World(
    name: name,
    description: 'Root: $name',
    lorebook: Lorebook(entries: []),
    climateEnabled: true,
  );
  await h.repo.saveWorld(w);
  return w;
}

/// Insert a child world under [parent] and return it.
Future<model.World> _child(_Harness h, String name, model.World parent) async {
  final w = model.World(
    name: name,
    description: 'Child: $name',
    lorebook: Lorebook(entries: []),
    parentWorldId: parent.id,
    climateEnabled: false,
  );
  await h.repo.saveWorld(w);
  return w;
}

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_mint_test_').path;
        }
        return null;
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  group('PlaceFactory', () {
    late _Harness h;

    setUp(() async => h = await _Harness.build());
    tearDown(() async => h.dispose());

    test('tool schema is registered and usableEvalJsonText salvages a plain '
        'text reply carrying the fields, blanks included', () {
      expect(toolIsRegistered(kPlaceMintTool), isTrue);

      final text = _placeDraftText(description: '');
      final salvaged = usableEvalJsonText(
        text,
        tools: kPlaceMintTools,
        toolChoice: kPlaceMintTool,
        callToText: (resp) => realismToolCallToJson(kPlaceMintTool, resp.calls),
      );
      expect(
        salvaged,
        isNotNull,
        reason: 'text-only model answer must salvage',
      );
      final decoded = jsonDecode(salvaged!) as Map<String, dynamic>;
      expect(decoded['short_description'], '');
      expect(decoded['lore_entries'], isA<List>());
    });

    test(
      'successful mint creates a child world under the setting with 3–5 '
      'lore entries, climate off, model-made marker, and repo sees it',
      () async {
        final root = await _root(h, 'Bletchport');
        final factory = _scriptedFactory(
          repo: h.repo,
          toolAnswer: () async => null,
          textAnswer: _placeDraftText(),
        );

        final result = await factory.mint(
          name: 'Salt Garden',
          descriptor: 'hedged beds beside the tideline',
          setting: root,
          sceneGrounding: 'They walked into a garden of salt.',
        );

        expect(result.ok, isTrue, reason: result.error);
        final world = result.world!;
        expect(world.name, 'Salt Garden');
        expect(world.parentWorldId, root.id);
        expect(world.climateEnabled, isFalse);
        expect(world.isModelMade, isTrue);
        expect(world.description, 'A small courtyard of salt-bleached stone.');
        expect(world.lorebook.entries.length, 3);

        final fromRepo = h.repo.worldById(world.id);
        expect(fromRepo, isNotNull);
        expect(fromRepo!.name, 'Salt Garden');
      },
    );

    test(
      'depth cap: minting under a level-2 setting lands under its PARENT',
      () async {
        final root = await _root(h, 'Continent');
        final level1 = await _child(h, 'Town', root);
        final level2 = await _child(h, 'Tavern', level1);

        final factory = _scriptedFactory(
          repo: h.repo,
          toolAnswer: () async => null,
          textAnswer: _placeDraftText(),
        );

        final result = await factory.mint(
          name: 'Back Room',
          descriptor: 'a private room behind the bar',
          setting: level2,
          sceneGrounding: 'They entered the back room.',
        );

        expect(result.ok, isTrue, reason: result.error);
        expect(
          result.world!.parentWorldId,
          level1.id,
          reason: 'level-2 parent is the depth cap; mint under level1',
        );
      },
    );

    test('inclusion group: a parent entry sharing a key means the minted '
        'entry carries the SAME group value', () async {
      final groupValue = 'harbour-group';
      final root = await _root(h, 'Bletchport');
      root.lorebook.entries.add(
        LorebookEntry(
          name: 'Harbour Gate',
          keys: ['gate', 'harbour'],
          content: 'The iron gate controls who enters.',
          group: groupValue,
        ),
      );
      await h.repo.saveWorld(root);

      final factory = _scriptedFactory(
        repo: h.repo,
        toolAnswer: () async => null,
        textAnswer: _placeDraftText(
          entries: [
            {
              'name': 'Gate',
              'keys': 'gate,iron',
              'content': 'A rusty iron gate.',
            },
            {'name': 'Salt walls', 'keys': 'salt', 'content': 'Weeping brine.'},
            {'name': 'Well', 'keys': 'well', 'content': 'Stone mouth.'},
          ],
        ),
      );

      final result = await factory.mint(
        name: 'Salt Garden',
        descriptor: 'hedged beds beside the tideline',
        setting: root,
        sceneGrounding: 'They walked into a garden of salt.',
      );

      expect(result.ok, isTrue, reason: result.error);
      final gateEntry = result.world!.lorebook.entries.firstWhere(
        (e) => e.name == 'Gate',
      );
      expect(
        gateEntry.group,
        groupValue,
        reason: 'shared key "gate" joins the ancestor group',
      );
    });

    test(
      'an existing name is refused, never re-minted as "Name (2)": '
      'exact and case-insensitive matches fail honestly, no new row',
      () async {
        final root = await _root(h, 'Bletchport');
        final factory = _scriptedFactory(
          repo: h.repo,
          toolAnswer: () async => null,
          textAnswer: _placeDraftText(),
        );

        final r1 = await factory.mint(
          name: 'Salt Garden',
          descriptor: 'first',
          setting: root,
          sceneGrounding: 'First arrival.',
        );
        expect(r1.ok, isTrue, reason: r1.error);

        final r2 = await factory.mint(
          name: 'Salt Garden',
          descriptor: 'second',
          setting: root,
          sceneGrounding: 'Second arrival.',
        );
        expect(
          r2.ok,
          isFalse,
          reason: 'a mint never re-mints an existing place',
        );
        expect(r2.error!.toLowerCase(), contains('already exists'));

        final r3 = await factory.mint(
          name: '  salt  GARDEN ',
          descriptor: 'case variant',
          setting: root,
          sceneGrounding: 'Third arrival.',
        );
        expect(r3.ok, isFalse, reason: 'case and space variants collide too');
        expect(r3.error!.toLowerCase(), contains('already exists'));

        final gardens = h.repo.worlds.where(
          (w) => w.name.toLowerCase().contains('garden'),
        );
        expect(gardens.map((w) => w.name).toList(), [
          'Salt Garden',
        ], reason: 'exactly one row — no " (2)" was ever written');
      },
    );

    test(
      'LLM not ready → failure result, no world created, no throw',
      () async {
        final root = await _root(h, 'Bletchport');
        final factory = PlaceFactory(h.repo);

        final result = await factory.mint(
          name: 'Salt Garden',
          descriptor: 'x',
          setting: root,
          sceneGrounding: 'y',
        );

        expect(result.ok, isFalse);
        expect(result.world, isNull);
        expect(result.error, contains('not ready'));
      },
    );

    test('malformed model JSON (missing entries) → failure "did not produce", '
        'no partial world row', () async {
      final root = await _root(h, 'Bletchport');
      final factory = _scriptedFactory(
        repo: h.repo,
        toolAnswer: () async => null,
        textAnswer: jsonEncode({'short_description': 'Only a description.'}),
      );

      final result = await factory.mint(
        name: 'Salt Garden',
        descriptor: 'x',
        setting: root,
        sceneGrounding: 'y',
      );

      expect(result.ok, isFalse);
      expect(result.error!.toLowerCase(), contains('did not produce'));

      final worlds = h.repo.worlds
          .where((w) => w.name.contains('Salt'))
          .toList();
      expect(worlds, isEmpty, reason: 'no partial row must be written');
    });
  });
}
