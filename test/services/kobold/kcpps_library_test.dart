// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The preset library on a real folder, what renaming and deleting do to
// the settings that point at a preset, and a preset's one-line summary for
// files made three ways.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/kcpps_references.dart';
import 'package:front_porch_ai/services/kobold/kobold.dart';

import '../../golden/support/fakes_storage.dart';

void main() {
  late Directory dir;
  late KcppsLibrary library;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('fpai presets');
    library = KcppsLibrary(dir.path);
  });

  tearDown(() => dir.deleteSync(recursive: true));

  String file(String name, Map<String, Object?> content) => (File(
    p.join(dir.path, name),
  )..writeAsStringSync(jsonEncode(content))).path;

  test('the list: presets by name, the app\'s own files left out', () async {
    file('zeta.kcpps', {'contextsize': 4096});
    file('Alpha.kcpps', {'contextsize': 4096});
    file('fpai-chat.kcpps', {'contextsize': 4096});
    file('fpai_batch_override.kcpps', {'batchsize': 512});
    file('notes.txt', {});
    final names = [for (final e in await library.list()) e.name];
    expect(names, ['Alpha', 'zeta']);
  });

  test('write, rename, duplicate and delete', () async {
    final path = await library.write('Mine', {'contextsize': 8192});
    expect(File(path).existsSync(), isTrue);
    final moved = await library.rename(path, 'Renamed');
    expect(p.basename(moved), 'Renamed.kcpps');
    expect(File(path).existsSync(), isFalse);
    final copy = await library.duplicate(moved);
    expect(p.basename(copy), 'Renamed (copy).kcpps');
    expect(
      p.basename(await library.duplicate(moved)),
      'Renamed (copy) 2.kcpps',
    );
    await library.delete(copy);
    expect(
      [for (final e in await library.list()) e.name],
      ['Renamed', 'Renamed (copy) 2'],
    );
  });

  test('names that cannot be a preset\'s are refused, in plain words', () {
    expect(kcppsNameProblem(''), isNotNull);
    expect(kcppsNameProblem('a/b'), contains('cannot have'));
    expect(kcppsNameProblem('fpai-chat'), contains("app's own"));
    expect(kcppsNameProblem('Qwen3.6 35B — long chats'), isNull);
  });

  group('what points at a preset follows it', () {
    test(
      'a rename moves chat, the model\'s and the helper\'s preset',
      () async {
        final storage = FakeStorageService();
        final from = file('old.kcpps', {'contextsize': 8192});
        final to = p.join(dir.path, 'new.kcpps');
        await storage.backendSettings.setActiveKcppsPath(from);
        await storage.backendSettings.setWorkerKoboldKcppsPath(from);
        await storage.presetSettings.setModelPreset('/m/a.gguf', from);
        await storage.presetSettings.setModelPreset(
          '/m/b.gguf',
          '/elsewhere.kcpps',
        );

        await repointKcppsPreset(storage: storage, from: from, to: to);

        expect(storage.backendSettings.activeKcppsPath, to);
        expect(storage.backendSettings.workerKoboldKcppsPath, to);
        expect(storage.presetSettings.modelPresetMap['/m/a.gguf'], to);
        expect(
          storage.presetSettings.modelPresetMap['/m/b.gguf'],
          '/elsewhere.kcpps',
        );
      },
    );

    test('a delete lets go of it everywhere', () async {
      final storage = FakeStorageService();
      final gone = file('gone.kcpps', {'contextsize': 8192});
      await storage.backendSettings.setActiveKcppsPath(gone);
      await storage.presetSettings.setModelPreset('/m/a.gguf', gone);

      await repointKcppsPreset(storage: storage, from: gone);

      expect(storage.backendSettings.activeKcppsPath, isNull);
      expect(storage.presetSettings.modelPresetMap['/m/a.gguf'], isNull);
    });
  });

  group('one line for a list', () {
    KcppsRead read(Map<String, Object?> map) => readKcpps(jsonEncode(map));

    test('one the editor made, KoboldCpp placing it', () {
      expect(
        kcppsShortLine(
          read({
            'contextsize': 16384,
            'gpulayers': -1,
            'autofit': true,
            'noswa': true,
            'nofastforward': false,
          }),
        ),
        '16k chat · fitted to the card · smart cache off',
      );
    });

    test('sliding window and a smaller chat memory say so', () {
      expect(
        kcppsShortLine(
          read({
            'contextsize': 32768,
            'noswa': false,
            'nofastforward': true,
            'quantkv': 'q8_0',
          }),
        ),
        '32k chat · sliding window on · 8-bit chat memory',
      );
    });

    test("one from KoboldCpp's launcher counts what the app does not "
        'manage', () {
      // As saved by KoboldCpp 1.117.1's own launcher.
      final export = File('test/fixtures/kcpps/koboldcpp_1_117_1_export.kcpps');
      final line = kcppsShortLine(readKcpps(export.readAsStringSync()));
      expect(line, contains('settings this app does not manage'));
    });

    test('a file that is not a preset says it cannot be read', () {
      expect(
        kcppsShortLine(readKcpps('not json')),
        startsWith('Cannot be read'),
      );
    });
  });
}
