// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/kobold/kobold.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late Directory engine;
  late File preset;
  const original = <String, dynamic>{
    'model_param': '/models/example.gguf',
    'contextsize': 8192,
    'jinjatemplate': '/templates/old.jinja',
    'jinja_tools': false,
    'tensor_split': [1, 2],
    'custom_future_setting': {'keep': true},
  };
  setUp(() async {
    root = await Directory.systemTemp.createTemp('fpai-template-test-');
    engine = await Directory(p.join(root.path, 'engine')).create();
    preset = File(p.join(engine.path, 'Example.kcpps'));
    await preset.writeAsString(jsonEncode(original));
  });
  tearDown(() async => root.delete(recursive: true));

  test(
    'draft selection survives saving, copying and clearing without losing extras',
    () async {
      final read = readKcpps(jsonEncode(original)) as KcppsOk;
      final draft = KcppsDraft.fromConfig('Example', read.config);
      final selected = draft.copyWith(
        chatTemplatePath: '/templates/selected.jinja',
      );
      expect(selected.chatTemplatePath, '/templates/selected.jinja');
      final saved = kcppsMergeEdits(original, draft.toMap(), selected.toMap());
      expect(saved['jinja_tools'], isFalse);
      expect(saved['tensor_split'], original['tensor_split']);
      expect(saved['custom_future_setting'], original['custom_future_setting']);
      await preset.writeAsString(encodeKcpps(saved));
      final copy = await KcppsLibrary(engine.path).duplicate(preset.path);
      final copied = (await KcppsLibrary.open(copy)).read as KcppsOk;
      final reopened = KcppsDraft.fromConfig('Example copy', copied.config);
      expect(reopened.chatTemplatePath, '/templates/selected.jinja');
      final cleared = kcppsMergeEdits(
        copied.raw,
        reopened.toMap(),
        reopened.copyWith(chatTemplatePath: '').toMap(),
      );
      expect(cleared.containsKey('jinjatemplate'), isFalse);
      expect(cleared['tensor_split'], original['tensor_split']);
    },
  );

  test(
    'web upload writes exact text to a host-owned file and preserves the preset',
    () async {
      const content = '{% if enable_thinking is false %}direct{% endif %}';
      await saveUploadedKoboldTemplate(
        engineDir: engine.path,
        preset: preset.path,
        name: '../outside.jinja',
        content: content,
      );
      final saved = (await KcppsLibrary.open(preset.path)).read as KcppsOk;
      final template = kcppsChatTemplatePath(saved.raw);
      expect(
        p.isWithin(p.join(engine.path, 'chat_templates'), template),
        isTrue,
      );
      expect(await File(template).readAsString(), content);
      expect(saved.raw['tensor_split'], original['tensor_split']);
      expect(saved.raw['jinja'], isTrue);
      expect(saved.raw['jinja_tools'], isFalse);
      await saveUploadedKoboldTemplate(
        engineDir: engine.path,
        preset: preset.path,
      );
      final cleared = (await KcppsLibrary.open(preset.path)).read as KcppsOk;
      expect(cleared.raw.containsKey('jinjatemplate'), isFalse);
      expect(
        cleared.raw['custom_future_setting'],
        original['custom_future_setting'],
      );
    },
  );

  test(
    'outside presets and app-staged configs cannot be edited from web',
    () async {
      final outside = File(p.join(root.path, 'Outside.kcpps'));
      await outside.writeAsString(jsonEncode(original));
      final staged = File(p.join(engine.path, 'fpai-chat.kcpps'));
      await staged.writeAsString(jsonEncode(original));
      for (final file in [outside, staged]) {
        await expectLater(
          saveUploadedKoboldTemplate(
            engineDir: engine.path,
            preset: file.path,
            name: 'safe.jinja',
            content: 'a template',
          ),
          throwsFormatException,
        );
        expect(jsonDecode(await file.readAsString()), original);
      }
    },
  );

  test(
    'invalid uploads and an overtaken selection never overwrite the preset',
    () async {
      for (final (name, content) in [
        ('bad.txt', 'a template'),
        ('empty.jinja', ''),
        ('binary.jinja', 'bad\u0000data'),
        ('large.jinja', 'x' * (kChatTemplateMaxBytes + 1)),
      ]) {
        await expectLater(
          saveUploadedKoboldTemplate(
            engineDir: engine.path,
            preset: preset.path,
            name: name,
            content: content,
          ),
          throwsFormatException,
        );
        expect(jsonDecode(await preset.readAsString()), original);
      }
      await expectLater(
        saveUploadedKoboldTemplate(
          engineDir: engine.path,
          preset: preset.path,
          name: 'fine.jinja',
          content: 'a template',
          stillSelected: () => false,
        ),
        throwsFormatException,
      );
      expect(jsonDecode(await preset.readAsString()), original);
    },
  );
}
