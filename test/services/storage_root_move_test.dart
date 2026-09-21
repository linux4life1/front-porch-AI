// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Guards for StorageService.setRootPath — "Change Data Directory", the one
// button that can move a user's entire library.
//
// 1. groups/ (every group member portrait) and custom_backgrounds/ hang
//    directly off the root and are resolved LIVE from it, so a move that
//    leaves them behind blanks them instantly and invites the user to delete
//    the "old" folder they are still living in.
// 2. The move is all-or-nothing and reports: a destination that already holds
//    a library is refused before anything is touched, and a failed copy leaves
//    the root exactly where it was rather than pointing the app (and the DB
//    path `<root>/KoboldManager/front_porch.db`) at data that never arrived.
// 3. A destination inside the current root (GTK on Linux sometimes returns
//    a subdirectory of the folder the picker is already sitting in) is
//    refused before anything is copied — otherwise the app copies the
//    library into a child of itself and then deletes the sources.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          if (call.method == 'getApplicationDocumentsDirectory') {
            return Directory.systemTemp.createTempSync('fpai_root_move_').path;
          }
          return null;
        });
  });

  Future<StorageService> freshStorage() async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.initialized;
    return storage;
  }

  void seed(String filePath, String contents) {
    final file = File(filePath);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
  }

  test('a root move carries group portraits and custom backgrounds', () async {
    final storage = await freshStorage();
    final oldRoot = storage.rootPath!;
    seed(
      p.join(oldRoot, 'groups', 'g1', 'avatars', 'ada.png'),
      'portrait bytes',
    );
    seed(p.join(oldRoot, 'custom_backgrounds', 'porch.png'), 'background');
    seed(p.join(oldRoot, 'KoboldManager', 'front_porch.db'), 'db');

    // Backgrounds remember an ABSOLUTE path, so moving the file is only half
    // the job. One inside the root (must be repointed) and one outside it
    // (must be left exactly as the user set it).
    final outside = Directory.systemTemp.createTempSync('fpai_outside_bg_');
    addTearDown(() => outside.deleteSync(recursive: true));
    seed(p.join(outside.path, 'elsewhere.png'), 'not ours');
    await storage.uiSettings.addCustomBackground(
      'bg1',
      'Porch',
      p.join(oldRoot, 'custom_backgrounds', 'porch.png'),
    );
    await storage.uiSettings.addCustomBackground(
      'bg2',
      'Elsewhere',
      p.join(outside.path, 'elsewhere.png'),
    );

    final newRoot = Directory.systemTemp.createTempSync('fpai_new_root_');
    addTearDown(() => newRoot.deleteSync(recursive: true));

    expect(await storage.setRootPath(newRoot.path), isNull);
    expect(storage.rootPath, newRoot.path);

    expect(
      File(
        p.join(newRoot.path, 'groups', 'g1', 'avatars', 'ada.png'),
      ).readAsStringSync(),
      'portrait bytes',
    );
    expect(
      File(
        p.join(newRoot.path, 'custom_backgrounds', 'porch.png'),
      ).readAsStringSync(),
      'background',
    );
    // Order kept, the one inside the root repointed, the outside one untouched.
    expect(storage.uiSettings.customBackgrounds.map((bg) => bg['id']), [
      'bg1',
      'bg2',
    ]);
    expect(
      storage.uiSettings.customBackgrounds.first['filePath'],
      p.join(newRoot.path, 'custom_backgrounds', 'porch.png'),
    );
    expect(
      File(
        storage.uiSettings.customBackgrounds.first['filePath']!,
      ).existsSync(),
      isTrue,
    );
    expect(
      storage.uiSettings.customBackgrounds.last['filePath'],
      p.join(outside.path, 'elsewhere.png'),
    );

    // The old copies are gone, so the user deleting the old folder loses
    // nothing.
    expect(Directory(p.join(oldRoot, 'groups')).existsSync(), isFalse);
    expect(
      Directory(p.join(oldRoot, 'custom_backgrounds')).existsSync(),
      isFalse,
    );
  });

  test(
    'a destination that already holds a library is refused intact',
    () async {
      final storage = await freshStorage();
      final oldRoot = storage.rootPath!;
      seed(p.join(oldRoot, 'KoboldManager', 'front_porch.db'), 'the real db');
      seed(p.join(oldRoot, 'chats', 'c1.json'), 'chat');

      final newRoot = Directory.systemTemp.createTempSync(
        'fpai_occupied_root_',
      );
      addTearDown(() => newRoot.deleteSync(recursive: true));
      seed(p.join(newRoot.path, 'KoboldManager', 'front_porch.db'), 'stale db');

      final reason = await storage.setRootPath(newRoot.path);
      expect(reason, isNotNull);
      expect(reason, contains('KoboldManager'));

      // Nothing moved, nothing merged, and the app still points at the library
      // it was using.
      expect(storage.rootPath, oldRoot);
      expect(
        File(
          p.join(oldRoot, 'KoboldManager', 'front_porch.db'),
        ).readAsStringSync(),
        'the real db',
      );
      expect(File(p.join(oldRoot, 'chats', 'c1.json')).existsSync(), isTrue);
      expect(
        File(
          p.join(newRoot.path, 'KoboldManager', 'front_porch.db'),
        ).readAsStringSync(),
        'stale db',
      );
      expect(Directory(p.join(newRoot.path, 'chats')).existsSync(), isFalse);
    },
  );

  test('a failed copy leaves the root where it was', () async {
    if (Platform.isWindows) {
      markTestSkipped(
        'read-only dirs are not enforced the same way on Windows',
      );
      return;
    }
    final storage = await freshStorage();
    final oldRoot = storage.rootPath!;
    seed(p.join(oldRoot, 'KoboldManager', 'front_porch.db'), 'the real db');

    final newRoot = Directory.systemTemp.createTempSync('fpai_readonly_root_');
    addTearDown(() {
      Process.runSync('chmod', ['u+w', newRoot.path]);
      newRoot.deleteSync(recursive: true);
    });
    Process.runSync('chmod', ['555', newRoot.path]);
    try {
      Directory(p.join(newRoot.path, 'probe')).createSync();
      markTestSkipped('running as root — a read-only directory proves nothing');
      return;
    } catch (_) {
      // Good: the destination really is unwritable.
    }

    final reason = await storage.setRootPath(newRoot.path);
    expect(reason, isNotNull);
    expect(storage.rootPath, oldRoot);
    expect(
      File(
        p.join(oldRoot, 'KoboldManager', 'front_porch.db'),
      ).readAsStringSync(),
      'the real db',
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('root_path'), isNot(newRoot.path));
  });

  test('a child-of-current-root is refused, sources untouched', () async {
    final storage = await freshStorage();
    final oldRoot = storage.rootPath!;
    seed(p.join(oldRoot, 'KoboldManager', 'front_porch.db'), 'the real db');
    seed(p.join(oldRoot, 'chats', 'c1.json'), 'chat');
    seed(
      p.join(oldRoot, 'groups', 'g1', 'avatars', 'ada.png'),
      'portrait bytes',
    );

    // GTK on Linux sometimes hands back a subdirectory of the current
    // root (the picker is already sitting in it). Copying the library
    // into a child of itself then deleting the sources splits data
    // across two folders.
    final nested = p.join(oldRoot, 'FrontPorchAI');

    final reason = await storage.setRootPath(nested);
    expect(reason, isNotNull);

    // Nothing moved, nothing created, and the app still points at the
    // library it was using.
    expect(storage.rootPath, oldRoot);
    expect(
      File(
        p.join(oldRoot, 'KoboldManager', 'front_porch.db'),
      ).readAsStringSync(),
      'the real db',
    );
    expect(File(p.join(oldRoot, 'chats', 'c1.json')).existsSync(), isTrue);
    expect(
      File(p.join(oldRoot, 'groups', 'g1', 'avatars', 'ada.png')).existsSync(),
      isTrue,
    );
    expect(Directory(nested).existsSync(), isFalse);
  });
}
