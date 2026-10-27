// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Starter worlds (assets/worlds/starter): every bundle decodes through the
// real .fpworld decoder, the two hand-authored climates validate, and each
// one imports through WorldRepository.importWorldJson as a root with three
// places whose climates, traits and lore resolve the way the engine reads
// them (docs/design/locations-within-worlds.md §3).

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/fp_world_package.dart';
import 'package:front_porch_ai/models/world.dart' as model;
import 'package:front_porch_ai/services/chat/lorebook_collection.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/world_injection.dart';
import 'package:front_porch_ai/services/chat/scene/scene_backdrop.dart';
import 'package:front_porch_ai/services/chat/weather_biomes.dart';
import 'package:front_porch_ai/services/starter_worlds.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/world_repository.dart';
import 'package:front_porch_ai/utils/world_cover.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_docs_').path;
        }
        return null;
      });
}

/// Words that would tie a starter to someone else's fiction. Matched as
/// whole words, case-insensitive.
const _denylist = [
  'Hogwarts',
  'Konoha',
  'Jedi',
  'Sith',
  'Pokémon',
  'Pokemon',
  'Gotham',
  'Middle-earth',
  'Mordor',
  'Starfleet',
  'Hyrule',
  'Narnia',
  'Westeros',
  'Tatooine',
  'Azeroth',
  'Tamriel',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late WorldRepository repo;
  late StarterWorlds starters;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting();
    await db.select(db.characters).get();
    final storage = StorageService();
    await storage.setRootPath(
      Directory.systemTemp.createTempSync('fpai_root_').path,
    );
    repo = WorldRepository(storage, db);
    await repo.loadWorlds();
    starters = StarterWorlds(repo);
  });

  tearDown(() => db.close());

  List<model.World> placesIn(model.World root) =>
      repo.placeWorlds.where((w) => w.parentWorldId == root.id).toList();

  model.World named(model.World root, String name) =>
      placesIn(root).singleWhere((w) => w.name == name);

  group('the bundle', () {
    test('the index lists seven worlds and every file is in it', () async {
      final index = await starters.index();
      expect(index.map((w) => w.id), [
        'whitereach',
        'kestrel-reach',
        'verdance-basin',
        'monsoon-coast',
        'harborside',
        'long-road',
        'greenhollow',
      ]);
      // No orphan file ships that the picker can never offer.
      final onDisk = Directory(StarterWorlds.kAssetDir)
          .listSync()
          .map((f) => f.uri.pathSegments.last)
          .where((n) => n.endsWith('.fpworld'))
          .map((n) => n.substring(0, n.length - '.fpworld'.length))
          .toSet();
      expect(onDisk, index.map((w) => w.id).toSet());
    });

    test(
      'every index row matches its bundle as the decoder reads it',
      () async {
        for (final info in await starters.index()) {
          final pkg = decodeFpWorld(await starters.package(info.id));
          final children = [for (final c in pkg.locations) decodeFpWorld(c)];
          expect(pkg.world.name, info.name, reason: info.id);
          expect(pkg.world.climateEnabled, isTrue, reason: info.id);
          expect(pkg.biome, isNotNull, reason: info.id);
          final rootBiome = Biome.fromJson(pkg.biome!);
          expect(rootBiome.displayName, info.climate, reason: info.id);
          expect(
            Biome.builtInById(rootBiome.id) == null,
            info.customClimate,
            reason: info.id,
          );
          expect(children, hasLength(info.places), reason: info.id);
          expect(
            children.where((c) => c.biome != null).length,
            info.ownClimates,
            reason: info.id,
          );
          for (final c in children.where((c) => c.biome != null)) {
            expect(
              Biome.builtInById(Biome.fromJson(c.biome!).id),
              isNotNull,
              reason: '${c.world.name}: places own built-in climates',
            );
          }
          expect(
            pkg.world.lorebook.entries.length +
                children.fold<int>(
                  0,
                  (n, c) => n + c.world.lorebook.entries.length,
                ),
            info.loreEntries,
            reason: info.id,
          );
        }
      },
    );

    test('both hand-authored climates pass the climate validator', () async {
      for (final id in ['whitereach', 'kestrel-reach']) {
        final pkg = decodeFpWorld(await starters.package(id));
        final biome = Biome.fromJson(pkg.biome!);
        expect(biome.validate(), isEmpty, reason: id);
        expect(biome.feel, isNotEmpty, reason: id);
      }
      final moon = Biome.fromJson(
        decodeFpWorld(await starters.package('kestrel-reach')).biome!,
      );
      expect(moon.id, 'starter_airless');
      // Pinned to the coldest band, with a display °C for every season.
      expect(moon.bandRange, (-1, -1));
      expect(moon.displayAnchorsC.keys, containsAll(kSeasons));
    });

    test(
      'text is original, set and short enough for the Setting budget',
      () async {
        final words = RegExp(
          '\\b(${_denylist.map(RegExp.escape).join('|')})\\b',
          caseSensitive: false,
        );
        for (final info in await starters.index()) {
          expect(info.blurb.trim(), isNotEmpty, reason: info.id);
          expect(words.hasMatch(info.blurb), isFalse, reason: info.blurb);
          final raw = await rootBundle.loadString(
            '${StarterWorlds.kAssetDir}/${info.id}.fpworld',
          );
          expect(
            words.firstMatch(raw)?.group(0),
            isNull,
            reason: '${info.id} names someone else\'s fiction',
          );
          expect(raw, isNot(contains('{{')), reason: info.id);
          final pkg = decodeFpWorld(await starters.package(info.id));
          for (final w in [
            pkg.world,
            for (final c in pkg.locations) decodeFpWorld(c).world,
          ]) {
            expect(w.description.trim(), isNotEmpty, reason: w.name);
            expect(
              w.description.length,
              lessThanOrEqualTo(600),
              reason: '${w.name} is over the 600-char Setting budget',
            );
          }
        }
      },
    );
  });

  group('adding through the file importer', () {
    test('each starter lands as one root with three places', () async {
      for (final info in await starters.index()) {
        final root = await starters.add(info.id);
        expect(root.parentWorldId, isNull, reason: info.id);
        expect(root.sourceId, StarterWorlds.sourceIdFor(info.id));
        expect(repo.worldById(root.id), isNotNull, reason: info.id);
        final places = placesIn(root);
        expect(places, hasLength(3), reason: info.id);
        expect(places.every((p) => p.parentWorldId == root.id), isTrue);
        expect(starters.isAdded(info.id), isTrue, reason: info.id);
      }
      expect(repo.placeWorlds, hasLength(28));
    });

    test('The Whitereach: a custom tundra over three towns that own '
        'comfortable built-in climates', () async {
      final root = await starters.add('whitereach');
      expect(root.biomeJson, isNotNull);
      expect(repo.climateAuthorFor(root.id)?.id, root.id);
      expect(
        Biome.resolve(biomeId: root.biomeId, biomeJson: root.biomeJson).id,
        'starter_tundra',
      );
      for (final (name, biome) in [
        ('Hearthford', 'temperate'),
        ('Thawwater Springs', 'mediterranean'),
        ('Emberlight', 'continental'),
      ]) {
        final town = named(root, name);
        expect(town.climateEnabled, isTrue, reason: name);
        expect(repo.climateAuthorFor(town.id)?.id, town.id, reason: name);
        expect(town.biomeId, biome, reason: name);
        expect(town.biomeJson, isNull, reason: '$name stores a built-in id');
      }
    });

    test('Kestrel Reach: each place reads the air and gravity of its '
        'climate author', () async {
      final root = await starters.add('kestrel-reach');
      expect(root.biomeJson, isNotNull);
      expect(
        Biome.resolve(biomeId: root.biomeId, biomeJson: root.biomeJson).id,
        'starter_airless',
      );
      for (final (name, author, air, gravity) in [
        (
          'Dome Town Meridian',
          'Dome Town Meridian',
          model.WorldAtmosphere.breathable,
          model.WorldGravity.low,
        ),
        (
          'The Ring',
          'The Ring',
          model.WorldAtmosphere.breathable,
          model.WorldGravity.earth,
        ),
        (
          'Outpost Nine',
          'Kestrel Reach',
          model.WorldAtmosphere.unbreathable,
          model.WorldGravity.low,
        ),
      ]) {
        final place = named(root, name);
        final resolved = repo.climateAuthorFor(place.id);
        expect(resolved?.name, author, reason: name);
        expect(resolved?.atmosphere, air, reason: name);
        expect(resolved?.gravity, gravity, reason: name);
      }
      expect(named(root, 'Outpost Nine').climateEnabled, isFalse);
    });

    test('Kestrel Reach: the Setting block tells the model each place\'s '
        'own air and gravity', () async {
      final root = await starters.add('kestrel-reach');
      String setting(String name) =>
          buildWorldInjection(repo.chainFor(named(root, name).id));
      final unbreathable = atmosphereLine(model.WorldAtmosphere.unbreathable)!;
      final low = gravityLine(model.WorldGravity.low)!;

      final ring = setting('The Ring');
      expect(ring, contains('An orbital habitat shaped like a great wheel'));
      expect(ring, isNot(contains(low)), reason: 'the Ring is spun to weight');
      expect(ring, isNot(contains(unbreathable)));
      expect(ring, isNot(contains('Gravity is')));

      final outpost = setting('Outpost Nine');
      expect(outpost, contains(unbreathable));
      expect(outpost, contains(low));

      final dome = setting('Dome Town Meridian');
      expect(dome, contains(low), reason: 'the dome keeps the moon\'s pull');
      expect(dome, isNot(contains(unbreathable)));
    });

    test('Greenhollow: a room as the Setting brings its own lore first, '
        'then the house\'s', () async {
      final root = await starters.add('greenhollow');
      expect(root.lorebook.entries, hasLength(6));
      final kitchens = named(root, 'The Kitchens');
      expect(kitchens.climateEnabled, isFalse);
      final refs = collectLoreEntryRefs(
        characters: const [],
        chatWorldIds: [kitchens.id],
        resolveWorld: repo.resolveWorld,
        settingChain: repo.chainFor(kitchens.id),
      );
      final labels = refs.map((r) => r.sourceLabel).toList();
      final room = labels.indexOf('world:The Kitchens');
      final house = labels.indexOf('world:Greenhollow Estate');
      expect(room, isNonNegative, reason: 'the room\'s own entries');
      expect(house, isNonNegative, reason: 'the estate\'s entries');
      expect(room, lessThan(house), reason: 'leaf first');
      expect(refs[room].placeRank, 0);
      expect(refs[house].placeRank, 1);
      expect(
        refs.map((r) => r.entry.name),
        containsAll(['The bread oven', 'The locked library']),
      );
    });

    test('adding twice keeps both copies with numbered names', () async {
      final first = await starters.add('harborside');
      final second = await starters.add('harborside');
      expect(second.id, isNot(first.id));
      expect(first.name, 'Harborside');
      expect(second.name, 'Harborside (2)');
      expect(placesIn(second).map((w) => w.name), contains('The Quay (2)'));
      expect(repo.placeWorlds, hasLength(8));
    });

    test('a second add while the first is writing joins it', () async {
      final both = await Future.wait([
        starters.add('harborside'),
        starters.add('harborside'),
      ]);
      expect(both[0].id, both[1].id);
      expect(repo.placeWorlds, hasLength(4));
    });

    test('an id outside the index never reaches the asset path', () async {
      await expectLater(starters.add('../index'), throwsArgumentError);
      await expectLater(starters.add('nope'), throwsArgumentError);
      expect(repo.placeWorlds, isEmpty);
    });
  });

  group('where chats start', () {
    test('every starter world lands with a starting place inside it', () async {
      for (final info in await starters.index()) {
        final root = await starters.add(info.id);
        final start = repo.startingPlaceFor(root.id)!;
        expect(start.id, isNot(root.id), reason: info.id);
        expect(start.parentWorldId, root.id, reason: info.id);
      }
      final harbor = repo.placeWorlds.firstWhere((w) => w.name == 'Harborside');
      expect(repo.startingPlaceFor(harbor.id)?.name, 'The Quay');
    });
  });

  group('pictures', () {
    test('every starter world and place lands with its own cover, and a '
        'chat in a place shows that place\'s picture', () async {
      for (final info in await starters.index()) {
        final root = await starters.add(info.id);
        final covered = [root, ...placesIn(root)];
        for (final w in covered) {
          expect(isWorldCoverDataUrl(w.coverImage), isTrue, reason: w.name);
          final bytes = decodeWorldCoverBytes(w.coverImage);
          expect(bytes, isNotNull, reason: w.name);
          expect(bytes!.length, lessThanOrEqualTo(kWorldCoverMaxBytes));
          final image = img.decodeJpg(bytes);
          expect(image, isNotNull, reason: '${w.name}: a real JPEG');
          expect(
            math.max(image!.width, image.height),
            lessThanOrEqualTo(kWorldCoverMaxEdge),
            reason: w.name,
          );
        }
        expect(
          covered.map((w) => w.coverImage).toSet(),
          hasLength(covered.length),
          reason: '${info.id}: each place has a picture of its own',
        );
        for (final place in placesIn(root)) {
          final backdrop = sceneBackdropOf(repo.chainFor(place.id));
          expect(backdrop?.placeId, place.id, reason: place.name);
        }
      }
    });
  });
}
