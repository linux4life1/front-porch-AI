// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// After a skip of a day or more, the moment the scene left is gone: the
// mood it raised has settled, a fixation has passed, and nobody is still
// standing where they stood. Every present character goes back to the
// card's resting mood with no fixation and no posture, so the next reply
// is not "still furious, still on the couch" two weeks later. Bond, trust
// and arousal are relationship state and stay as they are.
//
// Send and regen both run this before the realism judges, so a regen of a
// long skip's reply starts from the same settled state the first reply did.

import 'package:front_porch_ai/services/chat/mood_registers.dart';
import 'package:front_porch_ai/services/chat/realism_scope.dart';

class LongSkipSettle {
  const LongSkipSettle(this._scope);

  final RealismScope _scope;

  void settle() {
    final rel = _scope.relationship();
    final ext = _scope.session.activeCharacter?.frontPorchExtensions;
    MoodRegisters(
      _scope,
    ).seed(ext?.characterEmotion ?? '', ext?.emotionIntensity ?? '');
    rel.updateFixationFromEvalResult('none');
    rel.setSpatialStance('');
    if (_scope.session.activeGroup == null) return;
    for (final card in _scope.session.groupCharacters) {
      final member = _scope.groups.members[_scope.characterIdFor(card)];
      if (member == null) continue;
      final cardExt = card.frontPorchExtensions;
      member.emotion = cardExt?.characterEmotion ?? '';
      member.emotionIntensity = cardExt?.emotionIntensity ?? '';
      member.emotionCause = '';
      member.emotionHeldTurns = 0;
      member.fixation = '';
      member.fixationLifespan = 0;
      member.spatialStance = '';
    }
  }
}
