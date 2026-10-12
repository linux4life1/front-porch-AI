// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

// The start-up decision on the managed engine, and the snooze of the
// newer-engine box kept in SharedPreferences under the beta-aware keys [k]
// names.

import 'package:shared_preferences/shared_preferences.dart';
import 'package:front_porch_ai/services/kobold/kobold.dart';
import 'package:front_porch_ai/services/update_service.dart';

typedef KoboldUpdateSnooze = ({DateTime? until, String? version});

Future<KoboldUpdateSnooze> readKoboldUpdateSnooze(
  String Function(String key) k,
) async {
  final prefs = await SharedPreferences.getInstance();
  return (
    until: DateTime.tryParse(
      prefs.getString(k(kKoboldUpdateSnoozedUntilKey)) ?? '',
    ),
    version: prefs.getString(k(kKoboldUpdateSnoozedVersionKey)),
  );
}

/// Holds [kKoboldUpdateSnooze] from [now] for [remoteVersion].
Future<void> writeKoboldUpdateSnooze(
  String Function(String key) k,
  String remoteVersion,
  DateTime now,
) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    k(kKoboldUpdateSnoozedUntilKey),
    now.add(kKoboldUpdateSnooze).toIso8601String(),
  );
  await prefs.setString(k(kKoboldUpdateSnoozedVersionKey), remoteVersion);
}

/// Nothing, a newer release, or an installed engine below the floor. Below
/// the floor needs no network; the newer-release look follows the
/// auto-check setting the Settings page uses ([autoCheck] overrides it),
/// and waits for [awaitVersionCheck] before reading [remoteVersion] and
/// [updateAvailable].
Future<KoboldUpdateGate> decideKoboldUpdateGate({
  required bool installed,
  required Future<String?> Function() installedVersion,
  required bool? autoCheck,
  required Future<void> Function() awaitVersionCheck,
  required Future<KoboldUpdateSnooze> Function() readSnooze,
  required String? Function() remoteVersion,
  required bool Function() updateAvailable,
  required DateTime now,
}) async {
  if (!installed) return KoboldUpdateGate.nothing;
  final version = await installedVersion();
  if (KoboldBinaryVersion.tooOldProblem(version) != null) {
    return KoboldUpdateGate.tooOld;
  }
  final prefs = await SharedPreferences.getInstance();
  final check =
      autoCheck ??
      (UpdateService.isSupported &&
          (prefs.getBool('update_auto_check') ?? true));
  if (!check) return KoboldUpdateGate.nothing;
  await awaitVersionCheck();
  final snooze = await readSnooze();
  return koboldUpdateGate(
    installed: true,
    version: version,
    remoteVersion: remoteVersion(),
    updateAvailable: updateAvailable(),
    autoCheck: true,
    now: now,
    snoozedUntil: snooze.until,
    snoozedVersion: snooze.version,
  );
}
