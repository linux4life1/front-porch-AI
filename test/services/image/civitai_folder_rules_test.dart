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
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/image/studio_model_roots.dart';

import 'civitai_test_server.dart';

/// Symbolic links and POSIX paths like `/etc`: not something a Windows runner
/// can be assumed to allow (links need developer mode there).
final Object _noLinks = Platform.isWindows
    ? 'POSIX-only: it makes symbolic links or names a Unix system folder'
    : false;

Directory _made(String prefix) {
  final dir = Directory.systemTemp.createTempSync(prefix);
  addTearDown(() => dir.deleteSync(recursive: true));
  return Directory(dir.resolveSymbolicLinksSync());
}

void main() {
  group('the rule', () {
    late Directory home;
    late Directory elsewhere;

    // Resolved, as the app's own paths are: a temp folder is otherwise spelled
    // with a short name on Windows and behind a link on macOS.
    setUp(() {
      home = _made('civitai-home');
      elsewhere = _made('civitai-else');
    });

    /// [roots] are resolved paths, as the app stores them.
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
      'folders the system reads at login are refused though they have no dot',
      () async {
        final library = Directory(p.join(home.path, 'Library', 'LaunchAgents'))
          ..createSync(recursive: true);
        final appData = Directory(
          p.join(home.path, 'AppData', 'Roaming', 'Microsoft'),
        )..createSync(recursive: true);
        final ordinary = Directory(p.join(home.path, 'Documents', 'models'))
          ..createSync(recursive: true);
        final sensitive = [
          p.join(home.path, 'Library'),
          p.join(home.path, 'AppData', 'Roaming'),
        ];
        Future<bool> check(String folder, {List<String> roots = const []}) =>
            civitaiFolderIsSafe(
              folder,
              home: home.path,
              systemFolders: const [],
              sensitiveFolders: sensitive,
              roots: roots,
            );

        expect(await check(library.path), isFalse);
        expect(await check(library.parent.path), isFalse);
        expect(await check(appData.path), isFalse);
        expect(await check(ordinary.path), isTrue);
        // A models folder the person chose in one of them still works.
        expect(await check(library.path, roots: [library.parent.path]), isTrue);
      },
    );

    test(
      'on Windows a home folder is judged by its own AppData, not the environment\'s',
      () {
        // A test's or a copy's home folder inside the real app data folder
        // (the temp folder is one) must not make everything in it refused.
        expect(
          civitaiSensitiveHomeFolders(
            home: r'C:\Users\RUNNER~1\AppData\Local\Temp\home',
            os: 'windows',
            env: {
              'APPDATA': r'C:\Users\runneradmin\AppData\Roaming',
              'LOCALAPPDATA': r'C:\Users\runneradmin\AppData\Local',
            },
          ),
          [
            r'C:\Users\RUNNER~1\AppData\Local\Temp\home\AppData\Roaming',
            r'C:\Users\RUNNER~1\AppData\Local\Temp\home\AppData\Local',
          ],
        );
        // The environment's own, when it is inside the home folder, once.
        expect(
          civitaiSensitiveHomeFolders(
            home: r'C:\Users\a',
            os: 'windows',
            env: {'APPDATA': r'c:\users\A\appdata\roaming'},
          ),
          [r'c:\users\A\appdata\roaming', r'C:\Users\a\AppData\Local'],
        );
      },
    );

    test('the home folder is USERPROFILE on Windows, HOME elsewhere', () {
      final env = {'HOME': '/c/Users/a', 'USERPROFILE': r'C:\Users\a'};
      expect(civitaiHomeFolder(env: env, os: 'windows'), r'C:\Users\a');
      expect(civitaiHomeFolder(env: env, os: 'linux'), '/c/Users/a');
      expect(
        civitaiHomeFolder(env: {'USERPROFILE': r'C:\Users\a'}, os: 'linux'),
        r'C:\Users\a',
      );
      expect(civitaiHomeFolder(env: {}, os: 'windows'), isEmpty);
    });

    test('which folders those are, on each OS', () {
      expect(
        civitaiSensitiveHomeFolders(home: '/Users/a', os: 'macos', env: {}),
        [p.join('/Users/a', 'Library')],
      );
      expect(
        civitaiSensitiveHomeFolders(
          os: 'windows',
          env: {
            'APPDATA': r'C:\U\a\AppData\Roaming',
            'LOCALAPPDATA': r'C:\U\a\AppData\Local',
          },
        ),
        [r'C:\U\a\AppData\Roaming', r'C:\U\a\AppData\Local'],
      );
      expect(civitaiSensitiveHomeFolders(os: 'windows', env: {}), isEmpty);
      expect(
        civitaiSensitiveHomeFolders(home: '/home/a', os: 'linux', env: {}),
        isEmpty,
      );
    });

    test(
      'a hidden folder outside the home folder is not the rule\'s business',
      () async {
        final hidden = Directory(p.join(elsewhere.path, '.models'))
          ..createSync();
        expect(await safe(hidden.path), isTrue);
      },
    );

    test(
      'inside a root, by spelling, is for the models folder\'s own kinds',
      () {
        expect(civitaiFolderInRoots('/m/checkpoints', ['/m']), isTrue);
        expect(civitaiFolderInRoots('/m', ['/m']), isTrue);
        expect(civitaiFolderInRoots('/m2/checkpoints', ['/m']), isFalse);
        expect(civitaiFolderInRoots('/m/../etc', ['/m']), isFalse);
        expect(civitaiFolderInRoots('/m/a', ['', '/x', '/m']), isTrue);
        expect(civitaiFolderInRoots('/m/a', const []), isFalse);
      },
    );
  });

  group('a link inside a models folder', () {
    late Directory home;
    late Directory root;
    late Directory ssh;

    setUp(() {
      home = _made('civitai-home');
      root = _made('civitai-root');
      ssh = Directory(p.join(home.path, '.ssh'))..createSync();
      // The person's checkpoints folder is a link, and it leads to ~/.ssh.
      Link(p.join(root.path, 'checkpoints')).createSync(ssh.path);
    });

    Future<bool> safe(String folder, List<String> roots) => civitaiFolderIsSafe(
      folder,
      home: home.path,
      systemFolders: const [],
      roots: roots,
    );

    test('that leads to a hidden home folder is refused', () async {
      final folder = p.join(root.path, 'checkpoints');

      expect(await safe(folder, [root.path]), isFalse);
      expect(await safe(p.join(folder, 'not', 'yet'), [root.path]), isFalse);
    });

    test(
      'that leads to an ordinary folder is fine, even on another drive',
      () async {
        final other = _made('civitai-drive');
        Link(p.join(root.path, 'loras')).createSync(other.path);

        expect(await safe(p.join(root.path, 'loras'), [root.path]), isTrue);
      },
    );

    test(
      'the root itself may sit in a hidden folder the person chose',
      () async {
        final hidden = Directory(p.join(home.path, '.local', 'models'))
          ..createSync(recursive: true);

        expect(await safe(hidden.path, [hidden.path]), isTrue);
        expect(await safe(hidden.path, const []), isFalse);
      },
    );

    test(
      'a download through it is refused, and nothing is asked of CivitAI',
      () async {
        final host = await CivitaiFileHost.start();
        host.serve('/f', const [1, 2, 3]);

        final kind = await civitaiFailureOf(
          downloadCivitaiPlan(
            CivitaiDownloadPlan(
              uri: host.uri('/f'),
              path: p.join(root.path, 'checkpoints', 'm.safetensors'),
              authorization: 'Bearer test-token',
              log: 'civitai download account=local adult=false',
              refused: false,
              root: root.path,
              expectedBytes: 3,
              trustedRoots: [root.path],
            ),
            home: home.path,
          ),
        );

        expect(kind, CivitaiFailure.unsafe);
        expect(host.requests, isEmpty);
        expect(ssh.listSync(), isEmpty);
      },
    );
  }, skip: _noLinks);

  group('a saved models folder is trusted as it was when it was saved', () {
    late Directory home;
    late Directory ssh;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      home = _made('civitai-home');
      ssh = Directory(p.join(home.path, '.ssh'))..createSync();
    });

    test('a folder swapped for a link to ~/.ssh afterwards is not', () async {
      final root = Directory(p.join(_made('civitai-saved').path, 'models'))
        ..createSync();
      await rememberStudioModelRoot('comfyui', root.path);
      // Later, the folder is replaced by a link.
      root.deleteSync();
      Link(root.path).createSync(ssh.path);
      final host = await CivitaiFileHost.start();
      host.serve('/f', const [1, 2, 3]);

      final kind = await civitaiFailureOf(
        downloadCivitaiPlan(
          CivitaiDownloadPlan(
            uri: host.uri('/f'),
            path: p.join(root.path, 'checkpoints', 'm.safetensors'),
            authorization: 'Bearer test-token',
            log: 'civitai download account=local adult=false',
            refused: false,
            root: root.path,
            expectedBytes: 3,
            trustedRoots: await studioSavedModelRoots(),
          ),
          home: home.path,
        ),
      );

      expect(kind, CivitaiFailure.unsafe);
      expect(host.requests, isEmpty);
      expect(ssh.listSync(), isEmpty);
    }, skip: _noLinks);

    test('the folders come back as they resolved when saved', () async {
      final real = _made('civitai-real');
      final link = p.join(_made('civitai-links').path, 'via');
      Link(link).createSync(real.path);
      await rememberStudioModelRoot('comfyui', link);

      expect(await studioSavedModelRoots(), [real.path]);
    }, skip: _noLinks);

    test(
      'a folder the person chose to use is added, and only a safe one',
      () async {
        final mine = _made('civitai-mine');

        expect(await addTrustedModelFolder(mine.path), isTrue);
        expect(await addTrustedModelFolder(mine.path), isTrue);
        expect(await studioSavedModelRoots(), [mine.path]);

        expect(await addTrustedModelFolder('/etc'), isFalse);
        expect(await addTrustedModelFolder(''), isFalse);
        expect(await studioSavedModelRoots(), [mine.path]);
      },
      skip: _noLinks,
    );
  });

  group('a download', () {
    late Directory dir;
    late Directory home;
    late CivitaiFileHost host;
    late String models;
    late String farAway;
    final body = List<int>.generate(16, (i) => i);

    setUp(() async {
      dir = _made('civitai-rules');
      home = _made('civitai-rules-home');
      models = Directory(p.join(dir.path, 'models')).path;
      Directory(models).createSync();
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

    Future<CivitaiDownloadException> refusal(CivitaiDownloadPlan plan) async {
      try {
        await downloadCivitaiPlan(plan, home: home.path);
      } on CivitaiDownloadException catch (e) {
        return e;
      }
      fail('the download was expected to be refused');
    }

    test(
      'into a config folder outside the models folder is refused, and nothing is asked of CivitAI',
      () async {
        final e = await refusal(plan(p.join(farAway, 'm.safetensors')));

        expect(e.kind, CivitaiFailure.unsafe);
        expect(e.folder, farAway, reason: 'the desktop can offer to use it');
        expect(e.message, isNot(contains(farAway)));
        expect(host.requests, isEmpty);
        expect(Directory(farAway).existsSync(), isFalse);
      },
    );

    test(
      'into a config folder inside a models folder they saved lands',
      () async {
        Directory(farAway).createSync(recursive: true);
        final landed = await downloadCivitaiPlan(
          plan(p.join(farAway, 'm.safetensors'), trusted: [p.dirname(farAway)]),
          home: home.path,
        );

        expect(File(landed).readAsBytesSync(), body);
      },
    );

    test('into the models folder\'s own kind folder lands', () async {
      final landed = await downloadCivitaiPlan(
        plan(p.join(models, 'checkpoints', 'm.safetensors')),
        home: home.path,
      );

      expect(File(landed).readAsBytesSync(), body);
    });

    test(
      'into a hidden home folder is refused by that rule, not by the models-folder one',
      () async {
        final hidden = Directory(p.join(home.path, '.hidden', 'checkpoints'))
          ..createSync(recursive: true);

        final e = await refusal(plan(p.join(hidden.path, 'm.safetensors')));

        expect(e.kind, CivitaiFailure.unsafe);
        expect(e.message, contains('system folder'), reason: 'the safety rule');
        expect(e.folder, isNull, reason: 'and nothing is offered for it');
        expect(host.requests, isEmpty);
        expect(hidden.listSync(), isEmpty, reason: 'nothing was written');
      },
    );

    test('a hidden folder that does not exist is not made', () async {
      final missing = p.join(home.path, '.missing', 'checkpoints');

      final e = await refusal(plan(p.join(missing, 'm.safetensors')));

      expect(e.kind, CivitaiFailure.unsafe);
      expect(host.requests, isEmpty);
      expect(Directory(p.join(home.path, '.missing')).existsSync(), isFalse);
    });

    group('a checkpoint that turns out to carry its own encoders', () {
      final allInOne = civitaiSafetensors([
        'model.diffusion_model.double_blocks.0.w',
        'text_encoders.clip_l.transformer.w',
        'text_encoders.t5xxl.transformer.w',
        'vae.decoder.conv_in.w',
      ]);

      CivitaiDownloadPlan aioPlan(
        String home, {
        List<String> trusted = const [],
      }) {
        return CivitaiDownloadPlan(
          uri: host.uri('/aio'),
          path: p.join(models, 'diffusion_models', 'flux.safetensors'),
          authorization: 'Bearer test-token',
          log: 'civitai download account=local adult=false',
          refused: false,
          root: models,
          expectedBytes: allInOne.length,
          allInOnePath: p.join(home, 'checkpoints', 'flux.safetensors'),
          trustedRoots: trusted,
        );
      }

      setUp(() => host.serve('/aio', allInOne));

      test('goes to its own folder when that folder is fine', () async {
        final fine = Directory(p.join(models, 'more'))..createSync();
        final landed = await downloadCivitaiPlan(
          aioPlan(fine.path),
          home: home.path,
        );

        expect(landed, p.join(fine.path, 'checkpoints', 'flux.safetensors'));
        expect(File(landed).lengthSync(), allInOne.length);
      });

      test(
        'is refused, and nothing is kept, when that folder is a hidden home folder',
        () async {
          final hidden = Directory(p.join(home.path, '.hidden'))..createSync();

          final e = await refusal(aioPlan(hidden.path));

          expect(e.kind, CivitaiFailure.unsafe);
          expect(hidden.listSync(), isEmpty);
          // The part file it streamed into is gone too.
          expect(
            Directory(
              p.join(models, 'diffusion_models'),
            ).listSync().where((f) => f.path.endsWith('.fpai-part')),
            isEmpty,
          );
        },
      );
    });

    test(
      'a models folder the person chose inside a hidden home folder still works',
      () async {
        final root = Directory(p.join(home.path, '.local', 'models'))
          ..createSync(recursive: true);

        final landed = await downloadCivitaiPlan(
          plan(
            p.join(root.path, 'checkpoints', 'm.safetensors'),
            root: root.path,
            trusted: [root.path],
          ),
          home: home.path,
        );

        expect(File(landed).readAsBytesSync(), body);
      },
    );
  });
}
