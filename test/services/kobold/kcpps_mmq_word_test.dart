// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// A preset made in KoboldCpp's own launcher says "no MMQ" as a word in the
// CUDA list, and KoboldCpp reads that word before the `nommq` setting: with
// the word in the list MMQ is off whatever the setting says. The reader and
// the merge that saves an edit must both go by that.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/kobold/kobold.dart';

KcppsOk _read(Map<String, dynamic> map) =>
    readKcpps(jsonEncode(map)) as KcppsOk;

void main() {
  test('MMQ is off when the CUDA list says nommq, as KoboldCpp reads it, '
      'whatever the setting says', () {
    bool? mmq(Map<String, dynamic> map) => _read(map).config.mmq;
    expect(
      mmq({
        'usecuda': ['normal', '0', 'nommq'],
        'nommq': false,
      }),
      isFalse,
    );
    expect(
      mmq({
        'usecuda': ['normal', '0', 'nommq'],
      }),
      isFalse,
    );
    // Without the word, the setting decides.
    expect(mmq({'nommq': true}), isFalse);
    expect(mmq({'nommq': false}), isTrue);
    expect(
      mmq({
        'usecuda': ['normal', '0', 'mmq'],
      }),
      isTrue,
    );
    expect(mmq({'contextsize': 4096}), isNull);
  });

  test('an edit of MMQ rewrites the card and the setting together, so the '
      'word cannot outlive it', () {
    final raw = <String, dynamic>{
      'contextsize': 4096,
      'usecuda': ['normal', '0', 'nommq'],
      'usecublas': ['normal', '0', 'nommq'],
    };
    Map<String, dynamic> form(bool mmq) =>
        kcppsMap(_read(raw).config.copyWith(mmq: mmq));
    final out = kcppsMergeEdits(raw, form(false), form(true));
    expect(out['usecuda'], ['normal', '0']);
    expect(out['usecublas'], ['normal', '0']);
    expect(out['nommq'], isFalse);
    // Nothing else of the file moves.
    expect(out['contextsize'], 4096);
  });
}
