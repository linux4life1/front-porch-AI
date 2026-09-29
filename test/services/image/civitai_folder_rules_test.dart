// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Where a download may be written. A folder the backend's config names for one
// kind of file was chosen by a config file, not the person, so it must be the
// models folder, one they saved, or inside one; and no download goes into a
// hidden folder of the home folder (~/.ssh, ~/.config) unless it is inside a
// models folder they chose.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/image/image.dart';

import 'civitai_test_server.dart';

void main() {
  group('the rule', () {
    late Directory home;
    late Directory elsewhere;

    setUp(() {
      home = Directory.systemTemp.createTempSync('civitai-home');
      elsewhere = Directory.systemTemp.createTempSync('civitai-else');
      addTearDown(() {
        home.deleteSync(recursive: true);
        elsewhere.deleteSync(recursive: true);
      });
    });

    Future<bool> safe(String folder, {List<String> roots = const []}) =>
        civitaiFolderIsSafe(
          folder,
          home: home.path,
          systemFolders: const [],
          roots: roots,
        );

    test(
      'a hidden folder of the home folder is refused, however deep',
      () async {
        for (final hidden in [
          '.ssh',
          p.join('.config', 'autostart'),
          p.join('.local', 'share', 'models'),
          p.join('Documents', '.cache', 'models'),
        ]) {
          final folder = Directory(p.join(home.path, hidden))
            ..createSync(recursive: true);
          expect(await safe(folder.path), isFalse, reason: hidden);
          expect(
            await safe(p.join(folder.path, 'not', 'yet')),
            isFalse,
            reason: '$hidden, a folder not made yet',
          );
        }
      },
    );

    test('an ordinary folder of the home folder is fine', () async {
      final models = Directory(p.join(home.path, 'Documents', 'models'))
        ..createSync(recursive: true);
      expect(await safe(models.path), isTrue);
    });

    test(
      'a hidden folder inside a models folder the person chose is fine',
      () async {
        final chosen = Directory(p.join(home.path, '.local', 'share', 'comfy'))
          ..createSync(recursive: true);
        final inside = p.join(chosen.path, 'models', 'checkpoints');

        expect(await safe(inside), isFalse);
        expect(await safe(inside, roots: [chosen.path]), isTrue);
        expect(await safe(chosen.path, roots: [chosen.path]), isTrue);
        // A sibling hidden folder is not the chosen one.
        final sibling = Directory(p.join(home.path, '.ssh'))..createSync();
        expect(await safe(sibling.path, roots: [chosen.path]), isFalse);
      },
    );

    test(
      'a hidden folder outside the home folder is not the rule\'s business',
      () async {
        final hidden = Directory(p.join(elsewhere.path, '.models'))
          ..createSync();
        expect(await safe(hidden.path), isTrue);
      },
    );

    test('inside a root is by its own spelling, not by where a link leads', () {
      expect(civitaiFolderInRoots('/m/checkpoints', ['/m']), isTrue);
      expect(civitaiFolderInRoots('/m', ['/m']), isTrue);
      expect(civitaiFolderInRoots('/m2/checkpoints', ['/m']), isFalse);
      expect(civitaiFolderInRoots('/m/../etc', ['/m']), isFalse);
      expect(civitaiFolderInRoots('/m/a', ['', '/x', '/m']), isTrue);
      expect(civitaiFolderInRoots('/m/a', const []), isFalse);
    });
  });

  group('a download', () {
    late Directory dir;
    late CivitaiFileHost host;
    late String models;
    late String farAway;
    final body = List<int>.generate(16, (i) => i);

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('civitai-rules');
      addTearDown(() => dir.deleteSync(recursive: true));
      models = Directory(p.join(dir.path, 'models')).path;
      farAway = p.join(dir.path, 'other', 'checkpoints');
      host = await CivitaiFileHost.start();
      host.serve('/f', body);
    });

    CivitaiDownloadPlan plan(
      String path, {
      String? root,
      List<String> trusted = const [],
    }) => CivitaiDownloadPlan(
      uri: host.uri('/f'),
      path: path,
      authorization: 'Bearer test-token',
      log: 'civitai download account=local adult=false',
      refused: false,
      root: root ?? models,
      expectedBytes: body.length,
      trustedRoots: trusted,
    );

    test(
      'into a config folder outside the models folder is refused, and nothing is asked of CivitAI',
      () async {
        final kind = await civitaiFailureOf(
          downloadCivitaiPlan(plan(p.join(farAway, 'm.safetensors'))),
        );

        expect(kind, CivitaiFailure.unsafe);
        expect(host.requests, isEmpty);
        expect(Directory(farAway).existsSync(), isFalse);
      },
    );

    test(
      'into a config folder inside a models folder they saved lands',
      () async {
        final landed = await downloadCivitaiPlan(
          plan(p.join(farAway, 'm.safetensors'), trusted: [p.dirname(farAway)]),
        );

        expect(File(landed).readAsBytesSync(), body);
      },
    );

    test('into the models folder\'s own kind folder lands', () async {
      final landed = await downloadCivitaiPlan(
        plan(p.join(models, 'checkpoints', 'm.safetensors')),
      );

      expect(File(landed).readAsBytesSync(), body);
    });

    final home = Platform.environment['HOME'] ?? '';

    test(
      'into a hidden folder of the real home folder is refused before anything is made',
      () async {
        final hidden = p.join(
          home,
          '.fpai-rules-${DateTime.now().microsecondsSinceEpoch}',
        );
        addTearDown(() {
          final left = Directory(hidden);
          if (left.existsSync()) left.deleteSync(recursive: true);
        });

        final kind = await civitaiFailureOf(
          downloadCivitaiPlan(
            plan(p.join(hidden, 'checkpoints', 'm.safetensors')),
          ),
        );

        expect(kind, CivitaiFailure.unsafe);
        expect(host.requests, isEmpty);
        expect(Directory(hidden).existsSync(), isFalse);
      },
      skip: home.isEmpty || Platform.isWindows,
    );

    test(
      'a models folder the person chose inside a hidden folder still works',
      () async {
        final hidden = p.join(
          home,
          '.fpai-rules-${DateTime.now().microsecondsSinceEpoch}',
        );
        addTearDown(() {
          final left = Directory(hidden);
          if (left.existsSync()) left.deleteSync(recursive: true);
        });
        // The person's models folder exists; the kind folder inside it may not.
        final root = Directory(p.join(hidden, 'models'))
          ..createSync(recursive: true);

        final landed = await downloadCivitaiPlan(
          plan(
            p.join(root.path, 'checkpoints', 'm.safetensors'),
            root: root.path,
          ),
        );

        expect(File(landed).readAsBytesSync(), body);
      },
      skip: home.isEmpty || Platform.isWindows,
    );
  });
}
