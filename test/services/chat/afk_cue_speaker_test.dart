// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Group AFK already picks a speaker and loads their needs. The idle cue
// still named the 1:1 host (null in group → "{{char}}") and used the host's
// hygiene preference. The cue must follow the picked speaker.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/services/chat/afk_cue_speaker.dart';

CharacterCard _card(
  String name, {
  List<String> ambitions = const [],
  bool enjoysLowHygiene = false,
}) {
  return CharacterCard(
    name: name,
    description: 'Exists only inside the AFK cue test.',
    firstMessage: 'Hi.',
    frontPorchExtensions: FrontPorchExtensions(
      ambitions: ambitions,
      enjoysLowHygiene: enjoysLowHygiene,
    ),
  );
}

void main() {
  test('idle cue is built from the picked speaker', () {
    final src = File(
      'lib/services/chat/chat_service_idle_autonomous.dart',
    ).readAsStringSync();
    expect(src, contains('_buildAutonomousCue(afkSpeaker)'));
    expect(src, isNot(contains('final charName = _activeCharacter?.name')));
  });

  test('group idle uses the picked speaker, not the leftover 1:1 host', () {
    final host = _card('Nina', ambitions: ['keep the porch tidy']);
    final speaker = _card(
      'Sam',
      ambitions: ['find the spare keys'],
      enjoysLowHygiene: true,
    );
    final who = AfkCueSpeaker.resolve(picked: speaker, host: host);
    expect(who.name, 'Sam');
    expect(who.ambitions, ['find the spare keys']);
    expect(who.enjoysLowHygiene, isTrue);
  });

  test('1:1 idle still uses the host when no speaker was picked', () {
    final host = _card('Nina', ambitions: ['keep the porch tidy']);
    final who = AfkCueSpeaker.resolve(picked: null, host: host);
    expect(who.name, 'Nina');
    expect(who.ambitions, ['keep the porch tidy']);
  });
}
