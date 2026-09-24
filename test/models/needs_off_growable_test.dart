// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Turning a need back on must be able to mutate needsOff. A const default
// throws "Cannot modify an unmodifiable list" on Save.
// Proven red: FrontPorchExtensions().needsOff.add / remove threw.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/models.dart';

void main() {
  test('default needsOff can be mutated when a need is turned off then on', () {
    final ext = FrontPorchExtensions();
    expect(
      () => ext.needsOff.add('hunger'),
      returnsNormally,
      reason:
          'Save / persist mutate needsOff in place. const [] throws '
          '"Cannot modify an unmodifiable list"',
    );
    expect(ext.needsOff, ['hunger']);
    expect(
      () => ext.needsOff.remove('hunger'),
      returnsNormally,
      reason: 're-enabling a need removes the key — must not throw',
    );
    expect(ext.needsOff, isEmpty);
  });

  test('fromJson without needs_off is growable so Save can re-enable', () {
    final ext = FrontPorchExtensions.fromJson({
      'version': '2.5',
      'realism_engine': {'enabled': true, 'needs_sim_enabled': true},
    });
    expect(() => ext.needsOff.add('bladder'), returnsNormally);
    expect(() => ext.needsOff.remove('bladder'), returnsNormally);
    expect(jsonEncode(ext.toJson()), isNotEmpty);
  });

  test('copyWith does not share the source needsOff list', () {
    final src = FrontPorchExtensions(needsOff: ['hunger']);
    final next = src.copyWith(needsOff: const []);
    expect(() => next.needsOff.add('bladder'), returnsNormally);
    expect(src.needsOff, ['hunger']);
    expect(next.needsOff, ['bladder']);
  });
}
