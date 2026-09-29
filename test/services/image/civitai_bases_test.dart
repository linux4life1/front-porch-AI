// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/image/civitai_bases.dart';

void main() {
  test('the base picker lists image families and skips video', () {
    final apis = civitaiBaseApiValues();
    expect(apis, contains('Flux.1 S'));
    expect(apis, contains('Flux.1 D'));
    expect(apis, contains('Flux.1 Kontext'));
    expect(apis, contains('Flux.2 D'));
    expect(apis, contains('Flux.2 Klein 9B'));
    expect(apis, contains('Flux.2 Klein 4B'));
    expect(apis, contains('Qwen'));
    expect(apis, contains('Qwen 2'));
    expect(apis, contains('Qwen 2.1'));
    expect(apis, contains('Qwen 3'));
    expect(apis, contains('ZImageTurbo'));
    expect(apis, contains('ZImageBase'));
    expect(apis, isNot(contains('Wan Video')));
    expect(apis, isNot(contains('LTXV')));
    expect(apis, isNot(contains('Hunyuan Video')));
    expect(apis, isNot(contains('Flux 3 Video')));
    expect(apis, isNot(contains('SVD')));
    final qwen = kCivitaiBaseGroups
        .expand((group) => group.choices)
        .firstWhere((choice) => choice.api == 'Qwen');
    expect(qwen.label, contains('2512'));
    expect(qwen.label, contains('Image Edit'));
    expect(apis.toSet().length, apis.length);
  });
}
