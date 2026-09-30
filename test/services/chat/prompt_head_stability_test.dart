// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Growth, scenario fade, and the lore buckets that used to ride the system
// head must sit after history. A change there used to re-prefill the
// whole transcript.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('volatile sections are after history and not in the system zone', () {
    final src = File(
      'lib/services/chat/chat_service_generation_plan_register.dart',
    ).readAsStringSync();
    final history = src.indexOf("id: 'history'");
    expect(history, greaterThan(0));
    for (final id in [
      'growth',
      'lore.after',
      'scenario',
      'lore.ex_top',
      'lore.ex_bottom',
    ]) {
      final at = src.indexOf("id: '$id'");
      expect(at, greaterThan(history), reason: id);
      final add = src.substring(at, src.indexOf(');', at));
      expect(add.contains('inSystem: true'), isFalse, reason: id);
    }
    final before = src.indexOf("id: 'lore.before'");
    expect(before, greaterThan(history));
    expect(src.contains("id: 'lore.before',\n      inSystem: true"), isFalse);
  });

  test('impersonate places the same sections after history', () {
    final src = File(
      'lib/services/chat/chat_service_impersonate.dart',
    ).readAsStringSync();
    final history = src.indexOf("id: 'history'");
    for (final id in [
      'growth',
      'lore.after',
      'scenario',
      'lore.ex_top',
      'lore.ex_bottom',
    ]) {
      final at = src.indexOf("id: '$id'");
      expect(at, greaterThan(history), reason: id);
    }
    expect(src.contains('_groupCharacters.first'), isFalse);
    expect(src.contains('_impersonateGroupSpeaker'), isTrue);
    expect(src.contains('_pickPresentGroupSpeaker'), isTrue);
  });
}
