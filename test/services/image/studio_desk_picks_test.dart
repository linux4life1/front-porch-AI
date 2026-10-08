// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The rules the desk uses when the person picks something: which graphs it
// never swaps, which slot a picked file goes into, what the verdict carries so
// an empty slot can be filled, and the size snap.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/image/image.dart';

const _klein =
    'test/fixtures/comfy_templates/image_flux2_klein_text_to_image.json';

ComfyModelSlot _slot(String token) => ComfyModelSlot(
  token: token,
  loaderClass: 'UNETLoader',
  inputName: 'unet_name',
  label: token,
  folderHint: 'diffusion_models',
);

void main() {
  test(
    'saved, template, legacy and uploaded graphs are kept, bundled are not',
    () {
      for (final id in [
        'comfy:userdata:evening_shift',
        'comfy:default:image_z_image_turbo',
        'comfy:image_qwen_image',
        kComfyUploadedWorkflowId,
      ]) {
        expect(deskKeepsWorkflow(id), isTrue, reason: id);
      }
      for (final id in ['sd', 'z_image_turbo', 'flux', 'qwen_image_21']) {
        expect(deskKeepsWorkflow(id), isFalse, reason: id);
      }
    },
  );

  group('the slot a picked file goes into', () {
    test('a GGUF goes to a diffusion slot, another file to the checkpoint', () {
      final both = [_slot('%MODEL_DIFFUSION%'), _slot(kComfyCheckpointToken)];
      expect(
        deskPrimaryToken(workflowId: 'comfy:x', file: 'a.gguf', slots: both),
        '%MODEL_DIFFUSION%',
      );
      expect(
        deskPrimaryToken(
          workflowId: 'comfy:x',
          file: 'a.safetensors',
          slots: both,
        ),
        kComfyCheckpointToken,
      );
    });

    test('a graph with one kind of slot uses that slot', () {
      expect(
        deskPrimaryToken(
          workflowId: 'comfy:x',
          file: 'a.safetensors',
          slots: [_slot(kComfyCheckpointToken)],
        ),
        kComfyCheckpointToken,
      );
      expect(
        deskPrimaryToken(
          workflowId: 'comfy:x',
          file: 'a.safetensors',
          slots: [_slot('%MODEL_DIFFUSION%')],
        ),
        '%MODEL_DIFFUSION%',
      );
    });

    test('a graph not read yet falls back to the bundled rule', () {
      expect(
        deskPrimaryToken(workflowId: 'sd', file: 'a.safetensors'),
        kComfyCheckpointToken,
      );
      expect(
        deskPrimaryToken(workflowId: 'z_image_turbo', file: 'a.safetensors'),
        '%MODEL_DIFFUSION%',
      );
    });
  });

  group('the verdict carries the graph\'s slots', () {
    final template =
        jsonDecode(File(_klein).readAsStringSync()) as Map<String, dynamic>;
    final info = <String, dynamic>{
      for (final node in convertComfyUiToApi(template).values.whereType<Map>())
        node['class_type'].toString(): <String, dynamic>{},
    };

    StudioReadiness judge({
      Map<String, String> choices = const {},
      String workflowId = 'comfy:default:klein',
      String uploaded = '',
    }) {
      return deskReadiness(
        backend: 'comfyui',
        primaryFile: choices['$workflowId/%MODEL_DIFFUSION%'] ?? '',
        objectInfo: info,
        workflowId: workflowId,
        modelChoices: choices,
        liveTemplate: template,
        uploadedWorkflowJson: uploaded,
      );
    }

    test('even when nothing is chosen yet, so an empty slot can be filled', () {
      final verdict = judge();
      expect(verdict.kind, StudioReady.missingFile);
      expect(
        [for (final slot in verdict.slots) slot.token],
        containsAll([
          '%MODEL_DIFFUSION%',
          '%MODEL_CLIP%',
          '%MODEL_VAE%',
          '%MODEL_DIFFUSION_2%',
          '%MODEL_CLIP_2%',
          '%MODEL_VAE_2%',
        ]),
      );
    });

    test('an uploaded graph names its files inside itself', () {
      final verdict = judge(
        workflowId: kComfyUploadedWorkflowId,
        uploaded: jsonEncode(convertComfyUiToApi(template)),
      );
      expect(verdict.slots, isEmpty);
    });
  });

  test('a size snaps to a multiple of 64 between 256 and 2048', () {
    expect(snapStudioSize(1000, 1500), (width: 1024, height: 1472));
    expect(snapStudioSize(8, 9000), (width: 256, height: 2048));
    expect(snapStudioSize(300, 512), (width: 320, height: 512));
  });
}
