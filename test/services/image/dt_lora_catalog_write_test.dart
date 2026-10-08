// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// custom_lora.json is Draw Things' own catalog. A crash while it is being
// rewritten must not leave half a file, and two downloads finishing together
// must not lose each other's row.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/image/civitai_download.dart';

void main() {
  late Directory models;
  late File catalog;

  List<dynamic> rows() => jsonDecode(catalog.readAsStringSync()) as List;
  List<String> leftovers() => [
    for (final e in models.listSync())
      if (p.basename(e.path).endsWith('.tmp')) p.basename(e.path),
  ];

  setUp(() {
    models = Directory.systemTemp.createTempSync('dt_catalog');
    addTearDown(() => models.deleteSync(recursive: true));
    catalog = File(p.join(models.path, 'custom_lora.json'));
  });

  group('a crash mid-write', () {
    const before = '[{"file":"keep_me.safetensors","name":"keep_me"}]';

    Future<void> crashingWrite(File temp, String contents) async {
      temp.writeAsStringSync(contents.substring(0, contents.length ~/ 2));
      throw const FileSystemException('disk went away mid-write');
    }

    test('leaves the catalog exactly as it was, and no temp file', () async {
      catalog.writeAsStringSync(before);
      await expectLater(
        rememberDrawThingsLora(
          models,
          'new_lora.safetensors',
          writeTemp: crashingWrite,
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(catalog.readAsStringSync(), before);
      expect(leftovers(), isEmpty);
    });

    test(
      'on a first write leaves no catalog at all, not half of one',
      () async {
        await expectLater(
          rememberDrawThingsLora(
            models,
            'new_lora.safetensors',
            writeTemp: crashingWrite,
          ),
          throwsA(isA<FileSystemException>()),
        );
        expect(catalog.existsSync(), isFalse);
        expect(leftovers(), isEmpty);
      },
    );

    test('does not stop the next write from working', () async {
      catalog.writeAsStringSync(before);
      await expectLater(
        rememberDrawThingsLora(
          models,
          'a.safetensors',
          writeTemp: crashingWrite,
        ),
        throwsA(anything),
      );
      await rememberDrawThingsLora(models, 'b.safetensors');
      expect(rows().map((r) => (r as Map)['file']), [
        'keep_me.safetensors',
        'b.safetensors',
      ]);
    });
  });

  test(
    'the catalog is never written in place: it still holds the old rows while the new file is being written',
    () async {
      catalog.writeAsStringSync('[{"file":"old.safetensors","name":"old"}]');
      String? seenWhileWriting;
      var tempBeside = false;
      await rememberDrawThingsLora(
        models,
        'new.safetensors',
        writeTemp: (temp, contents) async {
          tempBeside = p.dirname(temp.path) == models.path;
          temp.writeAsStringSync(contents);
          seenWhileWriting = catalog.readAsStringSync();
        },
      );
      expect(tempBeside, isTrue);
      expect(seenWhileWriting, '[{"file":"old.safetensors","name":"old"}]');
      expect(rows().map((r) => (r as Map)['file']), [
        'old.safetensors',
        'new.safetensors',
      ]);
      expect(leftovers(), isEmpty);
    },
  );

  test('a normal write lands whole, valid JSON, with the version', () async {
    await rememberDrawThingsLora(
      models,
      'klein_unchained_v2_lora_f16.ckpt',
      baseModel: 'Flux.2 Klein 9B',
    );
    final row = rows().single as Map;
    expect(row['file'], 'klein_unchained_v2_lora_f16.ckpt');
    expect(row['version'], 'flux2_9b');
    expect(leftovers(), isEmpty);
  });

  test('a file already listed is not written again', () async {
    catalog.writeAsStringSync('[{"file":"lora/x.safetensors","name":"x"}]');
    var wrote = false;
    await rememberDrawThingsLora(
      models,
      'x.safetensors',
      writeTemp: (temp, contents) async => wrote = true,
    );
    expect(wrote, isFalse);
  });

  test('a catalog that is not a list, or not JSON, is left alone', () async {
    for (final text in ['{"a":1}', 'not json at all', '']) {
      catalog.writeAsStringSync(text);
      await rememberDrawThingsLora(models, 'x.safetensors');
      expect(catalog.readAsStringSync(), text);
      expect(leftovers(), isEmpty);
    }
  });

  test('two downloads finishing at once each keep their row', () async {
    await Future.wait([
      for (var i = 0; i < 40; i++)
        rememberDrawThingsLora(models, 'lora_$i.safetensors'),
    ]);
    final files = rows().map((r) => (r as Map)['file']).toSet();
    expect(files, {for (var i = 0; i < 40; i++) 'lora_$i.safetensors'});
    expect(rows(), hasLength(40));
    expect(leftovers(), isEmpty);
  });

  test('one failed write does not block the ones queued behind it', () async {
    final results = await Future.wait([
      rememberDrawThingsLora(
        models,
        'a.safetensors',
        writeTemp: (temp, contents) async =>
            throw const FileSystemException('x'),
      ).then<Object?>((_) => 'ok', onError: (_) => 'failed'),
      rememberDrawThingsLora(
        models,
        'b.safetensors',
      ).then<Object?>((_) => 'ok'),
    ]);
    expect(results, ['failed', 'ok']);
    expect(rows().map((r) => (r as Map)['file']), ['b.safetensors']);
  });

  group('writeFileAtomically on its own', () {
    test('replaces an existing file whole', () async {
      final f = File(p.join(models.path, 'x.json'))..writeAsStringSync('old');
      await writeFileAtomically(f, 'new contents');
      expect(f.readAsStringSync(), 'new contents');
      expect(leftovers(), isEmpty);
    });

    test('a failure keeps the old file and rethrows', () async {
      final f = File(p.join(models.path, 'x.json'))..writeAsStringSync('old');
      await expectLater(
        writeFileAtomically(
          f,
          'new',
          writeTemp: (temp, contents) async => throw StateError('boom'),
        ),
        throwsStateError,
      );
      expect(f.readAsStringSync(), 'old');
    });
  });
}
