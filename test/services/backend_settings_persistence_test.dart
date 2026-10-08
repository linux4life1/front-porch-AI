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

// Regression guards for the "my context limit doesn't survive a restart"
// report. The persistence layer was never the bug — setContextSize always
// round-tripped — the Settings page's silent auto-config was re-running on
// every visit for users whose saved gpuLayers was 0 and persisting a
// recomputed context over the saved one. These tests pin the facts the fix
// relies on: the round trip works, and `gpuLayersConfigured` distinguishes
// "never configured" from "deliberately 0".
//
// A third group used to pin that the optimizer honoured a requested context
// size. It went with the optimizer: KoboldCpp now fits the model itself and
// nothing in the app recomputes the context size, so there is no longer
// anything that could overwrite the saved one.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/storage/settings/backend_settings.dart';

Future<BackendSettings> _loadedSettings(Map<String, Object> values) async {
  // Keys must ride the beta-aware prefix exactly as production writes them.
  final probe = BackendSettings();
  SharedPreferences.setMockInitialValues({
    for (final e in values.entries) probe.k(e.key): e.value,
  });
  final prefs = await SharedPreferences.getInstance();
  final settings = BackendSettings();
  settings.initializeBase(prefs, () {});
  settings.load();
  return settings;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('context size persistence', () {
    test('setContextSize survives a reload (app restart)', () async {
      final s = await _loadedSettings({});
      await s.setContextSize(32768);

      final reloaded = BackendSettings();
      reloaded.initializeBase(await SharedPreferences.getInstance(), () {});
      reloaded.load();
      expect(reloaded.contextSize, 32768);
    });

    test('saved context size wins over the fresh-install default', () async {
      final s = await _loadedSettings({'context_size': 65536});
      expect(s.contextSize, 65536);
    });
  });

  group('gpuLayersConfigured (silent auto-config gate)', () {
    test('false on a fresh install', () async {
      final s = await _loadedSettings({});
      expect(s.gpuLayersConfigured, isFalse);
    });

    test('true after an explicit CPU-only choice of 0 — the case the old '
        '`gpuLayers == 0` guard got wrong', () async {
      final s = await _loadedSettings({});
      await s.setGpuLayers(0);
      expect(s.gpuLayers, 0);
      expect(s.gpuLayersConfigured, isTrue);

      final reloaded = BackendSettings();
      reloaded.initializeBase(await SharedPreferences.getInstance(), () {});
      reloaded.load();
      expect(reloaded.gpuLayersConfigured, isTrue);
    });

    test('true for an existing install with a saved non-zero value', () async {
      final s = await _loadedSettings({'gpu_layers': 24});
      expect(s.gpuLayersConfigured, isTrue);
    });
  });
}
