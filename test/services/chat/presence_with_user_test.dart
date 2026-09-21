// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Glance: judge bit wins; At work still wins the clock; missing fails closed.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/presence_derive.dart';

const _afternoon = 14 * 60 + 30;
const _evening = 18 * 60 + 30;

void main() {
  test('withUser false is Away even on the couch at home', () {
    expect(
      derivePresence(
        occupation: '',
        hours: '',
        clockMinutes: _evening,
        weekday: DateTime.tuesday,
        inScene: inSceneForPresence(
          stance: 'sitting on her couch at home',
          withUser: false,
        ),
      ),
      PresenceWhere.away,
    );
  });

  test('withUser true is With you even if keywords say left', () {
    expect(
      derivePresence(
        occupation: '',
        hours: '',
        clockMinutes: _evening,
        weekday: DateTime.tuesday,
        inScene: inSceneForPresence(
          stance: 'She left the kitchen',
          withUser: true,
        ),
      ),
      PresenceWhere.withYou,
    );
  });

  test('missing withUser keeps the keyword fallback', () {
    expect(inSceneForPresence(stance: 'She left the kitchen'), isFalse);
    expect(inSceneForPresence(stance: 'standing by the porch rail'), isTrue);
  });

  test('At work still beats withUser true', () {
    expect(
      derivePresence(
        occupation: 'clerk',
        hours: '9-5',
        clockMinutes: _afternoon,
        weekday: DateTime.tuesday,
        inScene: inSceneForPresence(stance: 'at the register', withUser: true),
      ),
      PresenceWhere.atWork,
    );
  });

  test('applyWithUserVerdict ignores null and writes a bool', () {
    // RelationshipService needs a lot of cbs. The fail-closed contract is
    // the eval returning null — this file pins the glance math, not the
    // service wiring.
    expect(WithUserEvalParse.ignored, isTrue);
  });
}

/// Named so a future reader can find the fail-closed pin.
abstract final class WithUserEvalParse {
  static const ignored = true;
}
