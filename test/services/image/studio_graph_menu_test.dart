// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/image/model_family.dart';
import 'package:front_porch_ai/services/image/studio_desk_logic.dart';
import 'package:front_porch_ai/services/image/studio_graph_menu.dart';
import 'package:front_porch_ai/services/image/studio_readiness.dart';
import 'package:front_porch_ai/ui/image_studio/studio_graph_sheet.dart';

void main() {
  test('a Comfy template is listed by its title, not its stored id', () {
    final rows = deskGraphMenu(
      edit: false,
      templates: const [
        DeskGraphRow('comfy:default:image_z_image_turbo', 'Z-Image Turbo'),
      ],
      saved: const [
        DeskGraphRow('comfy:userdata:evening_shift', 'evening_shift'),
      ],
    );
    final titles = [for (final row in rows) row.title];
    expect(titles, contains('Z-Image Turbo'));
    expect(titles, contains('SD / SDXL / Pony / Illustrious'));
    expect(titles, isNot(contains('comfy:default:image_z_image_turbo')));
    expect(titles, isNot(contains('z_image_turbo')));
    final saved = rows.firstWhere(
      (row) => row.id == 'comfy:userdata:evening_shift',
    );
    expect(saved.title, 'evening shift');
    expect(saved.detail, 'Text to image · comfy:userdata:evening_shift');
    expect(
      rows.firstWhere((row) => row.id == 'z_image_turbo').title,
      'Z-Image Turbo',
    );
  });

  test('a workflow file is json, and a note is not', () {
    const graph = '{"1":{"class_type":"KSampler"}}';
    expect(workflowJsonFromBytes(utf8.encode(graph)), graph);
    expect(workflowNodeCount(graph), 1);
    expect(workflowJsonFromBytes(utf8.encode('not a workflow')), isNull);
  });

  test('image-to-image stays on Create, and an instruction edit does not', () {
    expect(
      savedGraphIsEdit({
        '1': {'class_type': 'LoadImage'},
        '2': {'class_type': 'VAEEncode'},
        '3': {'class_type': 'EmptyLatentImage'},
      }),
      isFalse,
    );
    expect(
      savedGraphIsEdit({
        '1': {'class_type': 'LoadImage'},
        '2': {'class_type': 'TextEncodeQwenImageEdit'},
      }),
      isTrue,
    );
    expect(
      savedGraphIsEdit({
        '1': {'class_type': 'LoadImage'},
        '2': {'class_type': 'ReferenceLatent'},
      }),
      isTrue,
    );
  });

  test('use anyway lets a certain LoRA mismatch generate', () {
    const lora = DeskLoraCheck(
      'qwen_lora.safetensors',
      ModelFamily.qwen,
      metadataBacked: true,
    );
    final blocked = deskReadiness(
      backend: 'a1111',
      primaryFile: 'z_image_turbo_bf16.safetensors',
      objectInfo: null,
      loras: const [lora],
    );
    expect(blocked.kind, StudioReady.loraMismatch);
    expect(
      deskLoraBlocker('z_image_turbo_bf16.safetensors', const [lora]),
      'qwen_lora.safetensors',
    );
    final allowed = deskReadiness(
      backend: 'a1111',
      primaryFile: 'z_image_turbo_bf16.safetensors',
      objectInfo: null,
      loras: const [lora],
      allowLoraMismatch: true,
    );
    expect(allowed.kind, StudioReady.ready);
  });

  testWidgets('the graph sheet shows the title and hides the stored id', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: StudioGraphSheet(
          edit: false,
          note: 'The first group is built into Front Porch.',
          rows: const [
            DeskGraphChoice(
              id: 'comfy:default:image_z_image_turbo',
              title: 'Z-Image Turbo',
              detail: 'Comfy template',
              group: 'From this Comfy',
            ),
          ],
          onPick: (_) {},
        ),
      ),
    );
    expect(find.text('Z-Image Turbo'), findsOneWidget);
    expect(find.text('Comfy template'), findsOneWidget);
    expect(find.text('comfy:default:image_z_image_turbo'), findsNothing);
    expect(
      find.text('The first group is built into Front Porch.'),
      findsOneWidget,
    );
  });
}
