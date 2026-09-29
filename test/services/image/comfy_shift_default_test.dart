// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A graph posts its own sampling shift unless the person moved Shift for that
// graph. Real templates keep every shift they carry when Shift is untouched;
// moving Shift changes the `shift` of ModelSampling nodes only, and only in
// the graph it was moved for.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/storage/settings/image_gen_settings.dart';
import 'package:front_porch_ai/services/storage_service.dart';

const _fixtures = 'test/fixtures/comfy_templates';

Map<String, dynamic> _node(String type, Map<String, Object?> inputs) => {
  'class_type': type,
  'inputs': inputs,
};

/// Small API graphs shaped like the templates the review named: the loaders
/// and sampler are stand-ins, the ModelSampling nodes carry the real values.
Map<String, dynamic> _graph(Map<String, dynamic> shiftNodes) => {
  'ckpt': _node('CheckpointLoaderSimple', {'ckpt_name': 'm.safetensors'}),
  ...shiftNodes,
  'pos': _node('CLIPTextEncode', {
    'text': 'a porch',
    'clip': ['ckpt', 1],
  }),
  'neg': _node('CLIPTextEncode', {
    'text': 'blur',
    'clip': ['ckpt', 1],
  }),
  'latent': _node('EmptyLatentImage', {
    'width': 512,
    'height': 512,
    'batch_size': 1,
  }),
  'ks': _node('KSampler', {
    'model': ['ckpt', 0],
    'positive': ['pos', 0],
    'negative': ['neg', 0],
    'latent_image': ['latent', 0],
    'seed': 1,
    'steps': 20,
    'cfg': 7.0,
    'sampler_name': 'euler',
    'scheduler': 'normal',
    'denoise': 1.0,
  }),
  'save': _node('SaveImage', {
    'images': ['ks', 0],
    'filename_prefix': 'fpai',
  }),
};

final _graphs = <String, Map<String, dynamic>>{
  // Flux: max_shift is not the Shift control's.
  'flux max_shift 1.15': _graph({
    'ms': _node('ModelSamplingFlux', {
      'model': ['ckpt', 0],
      'max_shift': 1.15,
      'base_shift': 0.5,
      'width': 1024,
      'height': 1024,
    }),
  }),
  'sd3 shift 7': _graph({
    'ms': _node('ModelSamplingSD3', {
      'model': ['ckpt', 0],
      'shift': 7,
    }),
  }),
  'sd3 shift 5.5': _graph({
    'ms': _node('ModelSamplingSD3', {
      'model': ['ckpt', 0],
      'shift': 5.5,
    }),
  }),
  'auraflow shift 3.1': _graph({
    'ms': _node('ModelSamplingAuraFlow', {
      'model': ['ckpt', 0],
      'shift': 3.1,
    }),
  }),
  'two shift nodes': _graph({
    'a': _node('ModelSamplingSD3', {
      'model': ['ckpt', 0],
      'shift': 8,
    }),
    'b': _node('ModelSamplingSD3', {
      'model': ['a', 0],
      'shift': 2,
    }),
  }),
  // Not a ModelSampling node: its shift is not the desk's.
  'other node with a shift': _graph({
    'x': _node('SomeVideoNode', {
      'model': ['ckpt', 0],
      'shift': 9.5,
      'max_shift': 4.5,
    }),
  }),
};

/// Every shift-like input the graph carries, by node id and input name.
Map<String, Object?> _shifts(Map<String, dynamic> graph) => {
  for (final e in graph.entries)
    if (e.value is Map && (e.value as Map)['inputs'] is Map)
      for (final i in ((e.value as Map)['inputs'] as Map).entries)
        if (const {'shift', 'max_shift', 'base_shift'}.contains(i.key))
          '${e.key}.${i.key}': i.value,
};

/// What a generate posts for [graph], with the shift the person set (or none).
Map<String, dynamic> _posted(
  Map<String, dynamic> graph, {
  double? shift,
  bool edit = false,
}) {
  final values = edit
      ? resolveComfyEditRequest(
          workflowId: 'comfy:default:g',
          uploadedWorkflowJson: '',
          modelChoices: const {},
          prompt: 'p',
          negative: 'n',
          seed: 1,
          steps: 20,
          cfg: 7,
          denoise: 1,
          shift: shift,
          liveTemplate: graph,
        )
      : null;
  if (values != null) {
    return substituteComfyWorkflow(values.template, {
      ...values.values,
      ComfyEditTokens.image: 'x',
    });
  }
  final req = resolveComfyCreateRequest(
    workflowId: 'comfy:default:g',
    uploadedWorkflowJson: '',
    modelChoices: const {},
    prompt: 'p',
    negative: 'n',
    seed: 1,
    steps: 20,
    cfg: 7,
    denoise: 1,
    shift: shift,
    width: 512,
    height: 512,
    checkpointFallback: 'm.safetensors',
    liveTemplate: graph,
  )!;
  return substituteComfyWorkflow(req.template, req.values);
}

void main() {
  group('with Shift untouched a graph posts its own shifts', () {
    _graphs.forEach((name, graph) {
      test(name, () {
        expect(_shifts(_posted(graph)), _shifts(graph));
      });
    });

    for (final file in Directory(_fixtures).listSync().whereType<File>()) {
      if (!file.path.endsWith('.json')) continue;
      test('template ${file.uri.pathSegments.last}', () {
        final api = convertComfyUiToApi(
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
        );
        expect(_shifts(_posted(api)), _shifts(api));
      });
    }

    test(
      'a template whose AuraFlow shift is not 3 keeps it (it was forced to 3.0)',
      () {
        final api = convertComfyUiToApi(
          jsonDecode(
                File(
                  '$_fixtures/image_qwen_image_edit_2509_relight.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>,
        );
        // The shipped template says 3, which is also the old default; a
        // different value is what tells the two apart.
        var changed = 0;
        for (final node in api.values.whereType<Map>()) {
          if (node['class_type'] == 'ModelSamplingAuraFlow') {
            (node['inputs'] as Map)['shift'] = 5.5;
            changed++;
          }
        }
        expect(changed, greaterThan(0));

        expect(_shifts(_posted(api)).values, everyElement(5.5));
        expect(
          _shifts(_posted(api, shift: 6.5)).values,
          everyElement(6.5),
          reason: 'moved for this graph',
        );
        expect(_shifts(_posted(api, edit: true)).values, everyElement(5.5));
      },
    );

    // The shipped starters, posted the way the desk posts them by id.
    for (final id in [
      'sd',
      'z_image_turbo',
      'flux',
      'qwen_image',
      'qwen_image_21',
    ]) {
      test('starter $id posts its own shifts', () {
        final starter = comfyStarterGraph(id)!;
        final req = resolveComfyCreateRequest(
          workflowId: id,
          uploadedWorkflowJson: '',
          modelChoices: const {},
          prompt: 'p',
          negative: 'n',
          seed: 1,
          steps: 20,
          cfg: 7,
          denoise: 1,
          shift: null,
          width: 512,
          height: 512,
        )!;
        final posted = substituteComfyWorkflow(req.template, req.values);
        expect(_shifts(posted), _shifts(starter), reason: id);
      });
    }

    test('the Qwen starter\'s own 3.1 is not the default 3.0', () {
      final req = resolveComfyCreateRequest(
        workflowId: 'qwen_image',
        uploadedWorkflowJson: '',
        modelChoices: const {},
        prompt: 'p',
        negative: 'n',
        seed: 1,
        steps: 20,
        cfg: 7,
        denoise: 1,
        shift: null,
        width: 512,
        height: 512,
      )!;
      final posted = substituteComfyWorkflow(req.template, req.values);
      expect(_shifts(posted).values, contains(3.1));
    });
  });

  group('moving Shift', () {
    test('changes the shift of ModelSampling nodes, and only those', () {
      for (final name in ['sd3 shift 7', 'auraflow shift 3.1']) {
        final posted = _shifts(_posted(_graphs[name]!, shift: 6.5));
        expect(posted['ms.shift'], 6.5, reason: name);
      }
      final two = _shifts(_posted(_graphs['two shift nodes']!, shift: 6.5));
      expect(two['a.shift'], 6.5);
      expect(two['b.shift'], 6.5);
    });

    test('never touches Flux max_shift', () {
      final posted = _shifts(
        _posted(_graphs['flux max_shift 1.15']!, shift: 6.5),
      );
      expect(posted['ms.max_shift'], 1.15);
      expect(posted['ms.base_shift'], 0.5);
    });

    test('never touches a shift on a node that is not ModelSampling', () {
      final posted = _shifts(
        _posted(_graphs['other node with a shift']!, shift: 6.5),
      );
      expect(posted['x.shift'], 9.5);
      expect(posted['x.max_shift'], 4.5);
    });

    test('an Edit graph is the same', () {
      // The generic graph has no %IMAGE%; the edit path needs its tokens.
      final edit = {
        ..._graph({
          'ms': _node('ModelSamplingSD3', {
            'model': ['ckpt', 0],
            'shift': 7,
          }),
        }),
        'img': _node('LoadImage', {'image': 'in.png'}),
      };
      expect(_shifts(_posted(edit, edit: true))['ms.shift'], 7);
      expect(_shifts(_posted(edit, shift: 6.5, edit: true))['ms.shift'], 6.5);
    });
  });

  group('the desk remembers Shift per graph', () {
    late StorageService storage;

    setUp(() {
      final dir = Directory.systemTemp.createTempSync('comfy-shift-default');
      addTearDown(() => dir.deleteSync(recursive: true));
      storage = StorageService.sandbox(dir.path);
    });

    test('nothing is set until the person moves it', () {
      expect(
        storage.imageGenSettings.comfyShiftFor('comfy:default:a', edit: false),
        isNull,
      );
    });

    test('moving it for one graph leaves every other graph alone', () async {
      final s = storage.imageGenSettings;
      await s.setComfyShift('comfy:default:a', 6.5, edit: false);

      expect(s.comfyShiftFor('comfy:default:a', edit: false), 6.5);
      expect(s.comfyShiftFor('comfy:default:b', edit: false), isNull);
      expect(s.comfyShiftFor('comfy:default:a', edit: true), isNull);
    });

    test('it can go back to the graph\'s own', () async {
      final s = storage.imageGenSettings;
      await s.setComfyShift('comfy:default:a', 6.5, edit: false);
      await s.clearComfyShift('comfy:default:a', edit: false);

      expect(s.comfyShiftFor('comfy:default:a', edit: false), isNull);
    });
  });
}
