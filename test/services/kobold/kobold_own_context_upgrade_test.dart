// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Clearing a preset when the app never kept the user's own context (ruling
// I, as the coordinator settled it on 2026-10-05). Someone who already had a
// preset chosen when the app started keeping their own number has nothing
// kept, so clearing it keeps the number in use, the preset's, but never
// below the 16,384 floor: a small preset's 8,192 must not be left behind.
// Every way a preset is cleared goes through the same place: the user, a
// model pick, and a launch that drops a preset whose file is gone or that the
// app itself wrote. A number the user kept is put back exactly as they had
// it, even under 16,384: it is theirs, and the below-16K warning still says
// what that means; putting it back is not suggesting it.
//
// Real preset files and a real preferences store; the launch is the real
// one, and nothing is spawned (the engine program is never there).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/kobold/kobold.dart';
import 'package:front_porch_ai/services/kobold_admin_swap.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/storage/settings/backend_settings.dart';
import 'package:front_porch_ai/services/storage_service.dart';

import '../kobold_service_test.dart' show setupPathProviderMock;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupPathProviderMock();

  late Directory dir;
  late String model;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('fpai own context upgrade');
    model = p.join(dir.path, 'model.gguf');
    File(model).writeAsBytesSync([...'GGUF'.codeUnits, 3, 0, 0, 0]);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  String preset(String name, int context, [String? folder]) => (File(
    p.join(folder ?? dir.path, name),
  )..writeAsStringSync(jsonEncode({'contextsize': context}))).path;

  /// What a user who chose [kcpps] before the app kept their own context
  /// has saved: the preset, and its context copied in.
  Map<String, Object> chosenBefore(String kcpps, int context) {
    final b = BackendSettings();
    return {
      b.k('backend_type'): 'kobold',
      b.k('active_kcpps_path'): kcpps,
      b.k('context_size'): context,
      b.k('last_used_model_path'): model,
    };
  }

  Future<BackendSettings> open(Map<String, Object> saved) async {
    SharedPreferences.setMockInitialValues(saved);
    return BackendSettings()
      ..initializeBase(await SharedPreferences.getInstance(), () {})
      ..load();
  }

  group('with no number of the user\'s own kept', () {
    test('clearing a small preset leaves 16,384, not its 8,192', () async {
      final s = await open(chosenBefore(preset('Small.kcpps', 8192), 8192));
      expect(s.contextSize, 8192);

      await s.setActiveKcppsPath(null);

      expect(s.contextSize, kKoboldContextFloor);
    });

    test('clearing a larger preset keeps its size', () async {
      final s = await open(chosenBefore(preset('Long.kcpps', 32768), 32768));

      await s.setActiveKcppsPath(null);

      expect(s.contextSize, 32768);
    });

    test('picking a model with no preset of its own does the same', () async {
      final storage = await _storage(
        chosenBefore(preset('S.kcpps', 8192), 8192),
      );
      final other = p.join(dir.path, 'other.gguf');
      File(other).writeAsBytesSync([...'GGUF'.codeUnits, 3, 0, 0, 0]);

      await selectKoboldModel(storage, other);

      expect(storage.backendSettings.contextSize, kKoboldContextFloor);
    });
  });

  test('with no preset chosen nothing is cleared: a number under 16,384 the '
      'user set stays', () async {
    final s = await open({});
    await s.setBackendType('kobold');
    await s.setContextSize(8192);

    await s.setActiveKcppsPath(null);

    expect(s.contextSize, 8192);
  });

  test(
    'a number the user kept comes back exactly, even under 16,384',
    () async {
      final s = await open({});
      await s.setBackendType('kobold');
      await s.setContextSize(8192);
      await s.setActiveKcppsPath(preset('Long.kcpps', 32768));

      await s.setActiveKcppsPath(null);

      expect(s.contextSize, 8192);
    },
  );

  group('a launch that drops the preset', () {
    late KoboldService kobold;
    late StorageService storage;

    Future<void> launch() async {
      kobold = KoboldService(storage);
      addTearDown(kobold.dispose);
      // Never created: the launch stops before it can run anything.
      await kobold.launch(
        p.join(dir.path, 'koboldcpp'),
        pickedModel: model,
        port: 5999,
      );
      final admin = koboldAdminDirFor(storage);
      if (FileSystemEntity.isFileSync(admin)) File(admin).deleteSync();
    }

    test('whose file is gone, with no number kept: 16,384, not the preset\'s '
        '8,192', () async {
      final gone = preset('Gone.kcpps', 8192);
      storage = await _storage(chosenBefore(gone, 8192));
      File(gone).deleteSync();

      await launch();

      expect(storage.backendSettings.activeKcppsPath, isNull);
      expect(storage.backendSettings.contextSize, kKoboldContextFloor);
    });

    test('whose file is gone, with a number kept: that number', () async {
      storage = await _storage({BackendSettings().k('backend_type'): 'kobold'});
      await storage.backendSettings.setContextSize(20480);
      await storage.backendSettings.setLastUsedModelPath(model);
      final gone = preset('Gone.kcpps', 8192);
      await storage.backendSettings.setActiveKcppsPath(gone);
      File(gone).deleteSync();

      await launch();

      expect(storage.backendSettings.contextSize, 20480);
    });

    test('that the app wrote itself, with no number kept: 16,384', () async {
      storage = await _storage({});
      final own = preset(
        '${kStagedConfigPrefix}chat.kcpps',
        8192,
        storage.binDir.path,
      );
      storage = await _storage(chosenBefore(own, 8192));
      expect(storage.backendSettings.contextSize, 8192);

      await launch();

      expect(storage.backendSettings.activeKcppsPath, isNull);
      expect(storage.backendSettings.contextSize, kKoboldContextFloor);
    });
  });
}

/// A real storage service over a preferences store holding [saved].
Future<StorageService> _storage(Map<String, Object> saved) async {
  SharedPreferences.setMockInitialValues({
    'character_evolution_enabled': false,
    ...saved,
  });
  final storage = StorageService();
  await storage.initialized;
  await storage.binDir.create(recursive: true);
  return storage;
}
