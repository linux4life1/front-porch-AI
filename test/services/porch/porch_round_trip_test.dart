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

// .porch / .porchpack ROUND TRIP (issue #348), file to file, between two
// separate libraries: characters with a lorebook, a gallery look, an
// expression image, the ★ star and a real chat go out of one library and
// come back whole in a fresh one. A second import skips what is already
// there and says so by name. Damaged, renamed and foreign files are refused
// in plain words.
//
// Red-proved: without the skip rule both skip cases fail; without pointing
// the star at the new look its id stays the old library's; without the
// version check a version-99 pack is not called newer; without removing the
// greeting chat that opening a fresh card saves, the imported character has
// two chats instead of one.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/porch/porch.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/utils.dart';
import 'porch_test_library.dart';

void main() {
  setUpPorchTestPlatform();

  late Directory tmp;
  late PorchTestLibrary a;
  late PorchTestLibrary b;

  setUp(() {
    resetPorchTestPrefs();
    tmp = Directory.systemTemp.createTempSync('fpai_porch_rt_');
    a = PorchTestLibrary('${tmp.path}/library-a');
    b = PorchTestLibrary('${tmp.path}/library-b');
  });

  tearDown(() async {
    await a.close();
    await b.close();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> drain(PorchTestLibrary lib) async {
    for (
      var i = 0;
      i < 400 && (lib.chat.isGenerating || lib.chat.isSettlingTurn);
      i++
    ) {
      await Future<void>.delayed(Duration.zero);
    }
    for (var i = 0; i < 50; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// Export [names] from [lib] and write the file to disk, as Save would.
  Future<File> exportToDisk(PorchTestLibrary lib, List<String> names) async {
    final out = await lib.exporter.exportCards([
      for (final n in names) lib.named(n),
    ]);
    return File('${tmp.path}/${out.fileName}')..writeAsBytesSync(out.bytes);
  }

  Future<PorchImportReport> importFromDisk(
    PorchTestLibrary lib,
    List<File> files,
  ) {
    return lib.importer.importFiles([
      for (final f in files)
        (name: f.uri.pathSegments.last, bytes: f.readAsBytesSync()),
    ]);
  }

  test('three characters go out as one .porchpack and come back whole in a '
      'fresh library; a second import skips them by name', () async {
    final aria = await a.seed('Aria Vale', 1);
    await a.seed('Bram Elder', 2);
    await a.seed('Cora Lind', 3);

    // A look (starred) and an expression image for Aria.
    final lookId = await a.repo.addLook(
      aria.dbId!,
      aria.name,
      porchTestPicture(4),
    );
    await a.repo.addAvatar(aria.dbId!, aria.name, porchTestPicture(5), 'happy');
    aria.frontPorchExtensions = FrontPorchExtensions()
      ..favoriteAvatarId = lookId;
    await a.repo.updateCharacter(aria);

    // One real turn with Aria, and a Journal card on that chat.
    await a.chat.setActiveCharacter(aria);
    await a.chat.sendMessage('Evening, Aria.');
    await drain(a);
    await a.chat.journalStore.addCard(
      sessionId: a.chat.currentSessionId!,
      characterId: aria.stableGroupId,
      content: 'She keeps the porch light on for late visitors.',
      category: 'moment',
      maxCards: 40,
    );

    final pack = await exportToDisk(a, [
      'Aria Vale',
      'Bram Elder',
      'Cora Lind',
    ]);
    expect(pack.path, endsWith('Front Porch characters (3).porchpack'));

    final first = await importFromDisk(b, [pack]);
    expect(first.refused, isEmpty, reason: first.message);
    expect(first.imported, ['Aria Vale', 'Bram Elder', 'Cora Lind']);
    expect(first.message, 'Imported 3 characters with 1 chat.');

    final ariaB = b.named('Aria Vale');
    expect(
      ariaB.lorebook?.entries.single.content,
      'Aria Vale knows every gate.',
    );
    expect(ariaB.stableGroupId, isNot(aria.stableGroupId));

    final avatars = await b.repo.getAvatarImages(ariaB.dbId!);
    final looks = avatars.where((x) => x.isLook).toList();
    final faces = avatars.where((x) => !x.isLook).toList();
    expect(looks, hasLength(1));
    expect(faces.single.label, 'happy');
    final base = b.storage.characterBaseDir(ariaB.name).path;
    expect(looks.single.resolveFile(base).existsSync(), isTrue);
    expect(faces.single.resolveFile(base).existsSync(), isTrue);
    expect(
      ariaB.frontPorchExtensions?.favoriteAvatarId,
      looks.single.id,
      reason: 'the ★ must point at the look in the new library',
    );

    final chats = await b.chat.getSessionsForId(ariaB.stableGroupId);
    expect(chats, hasLength(1), reason: 'only the chat that was exported');
    await b.chat.setActiveCharacter(ariaB);
    await b.chat.loadSession(chats.single['id'] as String);
    expect(
      b.chat.messages.map((m) => m.text).join('\n'),
      contains('Evening, Aria.'),
    );
    final diary = await b.chat.journalStore.cardsFor(
      b.chat.currentSessionId!,
      ariaB.stableGroupId,
    );
    expect(diary.map((c) => c.content), contains(contains('porch light')));

    final again = await importFromDisk(b, [pack]);
    expect(again.imported, isEmpty);
    expect(
      again.message,
      'Skipped 3 you already have: Aria Vale, Bram Elder, Cora Lind.',
    );
    expect(b.repo.characters, hasLength(3));
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('one character is one .porch; importing it where it already exists '
      'skips it', () async {
    await a.seed('Bram Elder', 2);
    final single = await exportToDisk(a, ['Bram Elder']);
    expect(single.path, endsWith('Bram Elder.porch'));

    final into = await importFromDisk(b, [single]);
    expect(into.imported, ['Bram Elder']);
    final back = await importFromDisk(a, [single]);
    expect(back.message, 'Skipped 1 you already have: Bram Elder.');
    expect(a.repo.characters, hasLength(1));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('damaged, renamed and foreign files are refused in plain words and '
      'change nothing', () async {
    await a.seed('Bram Elder', 2);
    await a.seed('Cora Lind', 3);
    final good = (await exportToDisk(a, ['Bram Elder'])).readAsBytesSync();
    final cora = (await exportToDisk(a, ['Cora Lind'])).readAsBytesSync();

    Uint8List zip(Map<String, String> files) {
      final archive = Archive();
      files.forEach((n, text) {
        final d = utf8.encode(text);
        archive.addFile(ArchiveFile(n, d.length, d));
      });
      return Uint8List.fromList(ZipEncoder().encode(archive));
    }

    final plainZip = zip({'notes.txt': 'just a zip'});
    final shortPack = Archive()
      ..addFile(ArchiveFile('Cora Lind.porch', cora.length, cora));
    final shortManifest = utf8.encode(
      '{"format":"fpai_porchpack","version":1,"entries":['
      '{"file":"Cora Lind.porch","name":"Cora Lind"},'
      '{"file":"Gone.porch","name":"Gone"}]}',
    );
    shortPack.addFile(
      ArchiveFile('manifest.json', shortManifest.length, shortManifest),
    );

    final report = await b.importer.importFiles([
      (name: 'junk.porch', bytes: Uint8List.fromList(List.filled(300, 7))),
      (name: 'Bram Elder.porch', bytes: good.sublist(0, good.length ~/ 2)),
      (name: 'renamed.porch', bytes: plainZip),
      (name: 'renamed.porchpack', bytes: plainZip),
      (
        name: 'future.porchpack',
        bytes: zip({
          'manifest.json':
              '{"format":"fpai_porchpack","version":99,"entries":[]}',
        }),
      ),
      (
        name: 'short.porchpack',
        bytes: Uint8List.fromList(ZipEncoder().encode(shortPack)),
      ),
      (name: 'Aria.png', bytes: porchTestPicture(1)),
      (name: 'pack.zip', bytes: plainZip),
    ]);

    expect(report.imported, isEmpty);
    expect(b.repo.characters, isEmpty);
    expect(report.refused, [
      contains('“junk.porch” couldn’t be opened'),
      contains('“Bram Elder.porch” couldn’t be opened'),
      contains('“renamed.porch” isn’t a Front Porch character file'),
      contains('“renamed.porchpack” is missing its list of characters'),
      contains('“future.porchpack” was made by a newer Front Porch AI'),
      contains('“short.porchpack” is incomplete: 1 of its 2 characters'),
      contains('“Aria.png” isn’t a .porch or .porchpack file'),
      contains('“pack.zip” isn’t a .porch or .porchpack file'),
    ]);
    for (final line in report.refused) {
      expect(line, isNot(contains('Exception')));
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
