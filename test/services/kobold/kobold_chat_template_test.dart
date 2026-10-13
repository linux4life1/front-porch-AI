// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/kobold/kobold.dart';
import 'package:path/path.dart' as p;

import '../../helpers/gguf_vocab_file.dart';

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
      expect(p.isRelative(kcppsChatTemplatePath(saved.raw)), isTrue);
      final template = kcppsChatTemplateFile(saved.raw, engine.path);
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

  group('template and model fit', () {
    const chatml =
        "{% for m in messages %}{{ '<|im_start|>' + m.role }}"
        "{{ m.content + '<|im_end|>' }}{% endfor %}";
    const mistral =
        "{% for m in messages %}{{ '[INST] ' + m.content + ' [/INST]' }}"
        "{% endfor %}";

    test('a Qwen template on a Mistral vocabulary is flagged', () {
      final fit = checkChatTemplateFit(
        template: chatml,
        vocab: {'<s>', '</s>', '[INST]', '[/INST]'},
      );
      expect(fit.fits, isFalse);
      expect(fit.missing, ['<|im_end|>', '<|im_start|>']);
    });

    test('a Mistral template on a Qwen model is flagged by its family', () {
      final fit = checkChatTemplateFit(
        template: mistral,
        vocab: {'<|im_start|>', '<|im_end|>', '<think>'},
        embedded: chatml,
      );
      expect(fit.fits, isFalse);
      expect(fit.modelMarkers, ['<|im_end|>', '<|im_start|>']);
    });

    test('plain-text [INST] on an older vocabulary still fits', () {
      final fit = checkChatTemplateFit(
        template: mistral,
        vocab: {'<s>', '</s>', '<unk>'},
        embedded: mistral,
      );
      expect(fit.fits, isTrue);
    });

    test(
      'Use anyway is remembered per template and model, across folders',
      () async {
        final model = File(p.join(root.path, 'Mistral-7B.gguf'));
        await model.writeAsBytes(
          ggufWithVocab(
            tokens: ['<unk>', '<s>', '</s>', '[INST]', '[/INST]', 'hello'],
            template: mistral,
          ),
        );
        final template = File(p.join(engine.path, 'qwen.jinja'));
        await template.writeAsString(chatml);
        Future<ChatTemplateFit?> warning(String modelPath) =>
            koboldTemplateWarning(
              engineDir: engine.path,
              templatePath: template.path,
              modelPath: modelPath,
            );

        final first = await warning(model.path);
        expect(first?.missing, ['<|im_end|>', '<|im_start|>']);
        expect(first?.message('Mistral 7B'), contains('<|im_end|>'));

        await acceptKoboldTemplate(
          engineDir: engine.path,
          templatePath: template.path,
          modelPath: model.path,
        );
        expect(await warning(model.path), isNull);

        // The same model file in another folder is still the same model.
        final moved = await Directory(p.join(root.path, 'moved')).create();
        final copy = await model.copy(p.join(moved.path, 'Mistral-7B.gguf'));
        expect(await warning(copy.path), isNull);

        // Another template asks again.
        await template.writeAsString('$chatml{{ "<|endoftext|>" }}');
        expect(await warning(model.path), isNotNull);

        // A template the model reads never warns.
        await template.writeAsString(mistral);
        expect(await warning(model.path), isNull);
      },
    );

    test('a launch hands KoboldCpp the template as a full path', () {
      final map = kcppsPresetLaunchMap(
        {'jinjatemplate': p.join('chat_templates', 'abc', 'x.jinja')},
        modelPath: '',
        mmprojPath: '',
        engineDir: engine.path,
      );
      expect(
        map['jinjatemplate'],
        p.join(engine.path, 'chat_templates', 'abc', 'x.jinja'),
      );
    });
  });
}
