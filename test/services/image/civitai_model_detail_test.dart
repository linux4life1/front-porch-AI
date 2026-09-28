// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/image/civitai_client.dart';

void main() {
  test('a LoRA row keeps its picture, count, and description', () {
    const body =
        '{"items":[{"id":3,"name":"Soft light","type":"LORA","nsfw":false,'
        '"description":"<p>Warm window light.</p>",'
        '"modelVersions":[{"id":30,"stats":{"downloadCount":4321},'
        '"images":[{"url":"https://image.civitai.com/x/hero.jpeg"},'
        '{"url":"https://image.civitai.com/x/side.jpeg"}],'
        '"files":[{"name":"soft.safetensors"}]}]}]}';
    final row = parseCivitaiModels(body, includeAdult: false).single;
    expect(row.previewUrl, 'https://image.civitai.com/x/hero.jpeg');
    expect(row.imageUrls, [
      'https://image.civitai.com/x/hero.jpeg',
      'https://image.civitai.com/x/side.jpeg',
    ]);
    expect(row.downloads, 4321);
    expect(row.description, 'Warm window light.');
    expect(row.filename, 'soft.safetensors');
  });

  test('a model page uses the same fields', () {
    const body =
        '{"id":9,"name":"Studio","type":"LORA","nsfw":false,'
        '"description":"Full write-up",'
        '"modelVersions":[{"id":90,"images":'
        '[{"url":"http://insecure.example/a.jpeg"}],'
        '"files":[{"name":"studio.safetensors"}]}]}';
    final row = parseCivitaiModel(body, includeAdult: false);
    expect(row, isNotNull);
    expect(row!.description, 'Full write-up');
    expect(row.previewUrl, isNull);
    expect(row.imageUrls, isEmpty);
  });
}
