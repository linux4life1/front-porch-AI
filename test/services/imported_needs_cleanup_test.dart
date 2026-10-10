// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Before #454 every card save wrote `needs_sim_enabled: false`, and the
// importer saves each card it imports, so every plain card imported before
// it says "no Needs" and ignores the Porch Life switch. The app clears that
// stamp from imported cards once, in the background, after the library loads
// (maintainer ruling 2026-10-10). Cards made in the app keep their choice.
//
// Real StorageService, CharacterRepository, importer and PNG files in a temp
// library; in-memory database shared across "launches".

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart' show Pockets;
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/utils.dart' show PngMetadataUtils;
import '../helpers/chat_db_teardown.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory docs;
  // Holds the storage root back, as a slow first read of it would.
  Future<void>? rootArrives;
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          await rootArrives;
          return docs.path;
        }
        return null;
      });

  late AppDatabase db;
  ChatService? chat;

  setUp(() {
    rootArrives = null;
    docs = Directory.systemTemp.createTempSync('fpai_import_stamp_');
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': true,
      'needs_sim_default': true,
      'passage_of_time_default': true,
    });
    db = AppDatabase.forTesting(sameIsolate: true);
  });

  tearDown(() async {
    await disposeChatThenCloseDb(chat, db);
    chat = null;
  });

  /// A launch of an app from before the clean-up: no clean-up runs.
  Future<(StorageService, CharacterRepository)> oldAppLaunch() async {
    final storage = StorageService();
    final repo = CharacterRepository(db, storage);
    await storage.initialized;
    await repo.whenLoaded;
    return (storage, repo);
  }

  /// A launch of this app, built the way main.providers builds it.
  Future<(CharacterRepository, ImportedNeedsCleanupResult?)> launch() async {
    final storage = StorageService();
    final repo = openCharacterRepository(db, storage);
    final result = await debugImportedNeedsCleanup;
    // A skipped run returns before the load; the test reads the list.
    await repo.whenLoaded;
    return (repo, result);
  }

  /// A Chub/SillyTavern-style card with no Front Porch block, imported by
  /// the real importer, then saved the way the importer saved it before #454
  /// (its `toJson` wrote the explicit false).
  Future<CharacterCard> importedTheOldWay(
    CharacterRepository repo,
    String name, {
    bool largePortrait = false,
  }) async {
    final src = p.join(
      Directory.systemTemp.createTempSync('fpai_chub_').path,
      '$name.png',
    );
    final plain = CharacterCard(
      name: name,
      description: '$name keeps the bait shop by the river.',
      firstMessage: 'You came back.',
      alternateGreetings: const ['Oh. It is you.'],
      creator: 'someone_on_chub',
      creatorNotes: 'Slow burn.',
      characterVersion: '1.2',
      rawExtensions: {'talkativeness': '0.5', 'fav': false, 'world': ''},
      lorebook: Lorebook(
        entries: [LorebookEntry(name: 'River', key: 'river', content: 'Cold.')],
      ),
    );
    await V2CardService().saveCardAsPng(plain, src, null);
    final imported = (await repo.importCharacter(File(src)))!;
    imported.frontPorchExtensions!.needsSimChoice = false;
    await V2CardService().saveCardAsPng(
      imported,
      imported.imagePath!,
      imported.imagePath!,
    );
    if (largePortrait) {
      // The importer shrinks a big picture today; a card from before that,
      // or one copied into the folder by hand, keeps its full size. Same
      // card data, written around a 2100 x 2200 portrait.
      final chara = PngMetadataUtils.extractTextChunk(
        File(imported.imagePath!).readAsBytesSync(),
        'chara',
      )!;
      final big = img.Image(width: 2100, height: 2200);
      for (final px in big) {
        px
          ..r = px.x % 251
          ..g = px.y % 241
          ..b = (px.x * px.y) % 239;
      }
      File(imported.imagePath!).writeAsBytesSync(
        PngMetadataUtils.encodeWithTextChunk(big, 'chara', chara),
      );
    }
    expect(
      _realism(imported.imagePath!)['needs_sim_enabled'],
      isFalse,
      reason: 'fixture: the old importer stamp is on disk',
    );
    return imported;
  }

  /// Saved the way the manual creator saves a card (create_character_page
  /// .save.dart): every Realism field written, placeholder PNG, addCharacter.
  Future<CharacterCard> madeInTheApp(
    StorageService storage,
    CharacterRepository repo,
    String name, {
    required bool needs,
  }) async {
    final ext = FrontPorchExtensions(
      realismEnabled: true,
      passageOfTimeEnabled: true,
      needsSimEnabled: needs,
      inventory: Pockets.cardJsonFrom(worn: const [], carrying: const []),
    )..ensureStableId();
    final card = CharacterCard(
      name: name,
      description: '$name runs the diner.',
      firstMessage: 'Coffee?',
      frontPorchExtensions: ext,
    );
    final dir = storage.charactersDir..createSync(recursive: true);
    final path = p.join(
      dir.path,
      '${name}_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    card.imagePath = path;
    await V2CardService().saveCardAsPng(card, path, null);
    await repo.addCharacter(card);
    return card;
  }

  CharacterCard named(CharacterRepository repo, String name) =>
      repo.characters.firstWhere((c) => c.name == name);

  test(
    'an imported card stamped the old way follows the Porch Life Needs '
    'switch after the next launch; app-made cards keep their choice',
    () async {
      final (storage0, repo0) = await oldAppLaunch();
      final river = await importedTheOldWay(
        repo0,
        'River',
        largePortrait: true,
      );
      final dina = await madeInTheApp(storage0, repo0, 'Dina', needs: false);
      final otto = await madeInTheApp(storage0, repo0, 'Otto', needs: true);
      final riverBefore = _payload(river.imagePath!);
      final riverChunks = _otherChunks(river.imagePath!);
      final dinaBytes = File(dina.imagePath!).readAsBytesSync();
      final ottoBytes = File(otto.imagePath!).readAsBytesSync();
      final dinaTime = File(dina.imagePath!).lastModifiedSync();

      final (repo, result) = await launch();

      // On disk: the key is gone and nothing else in the card moved.
      final after = _payload(river.imagePath!);
      expect(
        _realismOf(after).containsKey('needs_sim_enabled'),
        isFalse,
        reason: 'the old importer stamp is still on the card',
      );
      expect(result!.cleared, 1);
      expect(result.skipped, 0);
      _realismOf(riverBefore).remove('needs_sim_enabled');
      expect(jsonEncode(after), jsonEncode(riverBefore));
      expect(
        _otherChunks(river.imagePath!),
        riverChunks,
        reason: 'the portrait was re-encoded, not left as it was',
      );
      final picture = img.decodePng(File(river.imagePath!).readAsBytesSync())!;
      expect([picture.width, picture.height], [2100, 2200]);
      expect(after['data']['creator'], 'someone_on_chub');

      // In memory, without another reload.
      expect(named(repo, 'River').frontPorchExtensions!.needsSimChoice, isNull);

      // App-made cards: byte for byte as they were.
      expect(File(dina.imagePath!).readAsBytesSync(), dinaBytes);
      expect(File(dina.imagePath!).lastModifiedSync(), dinaTime);
      expect(File(otto.imagePath!).readAsBytesSync(), ottoBytes);
      expect(named(repo, 'Dina').frontPorchExtensions!.needsSimChoice, isFalse);

      // Its new chat, Realism on and the Porch Life Needs switch on: Needs on.
      final storage = StorageService();
      await storage.initialized;
      chat =
          ChatService(
              KoboldService(storage),
              UserPersonaService(db),
              storage,
              WorldRepository(storage, db),
            )
            ..setDatabase(db)
            ..setCharacterRepository(repo);
      await chat!.setActiveCharacter(named(repo, 'River'));
      expect(chat!.realismEnabled, isTrue);
      expect(chat!.needsSimEnabled, isTrue, reason: 'River follows Porch Life');
      await chat!.setActiveCharacter(named(repo, 'Dina'));
      expect(chat!.needsSimEnabled, isFalse, reason: "Dina's own off stays");
    },
  );

  test('it runs once: a card set to off after it is left alone on every '
      'later launch', () async {
    final (_, repo0) = await oldAppLaunch();
    final river = await importedTheOldWay(repo0, 'River');
    final (repo1, first) = await launch();
    expect(first!.cleared, 1);

    // After the clean-up, the person switches Needs off on another imported
    // card; on disk that is the same shape as the old stamp.
    final mabel = await importedTheOldWay(repo1, 'Mabel');
    final mabelBytes = File(mabel.imagePath!).readAsBytesSync();
    final mabelTime = File(mabel.imagePath!).lastModifiedSync();
    final riverBytes = File(river.imagePath!).readAsBytesSync();

    final (repo2, second) = await launch();

    expect(second, isNull, reason: 'the once-only flag stopped the rerun');
    expect(File(mabel.imagePath!).readAsBytesSync(), mabelBytes);
    expect(File(mabel.imagePath!).lastModifiedSync(), mabelTime);
    expect(File(river.imagePath!).readAsBytesSync(), riverBytes);
    expect(named(repo2, 'Mabel').frontPorchExtensions!.needsSimChoice, isFalse);
  });

  test('a first library read that beat the storage root is read again '
      'before the clean-up decides', () async {
    final (_, repo0) = await oldAppLaunch();
    final river = await importedTheOldWay(repo0, 'River');

    final gate = Completer<void>();
    rootArrives = gate.future;
    final storage = StorageService();
    final repo = openCharacterRepository(db, storage);
    await repo.whenLoaded;
    expect(
      repo.libraryLoaded,
      isFalse,
      reason: 'fixture: the first pass ran with no storage root',
    );
    gate.complete();
    final result = await debugImportedNeedsCleanup;

    expect(
      _realism(river.imagePath!).containsKey('needs_sim_enabled'),
      isFalse,
      reason: 'the clean-up gave up on a library it never read',
    );
    expect(result!.cleared, 1);
    expect(named(repo, 'River').frontPorchExtensions!.needsSimChoice, isNull);
  });

  test('a card that could not be read keeps the clean-up coming back until '
      'it is cleared; a picture with no card data does not', () async {
    final (storage0, repo0) = await oldAppLaunch();
    final river = await importedTheOldWay(repo0, 'River');
    final bare = p.join(storage0.charactersDir.path, 'Bare_1.png');
    File(bare).writeAsBytesSync(img.encodePng(img.Image(width: 8, height: 8)));
    await repo0.addCharacter(CharacterCard(name: 'Bare', imagePath: bare));

    // River's file is away at launch (a sync folder still filling, a
    // locked disk): the library loads it with no settings.
    final away = '${river.imagePath!}.away';
    File(river.imagePath!).renameSync(away);
    final (repo1, first) = await launch();
    expect(named(repo1, 'River').frontPorchExtensions, isNull);
    expect(first!.skipped, 1);
    expect(first.cleared, 0);

    File(away).renameSync(river.imagePath!);
    final (repo2, second) = await launch();
    expect(
      second,
      isNotNull,
      reason: 'the skipped card set the once-only flag anyway',
    );
    expect(second!.cleared, 1);
    expect(second.skipped, 0);
    expect(
      _realism(river.imagePath!).containsKey('needs_sim_enabled'),
      isFalse,
    );
    expect(named(repo2, 'River').frontPorchExtensions!.needsSimChoice, isNull);

    final (_, third) = await launch();
    expect(third, isNull, reason: 'everything handled, so it is done');
  });

  test('a card whose PNG cannot be read is skipped and left where it is; a '
      'damaged picture keeps every byte but the card text', () async {
    final (_, repo) = await oldAppLaunch();
    final noData = await importedTheOldWay(repo, 'Garbled');
    final noPixels = await importedTheOldWay(repo, 'Cropped');
    final good = await importedTheOldWay(repo, 'River');
    // The library has loaded them; then the files go bad on disk.
    File(noData.imagePath!).writeAsBytesSync(utf8.encode('not a png'));
    final full = File(noPixels.imagePath!).readAsBytesSync();
    final idat = _indexOf(full, ascii.encode('IDAT'));
    File(noPixels.imagePath!).writeAsBytesSync(full.sublist(0, idat - 4));
    expect(
      await V2CardService().readCard(noPixels.imagePath!),
      isNotNull,
      reason: 'fixture: card data still reads, only the portrait is gone',
    );
    final garbled = File(noData.imagePath!).readAsBytesSync();
    final croppedChunks = _otherChunks(noPixels.imagePath!);

    final result = await clearImportedNeedsStamps(repo);

    expect(result.cleared, 2);
    expect(result.skipped, 1);
    expect(File(noData.imagePath!).readAsBytesSync(), garbled);
    expect(_otherChunks(noPixels.imagePath!), croppedChunks);
    expect(
      _realism(noPixels.imagePath!).containsKey('needs_sim_enabled'),
      isFalse,
    );
    expect(_realism(good.imagePath!).containsKey('needs_sim_enabled'), isFalse);
    expect(
      Directory(
        p.dirname(good.imagePath!),
      ).listSync().where((f) => f.path.endsWith('.tmp')),
      isEmpty,
      reason: 'no half-written file is left behind',
    );
  });
}

Map<String, dynamic> _payload(String path) {
  final chara = PngMetadataUtils.extractTextChunk(
    File(path).readAsBytesSync(),
    'chara',
  )!;
  return jsonDecode(utf8.decode(base64Decode(chara))) as Map<String, dynamic>;
}

Map<String, dynamic> _realismOf(Map<String, dynamic> payload) =>
    payload['data']['extensions']['front_porch']['realism_engine']
        as Map<String, dynamic>;

Map<String, dynamic> _realism(String path) => _realismOf(_payload(path));

/// Every chunk but the card's `chara` text, raw (length, type, data, CRC),
/// in file order. Stops at a cut-off chunk.
List<List<int>> _otherChunks(String path) {
  final bytes = File(path).readAsBytesSync();
  final chunks = <List<int>>[bytes.sublist(0, 8)];
  var offset = 8;
  while (offset + 12 <= bytes.length) {
    final length = ByteData.sublistView(bytes, offset, offset + 4).getUint32(0);
    final end = offset + 12 + length;
    if (end > bytes.length) break;
    final chunk = bytes.sublist(offset, end);
    final isChara =
        ascii.decode(chunk.sublist(4, 8)) == 'tEXt' &&
        latin1.decode(chunk.sublist(8, 14)) == 'chara\u0000';
    if (!isChara) chunks.add(chunk);
    offset = end;
  }
  return chunks;
}

int _indexOf(List<int> haystack, List<int> needle) {
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    var hit = true;
    for (var j = 0; j < needle.length && hit; j++) {
      hit = haystack[i + j] == needle[j];
    }
    if (hit) return i;
  }
  throw StateError('needle not found');
}
