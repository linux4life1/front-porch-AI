// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The draft settings the editor manages besides the draft model: tokens
// guessed each step (`draftamount`) and the model's own draft heads
// (`usemtp`), read, written back and said in plain words; and whether a
// model file has draft heads at all (real headers).

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/kobold/kobold.dart';
import 'package:front_porch_ai/utils/gguf_parser.dart';

KcppsOk _read(Map<String, Object?> map) =>
    readKcpps(jsonEncode(map)) as KcppsOk;

void main() {
  test('tokens guessed each step and the draft heads are read and written '
      'back', () {
    final read = _read({
      'draftmodel': '/m/small.gguf',
      'draftamount': 6,
      'usemtp': true,
    });
    expect(read.config.draftAmount, 6);
    expect(read.config.useMtp, isTrue);
    expect(read.unmanagedKeys, isEmpty);
    final back = kcppsMap(read.config);
    expect(back['draftamount'], 6);
    expect(back['usemtp'], isTrue);
  });

  test('a preset without them gets neither written', () {
    final back = kcppsMap(_read({'model_param': '/m/a.gguf'}).config);
    expect(back.containsKey('draftamount'), isFalse);
    expect(back.containsKey('usemtp'), isFalse);
  });

  test('the editor form carries them into the preset it writes, and an '
      'emptied amount is left to KoboldCpp', () {
    const d = KcppsDraft(
      name: 'Fast',
      modelPath: '/m/a.gguf',
      draftModelPath: '/m/small.gguf',
      draftAmount: 3,
      useMtp: true,
    );
    final map = d.toMap();
    expect(map['draftamount'], 3);
    expect(map['usemtp'], isTrue);
    expect(
      d.copyWith(clearDraftAmount: true).toMap().containsKey('draftamount'),
      isFalse,
    );
    final back = KcppsDraft.fromConfig('Fast', _read(map).config);
    expect(back.draftAmount, 3);
    expect(back.useMtp, isTrue);
  });

  test('in plain words, with the vision file warning', () {
    final words = kcppsPlainWords(
      _read({
        'model_param': '/m/Big-24B-Q4_K_M.gguf',
        'usemtp': true,
        'draftamount': 2,
        'mmproj': '/m/vision.gguf',
      }).config,
    );
    expect(
      words,
      contains("The model's own draft heads guess ahead to write faster."),
    );
    expect(words, contains('It guesses 2 tokens at a time'));
    expect(
      words,
      contains('Guessing ahead and a vision file should not be used together.'),
    );
    final plain = kcppsPlainWords(
      _read({'model_param': '/m/Big-24B-Q4_K_M.gguf'}).config,
    );
    expect(plain, isNot(contains('guess')));
  });

  test('a model file says whether it has draft heads', () async {
    const dir = 'test/fixtures/gguf_headers';
    final mtp = await GGUFParser.getModelArchitectureInfo(
      '$dir/Qwen3.6-35B-A3B-MTP.gguf',
    );
    final plain = await GGUFParser.getModelArchitectureInfo(
      '$dir/Qwen3.6-35B-A3B.gguf',
    );
    expect(mtp!.draftHeads, 1);
    expect(plain!.draftHeads, 0);
  });
}
