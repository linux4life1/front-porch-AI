// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The ComfyUI edit token engine + preset structural integrity. The render itself
// can't be tested without a live ComfyUI, but these lock the parts that CAN fail
// silently: type-preserving substitution, and that every preset's declared model
// slots + standard tokens actually appear in its graph AND fully resolve (a typo'd
// token would otherwise ship a graph with a literal "%SEED%" in it).

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/image/comfy_edit_workflow.dart';
import 'package:front_porch_ai/services/image/comfy_edit_presets.dart';

void main() {
  group('substituteComfyWorkflow', () {
    test('an exact-match token becomes the TYPED value (int/double), not a string',
        () {
      final tpl = {
        'k': {
          'class_type': 'KSampler',
          'inputs': {
            'seed': '%SEED%',
            'cfg': '%CFG%',
            'text': '%PROMPT%',
          },
        },
      };
      final out = substituteComfyWorkflow(tpl, {
        '%SEED%': 42,
        '%CFG%': 3.5,
        '%PROMPT%': 'a red coat',
      });
      final inputs = (out['k'] as Map)['inputs'] as Map;
      expect(inputs['seed'], 42);
      expect(inputs['seed'], isA<int>());
      expect(inputs['cfg'], 3.5);
      expect(inputs['cfg'], isA<double>());
      expect(inputs['text'], 'a red coat');
    });

    test('a token embedded in a larger string is replaced in place', () {
      final tpl = {
        'n': {
          'inputs': {'filename_prefix': 'edit_%SEED%'},
        },
      };
      final out = substituteComfyWorkflow(tpl, {'%SEED%': 7});
      expect(((out['n'] as Map)['inputs'] as Map)['filename_prefix'], 'edit_7');
    });

    test('node links (["node", 0]) and other data are preserved', () {
      final tpl = {
        'a': {
          'inputs': {
            'image': '%IMAGE%',
            'model': ['loader', 0],
            'batch': 1,
          },
        },
      };
      final out = substituteComfyWorkflow(tpl, {'%IMAGE%': 'up.png'});
      final inputs = (out['a'] as Map)['inputs'] as Map;
      expect(inputs['image'], 'up.png');
      expect(inputs['model'], ['loader', 0]);
      expect(inputs['batch'], 1);
    });

    test('the input template is not mutated', () {
      final tpl = {
        'a': {
          'inputs': {'text': '%PROMPT%'},
        },
      };
      substituteComfyWorkflow(tpl, {'%PROMPT%': 'hi'});
      expect(((tpl['a'] as Map)['inputs'] as Map)['text'], '%PROMPT%');
    });
  });

  group('detect / unresolved', () {
    test('detectComfyTokens reports which standard tokens are present', () {
      final tpl = {
        'a': {
          'inputs': {'image': '%IMAGE%', 'text': '%PROMPT%'},
        },
      };
      final found = detectComfyTokens(tpl);
      expect(found, containsAll([ComfyEditTokens.image, ComfyEditTokens.prompt]));
      expect(found, isNot(contains(ComfyEditTokens.seed)));
    });

    test('unresolvedComfyTokens catches a leftover placeholder', () {
      final partial = substituteComfyWorkflow({
        'a': {
          'inputs': {'image': '%IMAGE%', 'seed': '%SEED%'},
        },
      }, {'%IMAGE%': 'x.png'}); // %SEED% left unfilled
      expect(unresolvedComfyTokens(partial), contains('%SEED%'));
    });
  });

  group('bundled presets — structural integrity (render is community-verified)',
      () {
    test('there are presets and ids/labels are unique', () {
      expect(kComfyEditPresets, isNotEmpty);
      final ids = kComfyEditPresets.map((p) => p.id).toSet();
      final labels = kComfyEditPresets.map((p) => p.label).toSet();
      expect(ids.length, kComfyEditPresets.length);
      expect(labels.length, kComfyEditPresets.length);
    });

    for (final preset in kComfyEditPresets) {
      group('${preset.label} (${preset.id})', () {
        test('every declared model slot token appears in the graph', () {
          final strings = _allStrings(preset.template);
          for (final slot in preset.modelSlots) {
            expect(
              strings.any((s) => s.contains(slot.token)),
              isTrue,
              reason: '${slot.label} token ${slot.token} missing from graph',
            );
          }
        });

        test('requires the reference image + prompt tokens', () {
          final found = detectComfyTokens(preset.template);
          expect(found, containsAll(ComfyEditTokens.required));
        });

        test('has the required-node list and a SaveImage output', () {
          expect(preset.requiredNodes, isNotEmpty);
          final classTypes = (preset.template.values)
              .map((n) => (n as Map)['class_type'])
              .toSet();
          expect(classTypes, contains('SaveImage'));
          // Every node used in the graph is declared in requiredNodes (so the
          // probe can never miss a node the graph actually needs).
          for (final ct in classTypes) {
            expect(preset.requiredNodes, contains(ct),
                reason: '$ct used in graph but not in requiredNodes');
          }
        });

        test('fully filling every token leaves ZERO unresolved placeholders', () {
          final values = <String, Object?>{
            ComfyEditTokens.image: 'ref.png',
            ComfyEditTokens.prompt: 'give her a red coat',
            ComfyEditTokens.negative: 'blurry',
            ComfyEditTokens.seed: 123,
            ComfyEditTokens.steps: 20,
            ComfyEditTokens.cfg: 3.5,
            ComfyEditTokens.denoise: 1.0,
            ComfyEditTokens.sampler: 'euler',
            ComfyEditTokens.scheduler: 'simple',
            ComfyEditTokens.shift: 3.0,
            for (final slot in preset.modelSlots) slot.token: 'model.safetensors',
          };
          final filled = substituteComfyWorkflow(preset.template, values);
          expect(unresolvedComfyTokens(filled), isEmpty);
        });
      });
    }
  });

  group('resolveComfyEditRequest (workflow selection + values)', () {
    Map<String, Object?> knobs() => {
      'workflowId': 'qwen_image_edit',
      'uploadedWorkflowJson': '',
      'modelChoices': <String, String>{},
      'prompt': 'a red coat',
      'negative': 'blurry',
      'seed': 7,
      'steps': 20,
      'cfg': 3.5,
      'denoise': 1.0,
      'shift': 3.0,
    };

    test('a bundled preset resolves to its template + knob values', () {
      final r = resolveComfyEditRequest(
        workflowId: 'qwen_image_edit',
        uploadedWorkflowJson: '',
        modelChoices: const {
          'qwen_image_edit/%MODEL_DIFFUSION%': 'unet.safetensors',
          'qwen_image_edit/%MODEL_CLIP%': 'clip.safetensors',
          'qwen_image_edit/%MODEL_VAE%': 'vae.safetensors',
        },
        prompt: 'a red coat',
        negative: 'blurry',
        seed: 7,
        steps: 20,
        cfg: 3.5,
        denoise: 1.0,
        shift: 3.0,
      );
      expect(r, isNotNull);
      expect(r!.template, same(kQwenImageEditPreset.template));
      expect(r.values[ComfyEditTokens.prompt], 'a red coat');
      expect(r.values['%MODEL_DIFFUSION%'], 'unet.safetensors');
      // With every slot picked, a full substitute leaves nothing unresolved.
      final filled = substituteComfyWorkflow(r.template, {
        ...r.values,
        ComfyEditTokens.image: 'ref.png',
      });
      expect(unresolvedComfyTokens(filled), isEmpty);
    });

    test('an UNPICKED model slot is left unfilled (guarded downstream)', () {
      final r = resolveComfyEditRequest(
        workflowId: 'qwen_image_edit',
        uploadedWorkflowJson: '',
        modelChoices: const {}, // nothing picked
        prompt: 'x', negative: '', seed: 1, steps: 20,
        cfg: 3.5, denoise: 1.0, shift: 3.0,
      );
      expect(r, isNotNull);
      expect(r!.values.containsKey('%MODEL_DIFFUSION%'), isFalse);
      final filled = substituteComfyWorkflow(r.template, {
        ...r.values,
        ComfyEditTokens.image: 'ref.png',
      });
      expect(unresolvedComfyTokens(filled), contains('%MODEL_DIFFUSION%'));
    });

    test('an unknown workflow id → null', () {
      final r = resolveComfyEditRequest(
        workflowId: 'no_such_preset',
        uploadedWorkflowJson: '',
        modelChoices: const {},
        prompt: 'x', negative: '', seed: 1, steps: 20,
        cfg: 3.5, denoise: 1.0, shift: 3.0,
      );
      expect(r, isNull);
    });

    test('uploaded workflow: valid JSON parses; empty/invalid → null', () {
      final ok = resolveComfyEditRequest(
        workflowId: kComfyUploadedWorkflowId,
        uploadedWorkflowJson: '{"a":{"class_type":"X","inputs":{"t":"%PROMPT%"}}}',
        modelChoices: const {},
        prompt: 'hi', negative: '', seed: 1, steps: 20,
        cfg: 3.5, denoise: 1.0, shift: 3.0,
      );
      expect(ok, isNotNull);
      expect((ok!.template['a'] as Map)['class_type'], 'X');

      expect(
        resolveComfyEditRequest(
          workflowId: kComfyUploadedWorkflowId, uploadedWorkflowJson: '',
          modelChoices: const {}, prompt: 'x', negative: '', seed: 1,
          steps: 20, cfg: 3.5, denoise: 1.0, shift: 3.0,
        ),
        isNull,
      );
      expect(
        resolveComfyEditRequest(
          workflowId: kComfyUploadedWorkflowId, uploadedWorkflowJson: 'not json',
          modelChoices: const {}, prompt: 'x', negative: '', seed: 1,
          steps: 20, cfg: 3.5, denoise: 1.0, shift: 3.0,
        ),
        isNull,
      );
    });

    test('knobs helper is unused-safe', () => expect(knobs()['seed'], 7));
  });
}

List<String> _allStrings(Object? node) {
  final out = <String>[];
  void walk(Object? n) {
    if (n is String) {
      out.add(n);
    } else if (n is Map) {
      n.values.forEach(walk);
    } else if (n is List) {
      n.forEach(walk);
    }
  }

  walk(node);
  return out;
}
