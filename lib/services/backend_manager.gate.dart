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

part of 'backend_manager.dart';

/// What the start-up gate on the managed KoboldCpp needs from the manager:
/// the engine's verified version, a version check it can wait on, the
/// snooze of a "Not now", and removing an engine the user will not update.
extension BackendManagerGate on BackendManager {
  /// Resolves once the first look for the engine file is over, so a reader
  /// does not act on [backendPath] before it is known.
  Future<void> get engineChecked => _engineChecked.future;

  /// The installed engine's version from the record written for this very
  /// binary, or null when there is none: the same answer the launch refusal
  /// works from, so the gate and the refusal agree.
  Future<String?> installedVersion() async {
    final exe = _backendPath;
    if (exe == null) return null;
    return KoboldBinaryVersion.versionFor(exe);
  }

  /// Waits for the version check: the one start-up began, if it is still
  /// running, or a fresh one.
  Future<void> awaitVersionCheck() async {
    if (!_isCheckingVersion) return checkForUpdates();
    final done = Completer<void>();
    void listener() {
      if (!_isCheckingVersion && !done.isCompleted) done.complete();
    }

    addListener(listener);
    try {
      if (!_isCheckingVersion) return;
      await done.future;
    } finally {
      removeListener(listener);
    }
  }

  /// The snooze of the newer-engine box: a "Not now" pressed on
  /// [snoozedVersion], holding until [until].
  Future<({DateTime? until, String? version})> readUpdateSnooze() async {
    final prefs = await SharedPreferences.getInstance();
    final k = _storageService.backendSettings.k;
    return (
      until: DateTime.tryParse(
        prefs.getString(k(kKoboldUpdateSnoozedUntilKey)) ?? '',
      ),
      version: prefs.getString(k(kKoboldUpdateSnoozedVersionKey)),
    );
  }

  /// "Not now" on the newer-engine box: holds [kKoboldUpdateSnooze] for
  /// [remoteVersion]; a release after it asks at once.
  Future<void> snoozeUpdate(String remoteVersion, {DateTime? now}) async {
    final prefs = await SharedPreferences.getInstance();
    final k = _storageService.backendSettings.k;
    await prefs.setString(
      k(kKoboldUpdateSnoozedUntilKey),
      (now ?? DateTime.now()).add(kKoboldUpdateSnooze).toIso8601String(),
    );
    await prefs.setString(k(kKoboldUpdateSnoozedVersionKey), remoteVersion);
  }

  /// The start-up decision: nothing, a newer release, or an engine below
  /// the floor. Below the floor needs no network; the newer-release look
  /// follows the same auto-check setting the Settings page uses, and waits
  /// for the version check start-up began.
  Future<KoboldUpdateGate> updateGate({
    DateTime? now,
    @visibleForTesting bool? autoCheck,
  }) async {
    await engineChecked;
    final installed = _backendPath != null && !isIntelMac;
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
    final snooze = await readUpdateSnooze();
    return koboldUpdateGate(
      installed: true,
      version: version,
      remoteVersion: _remoteVersion,
      updateAvailable: isUpdateAvailable,
      autoCheck: true,
      now: now ?? DateTime.now(),
      snoozedUntil: snooze.until,
      snoozedVersion: snooze.version,
    );
  }

  /// Stands in for the GitHub lookup in tests.
  @visibleForTesting
  void seedRemoteVersion(String version, {int? assetSize}) {
    _remoteVersion = version;
    _remoteAssetSize = assetSize;
    notifyListeners();
  }

  /// Removes the managed engine and its version record, for a user who
  /// will not update an engine below the floor and uses another backend.
  /// Every engine file in the closet goes (Linux can hold the variant of
  /// an earlier GPU choice beside the current one, and the lookup would
  /// fall back to it), and a half-downloaded `.part`. The app downloads a
  /// current one again from Settings when asked. Returns what went wrong,
  /// in a sentence, or null.
  Future<String?> removeEngine() async {
    final exe = _backendPath;
    if (exe == null) return null;
    try {
      final dir = Directory(path.dirname(exe));
      await for (final entry in dir.list()) {
        if (entry is! File) continue;
        final name = path.basename(entry.path);
        if (name.startsWith('koboldcpp') ||
            name == KoboldBinaryVersion.fileName) {
          await entry.delete();
        }
      }
    } on FileSystemException catch (e) {
      final why = 'KoboldCpp could not be removed: ${e.osError?.message ?? e}';
      _error = why;
      notifyListeners();
      return why;
    }
    _localVersion = null;
    _localSize = null;
    _error = null;
    await checkBackendAvailability();
    return null;
  }
}
