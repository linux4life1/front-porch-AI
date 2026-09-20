// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Default keyword lore ("Context Info") used to sit in the system head.
// Flipping a trigger rewrote byte 1 of the prompt, so local backends
// re-prefills the whole transcript. It belongs after history, like memories.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/prompt_plan.dart';

PromptPlan _plan({required String loreBefore}) {
  final plan = PromptPlan();
  plan.add(id: 'system', inSystem: true, text: 'SYS\n');
  plan.add(id: 'persona', inSystem: true, text: 'Persona\n');
  plan.add(id: 'start', text: '<START>\n');
  plan.add(id: 'history', text: 'You: hi\nSam: hey', counted: false);
  plan.add(id: 'lore.before', label: 'Lorebook', text: loreBefore);
  plan.add(id: 'memories', text: '', counted: false);
  plan.add(id: 'suffix', text: '\nSam:');
  return plan;
}

void main() {
  test('production register keeps lore.before out of the system zone', () {
    final src = File(
      'lib/services/chat/chat_service_generation_plan_register.dart',
    ).readAsStringSync();
    final systemAdd = src.indexOf("id: 'system'");
    final loreAdd = src.indexOf("id: 'lore.before'");
    final historyAdd = src.indexOf("id: 'history'");
    expect(loreAdd, greaterThan(historyAdd));
    expect(loreAdd, greaterThan(systemAdd));
    expect(src.contains("id: 'lore.before',\n      inSystem: true"), isFalse);
  });

  test('keyword lore does not change the system prefix', () {
    final off = _plan(loreBefore: '');
    final on = _plan(loreBefore: 'Context Info:\nThe docks are on fire.\n');
    expect(on.systemText, off.systemText);
    expect(on.systemText, isNot(contains('docks')));
    expect(on.userText, contains('The docks are on fire.'));
  });
}
