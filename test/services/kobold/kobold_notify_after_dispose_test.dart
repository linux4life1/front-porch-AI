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

// dispose() starts a stop it does not wait for, so the stop's last log lines
// arrive after the service is gone. They must not tell anyone: a disposed
// ChangeNotifier that notifies throws in debug builds, which failed whatever
// test was tearing a service down when the line landed.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/system_role_probe.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a log line that lands after dispose tells no one and throws '
      'nothing', () async {
    final dir = await Directory.systemTemp.createTemp('fpai notify dispose');
    addTearDown(() => dir.delete(recursive: true));
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => call.method == 'getApplicationDocumentsDirectory'
              ? dir.path
              : null,
        );
    SharedPreferences.setMockInitialValues({'update_auto_check': false});
    final storage = StorageService();
    await storage.initialized;
    final kobold = KoboldService(
      storage,
      systemRoleProbe: SystemRoleProbe(retryBackoff: Duration.zero),
    )..setBaseUrl('http://127.0.0.1:1');
    var heard = 0;
    kobold.addListener(() => heard++);
    kobold.notify();
    expect(heard, 1, reason: 'a live service still tells its listeners');

    kobold.dispose();
    heard = 0;
    // What the stop's late log line does.
    expect(kobold.notify, returnsNormally);
    expect(heard, 0);
  });
}
