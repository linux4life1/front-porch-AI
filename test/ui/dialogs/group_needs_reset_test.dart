// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// GROUP SETTINGS → NEEDS → "RESET" WAS A LYING BUTTON.
//
// It rewrote the three local maps in the dialog's State and called
// resetRealismForGroupCharacter, which only drops the live _groupRealism slot.
// The member's card extension — the thing runtime _activeDecayRates() reads
// every turn — kept the hand-tuned decay rate and baselines. So a character the
// user had just "reset" went on decaying hunger at 20/turn while the slider
// read 4, and the old number reappeared the moment the dialog was reopened.
//
// WHY THIS IS A SOURCE PIN AND NOT AN INTERACTION TEST. Every ChatService door
// this tab writes through (setGroupNeedsDecayRate, resetRealismForGroupCharacter)
// is an EXTENSION member: it resolves on the static ChatService type, so a test
// double cannot intercept it — the real body runs and reaches ChatService's
// private _groupManager field, which no `implements ChatService` fake can have.
// The resulting NoSuchMethodError is an uncaught async error (the button
// discards the Future), so it is not even takeable with tester.takeException.
// And a REAL ChatService cannot be driven under testWidgets — drift wall-hangs
// there (see the note in edit_group_page_interaction_test.dart), which I
// confirmed by hanging a probe on exactly that setup. So the honest guard is:
// pin that the reset still routes through the persisting setters. Tapping the
// button for real belongs in an integration_test suite, where a live app has a
// real ChatService — noted rather than faked.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Reset persists through the doors the engine reads', () {
    final src = File(
      'lib/ui/dialogs/group_settings/needs_tab.dart',
    ).readAsStringSync();
    final reset = src.substring(
      src.indexOf('_resetCharacterNeeds(CharacterCard'),
    );

    // Decay is read off the member card ext every turn (_activeDecayRates), and
    // setGroupNeedsDecayRate(memberId:) is the only thing that writes it there
    // (+ PNG + the GroupMembers row). A reset that skips it is the bug.
    expect(reset, contains('setGroupNeedsDecayRate('));
    expect(reset, contains('memberId: id'));

    // Baselines and the hygiene preference go through the same setters the
    // sliders use — the ones that write char.frontPorchExtensions — rather than
    // a second, silent copy of the write.
    expect(reset, contains('_updateNeedsBaseline('));
    expect(reset, contains('_updateMemberEnjoysLowHygiene('));

    // ...and the local maps alone are no longer the whole story: the old body
    // assigned _needsBaselines[id] / _decayRates[id] / _enjoysLowHygiene[id]
    // directly and stopped there.
    expect(reset.contains('_needsBaselines[id] = {'), isFalse);
    expect(reset.contains('_enjoysLowHygiene[id] = false'), isFalse);

    // The member id must be the one every service stores a member under. The
    // hand-rolled version answered '' for a member with no avatar file (group
    // members resolve to an EMPTY imagePath, not null) and truncated at the
    // first dot otherwise — and setGroupNeedsDecayRate matches its target by
    // exactly this id, so a mismatch silently persists nothing.
    expect(src, contains('_getCharId(CharacterCard c) => c.stableGroupId'));
  });
}
