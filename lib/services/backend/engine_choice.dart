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

// Which acceleration the engine build has to carry, and telling a real
// change of it (or of the data root) apart from the settings' every notify.

import 'package:front_porch_ai/services/gpu_backend_resolver.dart';
import 'package:front_porch_ai/services/storage/settings/backend_settings.dart';

/// What the chosen acceleration needs the engine build to carry. The
/// vendor only tells Vulkan from CPU, which every build runs.
GpuBackend neededEngineBackend(
  BackendSettings b, {
  required bool hasCuda,
  required bool onMac,
}) => GpuBackendResolver.resolve(
  userCublas: b.useCublas,
  userVulkan: b.useVulkan,
  userRocm: b.useRocm,
  userMetal: b.useMetal,
  hasCuda: hasCuda,
  vendor: 'Unknown',
  onMac: onMac,
);

/// The data root and acceleration the engine was last looked for with.
///
/// StorageService notifies on EVERY settings mutation (any slider, any
/// toggle) — but the engine look spawns processes (uname / nvidia-smi) and
/// re-reads the binary version from disk, so re-running it per notify made
/// flipping an unrelated switch spawn a process. Only the inputs it
/// actually reads matter: the data root (bin dir) and the acceleration the
/// engine build has to carry.
class EngineChoiceWatch {
  String? _root;
  GpuBackend? _wish;
  bool _loaded = false;

  /// A settings notify: null when neither input changed (nothing to do),
  /// else whether ROCm was just picked. ROCm chosen while the app runs
  /// fetches its build at once; a choice read with the settings at start-up
  /// does not: start-up never downloads on its own.
  bool? changed(String? root, GpuBackend wish) {
    if (root == _root && wish == _wish) return null;
    final pickedRocm =
        _loaded && wish == GpuBackend.rocm && _wish != GpuBackend.rocm;
    _root = root;
    _wish = wish;
    return pickedRocm;
  }

  /// The settings as saved are in: what they ask for is the baseline a
  /// later choice is told apart from. True when it differs from the last
  /// look, which then has to run again.
  bool loaded(String? root, GpuBackend wish) {
    final differs = root != _root || wish != _wish;
    _root = root;
    _wish = wish;
    _loaded = true;
    return differs;
  }
}
