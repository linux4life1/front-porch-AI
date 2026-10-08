// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'kobold_binary_version.dart';

/// What the start-up look at the managed KoboldCpp should put in front of
/// the user. [tooOld] is a box with no "Not now": the engine is refused at
/// every launch below [KoboldBinaryVersion.minimum], so the only ways on are
/// an update or removing it. [newer] can be put off for [kKoboldUpdateSnooze]
/// per release.
enum KoboldUpdateGate { nothing, newer, tooOld }

/// How long "Not now" holds, for the release it was pressed on.
const Duration kKoboldUpdateSnooze = Duration(days: 3);

/// Preference keys for the snooze (through the settings' `k()`, so a nightly
/// and the stable app keep their own).
const String kKoboldUpdateSnoozedUntilKey = 'kobold_update_snoozed_until';
const String kKoboldUpdateSnoozedVersionKey = 'kobold_update_snoozed_version';

/// The decision, from facts the caller has already gathered.
///
/// [version] is the engine's size-verified record (null when the binary has
/// none, which counts as current, the same as the launch refusal). An engine
/// that is not [installed] shows nothing: KoboldCpp is optional. Below the
/// floor the answer is [KoboldUpdateGate.tooOld] whatever the network or the
/// auto-check setting says. Otherwise a newer release shows once per release:
/// a "Not now" on [snoozedVersion] holds until [snoozedUntil], and a release
/// after that one asks at once.
KoboldUpdateGate koboldUpdateGate({
  required bool installed,
  required String? version,
  required String? remoteVersion,
  required bool updateAvailable,
  required bool autoCheck,
  required DateTime now,
  DateTime? snoozedUntil,
  String? snoozedVersion,
}) {
  if (!installed) return KoboldUpdateGate.nothing;
  if (KoboldBinaryVersion.tooOldProblem(version) != null) {
    return KoboldUpdateGate.tooOld;
  }
  if (!autoCheck || remoteVersion == null || !updateAvailable) {
    return KoboldUpdateGate.nothing;
  }
  final held =
      snoozedUntil != null &&
      now.isBefore(snoozedUntil) &&
      snoozedVersion == remoteVersion;
  return held ? KoboldUpdateGate.nothing : KoboldUpdateGate.newer;
}
