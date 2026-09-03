// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/lore_extraction_service.dart';
import 'package:front_porch_ai/utils/picker_prefs.dart';

void main() {
  test('pubspec pins file_picker ^12.1.1 not 12.0 or 12.1.0', () {
    final yaml = File('pubspec.yaml').readAsStringSync();
    expect(yaml, contains('file_picker: ^12.1.1'));
    expect(yaml.contains('file_picker: ^12.0'), isFalse);
    expect(yaml.contains('file_picker: ^12.1.0'), isFalse);
  });

  test('lock resolves file_picker at least 12.1.1', () {
    final lock = File('pubspec.lock').readAsStringSync();
    final idx = lock.indexOf('\n  file_picker:\n');
    expect(idx, greaterThanOrEqualTo(0), reason: 'file_picker missing from lock');
    final block = lock.substring(idx, idx + 500);
    final version = RegExp(r'version: "([^"]+)"').firstMatch(block)!.group(1)!;
    final parts = version.split('.').map(int.parse).toList();
    expect(parts[0], 12);
    expect(parts[1], greaterThanOrEqualTo(1));
    if (parts[1] == 1) {
      expect(parts[2], greaterThanOrEqualTo(1));
    }
  });

  test('package_info_plus is constraint-only (no Dart import)', () {
    final needle = 'package:package_info_plus/';
    final dartFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    for (final f in dartFiles) {
      for (final line in f.readAsLinesSync()) {
        final trimmed = line.trimLeft();
        if (trimmed.startsWith('import ') && trimmed.contains(needle)) {
          fail('${f.path} must not import package_info_plus');
        }
      }
    }
  });

  test('single-file pickers use pickFile (12 defaults allowMultiple true)', () {
    final piper = File('lib/ui/dialogs/piper_import_voice_button.dart')
        .readAsStringSync();
    expect(piper, contains('FilePicker.pickFile('));
    expect(piper.contains('FilePicker.pickFiles('), isFalse);

    final vision =
        File('lib/ui/widgets/vision_projector_field.dart').readAsStringSync();
    expect(vision, contains('FilePicker.pickFile('));
    expect(vision.contains('FilePicker.pickFiles('), isFalse);
  });

  test('PickerPrefs never enables Android SAF persistable URI grants', () {
    final src = File('lib/utils/picker_prefs.dart').readAsStringSync();
    expect(src.contains('FilePickerAndroidOptions('), isFalse);
    expect(src.contains('persistGrant:'), isFalse);
    expect(src.contains('AndroidSAFGrant'), isFalse);
    expect(src.contains('androidSafOptions:'), isFalse);
    expect(src.contains('AndroidSAFOptions('), isFalse);
  });

  test('FilePickerResult shim exposes files and firstBytes', () async {
    final file = MemoryPlatformFile(
      name: 'note.txt',
      bytes: Uint8List.fromList(utf8.encode('hello porch')),
    );
    final result = FilePickerResult([file]);
    expect(result.files, hasLength(1));
    expect(result.files.first.name, 'note.txt');
    expect(await result.firstBytes(), utf8.encode('hello porch'));
    expect(await FilePickerResult([]).firstBytes(), isNull);
  });

  test('MemoryPlatformFile readAsBytes and extension (12.1 getter)', () async {
    final file = MemoryPlatformFile(
      name: 'lore.md',
      bytes: Uint8List.fromList(utf8.encode('# Tide')),
    );
    expect(file.extension, 'md');
    expect(await file.readAsBytes(), utf8.encode('# Tide'));
    expect(await file.length(), 6);
  });

  test('uriToSavePath converts file Uri to a filesystem path', () {
    expect(PickerPrefs.uriToSavePath(null), isNull);
    final path = PickerPrefs.uriToSavePath(Uri.file('/tmp/out.txt'));
    expect(path, '/tmp/out.txt');
    expect(
      PickerPrefs.uriToSavePath(Uri.parse('content://media/123')),
      'content://media/123',
    );
  });

  test('lore extraction reads MemoryPlatformFile via readAsBytes', () async {
    const body =
        'The Saltmarrow Compact binds the seven tide-houses of Brelth.';
    final text = await LoreExtractionService.extractAll(
      urls: const [],
      files: [
        MemoryPlatformFile(
          name: 'compact.txt',
          bytes: Uint8List.fromList(utf8.encode(body)),
        ),
      ],
    );
    expect(text, contains('Saltmarrow Compact'));
    expect(text, contains('compact.txt'));
  });

  test('saveFile rejects empty bytes so it cannot wipe the chosen file', () {
    expect(
      PickerPrefs.saveFile(
        category: PickerPrefs.catExport,
        bytes: Uint8List(0),
        fileName: 'wipe-me.txt',
      ),
      throwsA(isA<ArgumentError>()),
    );
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      expect(
        src.contains('bytes: Uint8List(0)'),
        isFalse,
        reason: '${f.path} must not pass empty save bytes',
      );
    }
  });

  test('vision projector GGUF pick is path-only (no readAsBytes)', () {
    final vision =
        File('lib/ui/widgets/vision_projector_field.dart').readAsStringSync();
    expect(vision.contains('readAsBytes'), isFalse);
    final models = File('lib/ui/pages/model_manager_page.dart').readAsStringSync();
    expect(
      models.contains("allowedExtensions: ['gguf']"),
      isTrue,
    );
  });

  test('comfy workflow pick is json, not FileType.any', () {
    final src = File('lib/ui/image_studio/comfy_edit_panel.dart').readAsStringSync();
    expect(src.contains('FileType.any'), isFalse);
    expect(src, contains('FileType.custom'));
    expect(src, contains("allowedExtensions: ['json']"));
  });

  test('localPathOrTemp materializes a path-null pick', () async {
    final file = MemoryPlatformFile(
      name: 'card.json',
      bytes: Uint8List.fromList(utf8.encode('{"ok":true}')),
    );
    expect(file.path, isNull);
    final path = await PickerPrefs.localPathOrTemp(file);
    expect(path, isNotNull);
    expect(File(path!).readAsStringSync(), '{"ok":true}');
  });

  test('chargen facade constructs MemoryPlatformFile (PlatformFile is abstract)', () {
    final src = File('lib/services/web/facade/chargen_facade.dart')
        .readAsStringSync();
    expect(src, contains('MemoryPlatformFile('));
    expect(src.contains('PlatformFile(name:'), isFalse);
  });

  test('lorebook import reads bytes by name, not path.split', () {
    final src = File('lib/ui/pages/import_lorebook_page.dart').readAsStringSync();
    expect(src, contains('result.files.single.readAsBytes()'));
    expect(src, contains('result.files.single.name'));
    expect(src.contains('path.split'), isFalse);
  });

  test('lock resolves win32 6 with file_picker 12', () {
    final lock = File('pubspec.lock').readAsStringSync();
    final idx = lock.indexOf('\n  win32:\n');
    expect(idx, greaterThanOrEqualTo(0), reason: 'win32 missing from lock');
    final block = lock.substring(idx, idx + 400);
    final version = RegExp(r'version: "([^"]+)"').firstMatch(block)!.group(1)!;
    expect(int.parse(version.split('.').first), 6);
  });

  test('PickerPrefs.pickFiles default routes to pickFile', () {
    final src = File('lib/utils/picker_prefs.dart').readAsStringSync();
    expect(src, contains('bool allowMultiple = false'));
    expect(src, contains('FilePicker.pickFile('));
  });

  test('no dart in lib/test/integration_test constructs PlatformFile', () {
    final ctor = RegExp(r'(?<!Memory)PlatformFile\(');
    for (final dir in ['lib', 'test', 'integration_test']) {
      for (final f in Directory(dir)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        if (f.path.endsWith('picker_prefs_v12_test.dart')) continue;
        for (final line in f.readAsStringSync().split('\n')) {
          final t = line.trim();
          if (t.startsWith('//') || t.startsWith('///') || t.startsWith('*')) {
            continue;
          }
          if (t.contains("contains('PlatformFile")) continue;
          if (ctor.hasMatch(t)) {
            fail('${f.path}: still constructs PlatformFile: $t');
          }
        }
      }
    }
  });

  test('lorebook E2E uses MemoryPlatformFile shim', () {
    final src =
        File('integration_test/lorebook_import_test.dart').readAsStringSync();
    expect(src, contains('MemoryPlatformFile('));
    expect(RegExp(r'(?<!Memory)PlatformFile\(').hasMatch(src), isFalse);
  });
}
