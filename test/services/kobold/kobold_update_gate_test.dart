// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The start-up decision about the managed KoboldCpp: nothing when it is not
// installed (it is optional), the red box below the floor whatever the
// network or the auto-check setting says, the amber box for a newer release
// once per release, held three days by "Not now".
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/kobold/kobold.dart';

void main() {
  final now = DateTime(2026, 10, 7, 12);
  KoboldUpdateGate gate({
    bool installed = true,
    String? version = '1.120',
    String? remoteVersion = '1.130',
    bool updateAvailable = true,
    bool autoCheck = true,
    DateTime? snoozedUntil,
    String? snoozedVersion,
  }) => koboldUpdateGate(
    installed: installed,
    version: version,
    remoteVersion: remoteVersion,
    updateAvailable: updateAvailable,
    autoCheck: autoCheck,
    now: now,
    snoozedUntil: snoozedUntil,
    snoozedVersion: snoozedVersion,
  );

  test('not installed shows nothing, even below the floor', () {
    expect(gate(installed: false, version: '1.100'), KoboldUpdateGate.nothing);
  });

  test('below the floor is the red box, with or without the network or the '
      'auto-check', () {
    expect(gate(version: '1.100'), KoboldUpdateGate.tooOld);
    expect(
      gate(version: '1.111', remoteVersion: null, updateAvailable: false),
      KoboldUpdateGate.tooOld,
    );
    expect(gate(version: '1.100', autoCheck: false), KoboldUpdateGate.tooOld);
    expect(
      gate(
        version: '1.100',
        snoozedUntil: now.add(const Duration(days: 30)),
        snoozedVersion: '1.130',
      ),
      KoboldUpdateGate.tooOld,
      reason: 'a snooze is for the amber box only',
    );
  });

  test('the floor itself and above are not too old', () {
    expect(gate(version: KoboldBinaryVersion.minimum), KoboldUpdateGate.newer);
    expect(
      gate(version: '1.130', updateAvailable: false),
      KoboldUpdateGate.nothing,
    );
  });

  test('no record counts as current: amber only when a newer release is '
      'known', () {
    expect(gate(version: null), KoboldUpdateGate.newer);
    expect(
      gate(version: null, remoteVersion: null),
      KoboldUpdateGate.nothing,
      reason: 'nothing to update to',
    );
  });

  test('the amber box needs the auto-check, a known release and an update', () {
    expect(gate(autoCheck: false), KoboldUpdateGate.nothing);
    expect(gate(remoteVersion: null), KoboldUpdateGate.nothing);
    expect(gate(updateAvailable: false), KoboldUpdateGate.nothing);
    expect(gate(), KoboldUpdateGate.newer);
  });

  test('"Not now" holds for the release it was pressed on, until it runs '
      'out', () {
    final until = now.add(kKoboldUpdateSnooze);
    expect(
      gate(snoozedUntil: until, snoozedVersion: '1.130'),
      KoboldUpdateGate.nothing,
    );
    expect(
      gate(snoozedUntil: until, snoozedVersion: '1.129'),
      KoboldUpdateGate.newer,
      reason: 'a release after the snoozed one asks at once',
    );
    expect(
      gate(snoozedUntil: now, snoozedVersion: '1.130'),
      KoboldUpdateGate.newer,
      reason: 'the hold has run out',
    );
    expect(
      gate(snoozedUntil: until, snoozedVersion: null),
      KoboldUpdateGate.newer,
      reason: 'a hold with no release recorded holds nothing',
    );
  });
}
