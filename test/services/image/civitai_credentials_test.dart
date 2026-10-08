// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/image/image.dart';

void main() {
  const secure = FlutterSecureStorage();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test(
    'a saved key lives in the OS key store, not in SharedPreferences',
    () async {
      final store = await CivitaiCredentialStore.open();
      await store.save('local', 'secret-token');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty);
      expect(
        await secure.read(key: 'civitai_credential_local'),
        'secret-token',
      );
      final reopened = await CivitaiCredentialStore.open();
      expect(await reopened.read('local'), 'secret-token');
    },
  );

  test(
    'sign-out clears this account, its leftover second key, and nobody else',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'civitai_credential_local': 'green',
        'civitai_credential_local_red': 'red',
        'civitai_credential_other': 'keep',
      });
      final store = await CivitaiCredentialStore.open();
      await store.signOut('local');
      expect(await secure.readAll(), {'civitai_credential_other': 'keep'});
    },
  );

  test('a blank key is refused and nothing is written', () async {
    final store = await CivitaiCredentialStore.open();
    expect(() => store.save('local', '   '), throwsArgumentError);
    expect(await secure.readAll(), isEmpty);
  });
}
