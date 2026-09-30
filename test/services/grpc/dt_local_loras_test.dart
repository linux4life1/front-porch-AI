// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/grpc/dt_native/dt_local_loras.dart';

void main() {
  test('local Models folder lists LoRA weights that exist', () async {
    final dir = await Directory.systemTemp.createTemp('dt_loras_');
    try {
      await File(
        p.join(dir.path, 'flux_style_lora_f16.ckpt'),
      ).writeAsBytes(const [1]);
      await File(p.join(dir.path, 'notes_lora.txt')).writeAsString('no');
      await File(p.join(dir.path, 'custom_lora.json')).writeAsString(
        jsonEncode([
          {
            'file': 'flux_style_lora_f16.ckpt',
            'name': 'Style',
            'version': 'flux2_9b',
          },
          {
            'file': 'detail_slider.ckpt',
            'name': 'Detail',
            'version': 'qwen_image',
          },
          {'file': 'gone_lora_f16.ckpt', 'name': 'Gone', 'version': 'flux1'},
        ]),
      );
      await File(
        p.join(dir.path, 'detail_slider.ckpt'),
      ).writeAsBytes(const [2]);

      final rows = await drawThingsLoraFilesIn(dir);
      expect(rows.map((r) => r.file), [
        'detail_slider.ckpt',
        'flux_style_lora_f16.ckpt',
      ]);
      expect(
        rows.firstWhere((r) => r.file == 'flux_style_lora_f16.ckpt').version,
        'flux2_9b',
      );
      expect(
        rows.firstWhere((r) => r.file == 'detail_slider.ckpt').version,
        'qwen_image',
      );
      expect(rows.map((r) => r.file), isNot(contains('gone_lora_f16.ckpt')));
      expect(rows.map((r) => r.file), isNot(contains('notes_lora.txt')));
      expect(rows.map((r) => r.file), isNot(contains('custom_lora.json')));
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('echo paths reduce to the file name Draw Things loads', () {
    expect(
      drawThingsLoraBasename(r'lora/flux_style_lora_f16.ckpt'),
      'flux_style_lora_f16.ckpt',
    );
    expect(drawThingsHostIsLocal('127.0.0.1'), isTrue);
    expect(drawThingsHostIsLocal('10.0.0.4'), isFalse);
  });
}
