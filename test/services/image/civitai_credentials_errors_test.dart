// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/image/image.dart';

void main() {
  CivitaiCredentialStore broken(Object error) => CivitaiCredentialStore(
    readKey: (_) async => throw error,
    writeKey: (_, _) async => throw error,
    deleteKey: (_) async => throw error,
  );

  test('a key store that cannot be read is an error, never "no key"', () async {
    final store = broken(PlatformException(code: 'locked'));
    await expectLater(
      store.read('local'),
      throwsA(
        isA<CivitaiKeyStoreException>().having(
          (e) => e.message,
          'message',
          kCivitaiKeyUnreadable,
        ),
      ),
    );
  });

  test(
    'a key store that cannot be written says so, and not the secret',
    () async {
      final store = broken(StateError('keychain says secret-token is locked'));
      await expectLater(
        store.save('local', 'secret-token'),
        throwsA(
          isA<CivitaiKeyStoreException>().having(
            (e) => e.message,
            'message',
            allOf('Could not save the CivitAI key.', isNot(contains('secret'))),
          ),
        ),
      );
    },
  );

  test('a sign-out that cannot reach the store is an error too', () async {
    await expectLater(
      broken(StateError('x')).signOut('local'),
      throwsA(isA<CivitaiKeyStoreException>()),
    );
  });

  test('a bad account id is still an argument error, not a store error', () {
    final store = broken(StateError('x'));
    expect(() => store.read('../x'), throwsArgumentError);
    expect(() => store.save('local', ' '), throwsArgumentError);
  });
}
