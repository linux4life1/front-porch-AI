// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Needs chip's hover reason comes from the needs-impact judge's "reason".
// A reason that quoted someone came back as a lone backslash (the reader
// stopped at the first escaped quote). Both the turn pass and the manual
// Reprocess read it, so both are pinned here.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/needs_simulation.dart';

import 'needs_impact_evaluator_test.dart' show createTestEvaluator;

const _answer =
    r'{"fun_delta": 6, "reason": "\"Best pie on the porch,\" she says, '
    r'and laughs."}';
const _expected = '"Best pie on the porch," she says, and laughs.';

const _pre = <String, int>{
  'hunger': 50,
  'energy': 50,
  'hygiene': 50,
  'fun': 50,
  'social': 50,
  'bladder': 50,
  'comfort': 50,
};

NeedsSimulation _sim() => NeedsSimulation(
  onNotify: () {},
  onSaveChat: () async {},
  getTimeOfDay: () => 'evening',
  getRealismEnabled: () => true,
  getObserverMode: () => false,
  getCurrentSpeakerIdForRealism: () => 'char-1',
  getIsGroupNonObserverMode: () => false,
  getGroupNeeds: (_) => {},
  setGroupNeeds: (_, _) {},
  getEnjoysLowHygiene: () => false,
  getNeedsSimEnabled: () => true,
)..restoreFromSnapshot({'vector': Map<String, int>.from(_pre)});

void main() {
  test('the turn pass keeps a quoted reason whole', () async {
    final sim = _sim();
    final e = createTestEvaluator(
      sim: sim,
      activeCharFn: () => CharacterCard(name: 'Pie Baker'),
      impactCallFn: (r, {onChunk, userCritique, previousDeltas}) async =>
          _answer,
    );
    await e.evaluateAndApply('they share a slice of pie');
    final fun =
        sim.computeNeedsDeltasWithReasons(_pre)['fun'] as Map<String, dynamic>;
    expect(fun['delta'], 6);
    expect(fun['reason'], _expected);
  });

  test('Reprocess keeps a quoted reason whole', () async {
    final sim = _sim();
    final e = createTestEvaluator(
      sim: sim,
      impactCallFn: (r, {onChunk, userCritique, previousDeltas}) async =>
          _answer,
    );
    final ok = await e.reprocessWithUserCritique(
      'they share a slice of pie',
      {},
      'fun should go up',
    );
    expect(ok, isTrue);
    final fun =
        sim.computeNeedsDeltasWithReasons(_pre)['fun'] as Map<String, dynamic>;
    expect(fun['reason'], _expected);
  });
}
