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

// Settings → Backend → "Start Backend" must record the model it launches.
//
// storage.backendSettings.lastUsedModelPath is the app's ONLY memory of which GGUF is loaded:
// the system-role/template probe files its verdict under it, the auto-restart
// path relaunches it, "Restart Backend" on the Advanced tab uses it, and the
// web UI marks it as the loaded model. The Backend tab auto-picks the FIRST
// model in the list when the user never touched the dropdown, so launching
// without writing this scalar loads model A while every consumer still points
// at model B. The twin surface (model_settings_dialog.local_actions.dart) has
// always written it.
//
// _toggleManagedBackend is a private State method behind the whole settings
// provider graph (KoboldService + BackendManager + ModelManager + storage) and
// spawns a real process at the end, so there is no unit seam to drive — this
// reads the call site, like chaos_global_toggle_test does.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('launching the managed backend persists the model it loaded', () {
    final src = File(
      'lib/ui/pages/settings_page.controls.dart',
    ).readAsStringSync();

    final method = RegExp(
      r'Future<void> _toggleManagedBackend\(.*?\n  \}',
      dotAll: true,
    ).firstMatch(src);
    expect(
      method,
      isNotNull,
      reason:
          'could not read _toggleManagedBackend — if it moved, move this '
          'guard with it rather than deleting it',
    );
    final body = method!.group(0)!;

    final persist = body.indexOf('setLastUsedModelPath(_selectedModelPath)');
    final launch = body.indexOf('startKobold(');
    expect(
      persist,
      greaterThanOrEqualTo(0),
      reason:
          'Launch Backend starts a model without recording it in '
          'lastUsedModelPath — the system-role probe, auto-restart, Restart '
          'Backend and the web UI would all point at a different GGUF than '
          'the one actually running',
    );
    expect(
      launch,
      greaterThan(persist),
      reason: 'the model must be recorded before the process is started',
    );
    // The preset branch passes '' and lets the .kcpps supply the model, so the
    // recording sits with the effectiveModel decision, not before it.
    expect(
      body.indexOf('final effectiveModel ='),
      lessThan(persist),
      reason:
          'the recording must sit in the branch that actually passes a '
          'model path',
    );
  });
}
