// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/opencode/opencode.dart';
import 'package:front_porch_ai/ui/settings/tabs/backend/opencode_managed_section.dart';
import 'package:front_porch_ai/ui/waifu/waifu_opencode_status.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late int lookups;
  late OpenCodeManager mgr;

  setUp(() {
    lookups = 0;
    mgr = OpenCodeManager(
      rootPath: '',
      remoteLookup: () async {
        lookups++;
        return (tag: '9.9.9', assetBytes: 1);
      },
    );
  });

  tearDown(() => mgr.dispose());

  Future<void> pumpMount(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<OpenCodeManager>.value(
        value: mgr,
        child: MaterialApp(home: Scaffold(body: child)),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('settings mount does not hit GitHub when auto-check is off', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'update_auto_check': false});
    await pumpMount(tester, const OpenCodeManagedSection());
    expect(lookups, 0);
    expect(mgr.remoteVersion, isNull);
    expect(mgr.versionError, isNull);
  });

  testWidgets('waifu status mount does not hit GitHub when auto-check is off', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'update_auto_check': false});
    await pumpMount(tester, const WaifuOpenCodeStatus());
    expect(lookups, 0);
    expect(mgr.remoteVersion, isNull);
    expect(mgr.versionError, isNull);
  });

  testWidgets('settings mount still checks GitHub when auto-check is on', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'update_auto_check': true});
    await pumpMount(tester, const OpenCodeManagedSection());
    expect(lookups, 1);
    expect(mgr.remoteVersion, '9.9.9');
  });

  test(
    'manual checkRemoteVersion still hits GitHub when auto-check is off',
    () async {
      SharedPreferences.setMockInitialValues({'update_auto_check': false});
      await mgr.checkRemoteVersion();
      expect(lookups, 1);
      expect(mgr.remoteVersion, '9.9.9');
    },
  );

  test(
    'maybeAutoCheckRemoteVersion skips GitHub when auto-check is off',
    () async {
      SharedPreferences.setMockInitialValues({'update_auto_check': false});
      await mgr.maybeAutoCheckRemoteVersion();
      expect(lookups, 0);
      expect(mgr.remoteVersion, isNull);
    },
  );

  test(
    'cached remote survives auto-check-off without another lookup',
    () async {
      SharedPreferences.setMockInitialValues({'update_auto_check': true});
      await mgr.checkRemoteVersion();
      expect(lookups, 1);
      SharedPreferences.setMockInitialValues({'update_auto_check': false});
      await mgr.maybeAutoCheckRemoteVersion();
      expect(lookups, 1);
      expect(mgr.remoteVersion, '9.9.9');
    },
  );
}
