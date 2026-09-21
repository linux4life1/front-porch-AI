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

import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/system_role_probe.dart';

/// KoboldService's half of the `--jinja` system-message workaround: WHEN the
/// probe key is resolved, when the measurement is armed, and the one boolean
/// the transport asks for on every generation. [SystemRoleProbe] owns the
/// measurement itself and the reasoning behind it; this owns the wiring.
///
/// Separate from `kobold_service.dart` because the two answer different
/// questions — that file is the service (process, readiness, transport), this
/// is one capability's lifecycle — and because the wiring has exactly three
/// events (arm, read, forget) that must stay in step with each other. Kept
/// together they are three lines you can check at a glance; scattered through
/// a 900-line service they are how a `forget` goes missing.
class KoboldSystemRole {
  /// Defaults to the app-wide [SystemRoleProbe.instance] so the provider graph
  /// does not have to construct and thread one. Tests pass their own, which is
  /// what makes them hermetic: a verdict map shared between test cases is
  /// shared state, and shared state under `--concurrency=4` is a flake.
  KoboldSystemRole({SystemRoleProbe? probe})
    : _probe = probe ?? SystemRoleProbe.instance;

  final SystemRoleProbe _probe;

  String _identity = '';

  /// This model's key in [SystemRoleProbe], resolved once by [arm] and empty
  /// until then (an empty identity is never probed and never folds).
  ///
  /// A cached STRING, never a getter — [systemRoleIdentityFor] documents why
  /// recomputing it silently switches the workaround off. Second, independent
  /// reason: `kcppsModelPath` is a synchronous `existsSync` +
  /// `readAsStringSync` + `jsonDecode` of the preset file, and
  /// [foldSystemIntoUser] is read on EVERY generation — a live getter put that
  /// file read on the per-generation path for every .kcpps user.
  String get identity => _identity;

  /// True only when THIS model was measured to discard the system message.
  /// Untested and honored both answer false, so an unmeasured backend keeps
  /// today's behaviour exactly.
  bool get foldSystemIntoUser => _probe.isSystemDropped(_identity);

  /// Resolve the key for the model that is coming up and arm the measurement.
  /// Called from the backend's model-ready transition and nowhere else — see
  /// [SystemRoleProbe] for why arming from the generation path would evict the
  /// live chat's prefix cache.
  ///
  /// Returns the measurement so a CALLER can wait on it. Production never
  /// does — nothing may wait on the verdict, or the first token after a load
  /// would be held up by three probe requests — but a test must, because the
  /// alternative is guessing when the probe is finished.
  Future<void> arm({
    required String baseUrl,
    required String backendName,
    required StorageService storage,
    required Future<int?> Function(Future<int?> Function()) runExclusive,
    required void Function(String message) log,
  }) {
    // Preset (.kcpps) launches leave lastUsedModelPath empty — the preset owns
    // the model — so fall through to the preset's own path.
    _identity = systemRoleIdentityFor(
      backendName: backendName,
      remoteModelName: storage.backendSettings.remoteModelName,
      modelPath:
          storage.backendSettings.lastUsedModelPath ??
          storage.backendSettings.kcppsModelPath,
    );
    return _probe.ensureProbed(
      baseUrl: baseUrl,
      identity: _identity,
      runExclusive: runExclusive,
      log: log,
    );
  }

  /// Drop the verdict AND cancel a measurement still on the wire. Called when
  /// the backend stops, so a GGUF swapped in at the same path is never judged
  /// by the previous file's template, and so an arm waiting on a server that
  /// no longer exists stops holding the engine's single request slot.
  void forget() {
    _probe.reset(_identity);
    _identity = '';
  }
}
