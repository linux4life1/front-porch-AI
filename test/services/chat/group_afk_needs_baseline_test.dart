// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Group AFK used to stamp needs_pre_turn_vector from the live scalar
// (whoever last spoke) before picking who would write the idle turn.
// The chip then subtracted the previous speaker from the AFK speaker.
//
// Proven red: without _pickPresentGroupSpeaker before the stamp, the
// call-site scan fails.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('group AFK picks the speaker before stamping the needs baseline', () {
    final src = File(
      'lib/services/chat/chat_service_idle_autonomous.dart',
    ).readAsStringSync();
    final pick = src.indexOf('_pickPresentGroupSpeaker()');
    final load = src.indexOf('_loadGroupRealismIntoScalars(sid)');
    final stamp = src.indexOf("'needs_pre_turn_vector'");
    final gen = src.indexOf('forceSpeaker: afkSpeaker');
    expect(pick, greaterThanOrEqualTo(0));
    expect(load, greaterThan(pick));
    expect(stamp, greaterThan(load));
    expect(gen, greaterThan(stamp));
  });
}
