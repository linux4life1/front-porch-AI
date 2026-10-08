// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/image/studio_desk_logic.dart';
import 'package:front_porch_ai/services/image/studio_graph_menu.dart';

void main() {
  List<String> ids({
    required String modelFile,
    bool edit = false,
    List<DeskGraphRow> templates = const [],
    List<DeskGraphRow> saved = const [],
    List<DeskGraphRow> unread = const [],
  }) {
    return [
      for (final row in deskGraphMenu(
        edit: edit,
        modelFile: modelFile,
        templates: templates,
        saved: saved,
        unread: unread,
      ))
        row.id,
    ];
  }

  test('a loaded Z-Image file lists only the graph that can load it', () {
    final listed = ids(
      modelFile: 'z_image_turbo_bf16.safetensors',
      templates: const [
        DeskGraphRow('comfy:default:image_z_image_turbo', 'Z-Image Turbo'),
        DeskGraphRow('comfy:default:flux_schnell', 'Flux Schnell'),
        DeskGraphRow('comfy:default:my_portrait', 'my portrait'),
      ],
      saved: const [
        DeskGraphRow('comfy:userdata:flux_evening', 'flux_evening'),
      ],
      unread: const [DeskGraphRow('comfy:userdata:closed', 'closed')],
    );
    expect(listed, contains('z_image_turbo'));
    expect(listed, contains('comfy:default:image_z_image_turbo'));
    expect(listed, contains('comfy:default:my_portrait'));
    expect(listed, contains('comfy:userdata:flux_evening'));
    expect(listed, contains('comfy:userdata:closed'));
    expect(listed, isNot(contains('flux')));
    expect(listed, isNot(contains('qwen_image')));
    expect(listed, isNot(contains('qwen_image_21')));
    expect(listed, isNot(contains('sd')));
    expect(listed, isNot(contains('comfy:default:flux_schnell')));
  });

  test('Qwen-Image 2.1 does not list the 1.0 graph', () {
    final listed = ids(
      modelFile: 'qwen_image_2.1_q8.gguf',
      templates: const [
        DeskGraphRow('comfy:default:image_qwen_image', 'image_qwen_image'),
      ],
    );
    expect(listed, contains('qwen_image_21'));
    expect(listed, isNot(contains('qwen_image')));
    expect(listed, isNot(contains('z_image_turbo')));
    expect(listed, isNot(contains('comfy:default:image_qwen_image')));
  });

  test('an SDXL checkpoint lists the shared checkpoint graph', () {
    final listed = ids(
      modelFile: 'illustrious_xl.safetensors',
      templates: const [
        DeskGraphRow('comfy:default:image_z_image_turbo', 'Z-Image Turbo'),
      ],
    );
    expect(listed, contains('sd'));
    expect(listed, isNot(contains('z_image_turbo')));
    expect(listed, isNot(contains('flux')));
    expect(listed, isNot(contains('qwen_image')));
    expect(listed, isNot(contains('comfy:default:image_z_image_turbo')));
  });

  test('an edit Flux file lists Flux Kontext only', () {
    expect(ids(edit: true, modelFile: 'flux1-dev.safetensors'), [
      'flux_kontext',
    ]);
  });

  test('a GGUF with no family name lists the Z-Image graph', () {
    expect(ids(modelFile: 'mystery.gguf'), ['z_image_turbo']);
  });

  test('no model file still lists every premade graph', () {
    final listed = ids(modelFile: '');
    expect(listed, containsAll(['sd', 'flux', 'qwen_image', 'z_image_turbo']));
  });
}
