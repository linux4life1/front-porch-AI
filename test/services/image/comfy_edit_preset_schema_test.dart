// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Validates the bundled ComfyUI edit presets against a REAL ComfyUI's node
// schema (a trimmed /object_info snapshot in test/fixtures, captured from a live
// server). The render itself needs models we don't ship, but this catches the
// one error class that silently breaks a graph: a node class_type that doesn't
// exist, an input name the node doesn't accept, or a node link pointing nowhere.
// If a preset gains a node, regenerate the fixture from a live /object_info.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/image/comfy_edit_workflow.dart';
import 'package:front_porch_ai/services/image/comfy_edit_presets.dart';

void main() {
  final raw = File('test/fixtures/comfy_object_info_subset.json').readAsStringSync();
  final schema = (jsonDecode(raw) as Map).cast<String, dynamic>();

  Set<String> inputsOf(String node) => ((schema[node] as Map)['inputs'] as List)
      .map((e) => e as String)
      .toSet();

  // Fill values that produce a fully-resolved graph (values are placeholders;
  // only the STRUCTURE is validated here).
  final values = <String, Object?>{
    ComfyEditTokens.image: 'ref.png',
    ComfyEditTokens.prompt: 'x',
    ComfyEditTokens.negative: '',
    ComfyEditTokens.seed: 1,
    ComfyEditTokens.steps: 20,
    ComfyEditTokens.cfg: 3.5,
    ComfyEditTokens.denoise: 1.0,
    ComfyEditTokens.sampler: 'euler',
    ComfyEditTokens.scheduler: 'simple',
    ComfyEditTokens.shift: 3.0,
  };

  for (final preset in kComfyEditPresets) {
    group('${preset.label} validates against the real ComfyUI schema', () {
      final filled = substituteComfyWorkflow(preset.template, {
        ...values,
        for (final slot in preset.modelSlots) slot.token: 'model.safetensors',
      });
      final nodeIds = filled.keys.toSet();

      test('every node class_type exists on ComfyUI', () {
        for (final entry in filled.entries) {
          final ct = (entry.value as Map)['class_type'] as String;
          expect(schema.containsKey(ct), isTrue,
              reason: 'node "${entry.key}" uses class_type "$ct" which is not a '
                  'known ComfyUI node (fixture)');
        }
      });

      test('every input name is accepted by its node', () {
        for (final entry in filled.entries) {
          final node = entry.value as Map;
          final ct = node['class_type'] as String;
          final valid = inputsOf(ct);
          final inputs = (node['inputs'] as Map).keys.cast<String>();
          for (final k in inputs) {
            expect(valid.contains(k), isTrue,
                reason: '$ct.$k is not a valid input for $ct '
                    '(valid: ${valid.toList()..sort()})');
          }
        }
      });

      test('every node link points to a node that exists in the graph', () {
        for (final entry in filled.entries) {
          final inputs = ((entry.value as Map)['inputs'] as Map);
          for (final v in inputs.values) {
            // A link is [ "nodeId", outputIndex ].
            if (v is List && v.length == 2 && v[0] is String) {
              expect(nodeIds.contains(v[0]), isTrue,
                  reason: 'link to missing node "${v[0]}" in ${entry.key}');
            }
          }
        }
      });

      test('required-node list contains exactly the graph\'s class_types', () {
        final used = filled.values
            .map((n) => (n as Map)['class_type'] as String)
            .toSet();
        expect(preset.requiredNodes.toSet(), used);
      });
    });
  }
}
