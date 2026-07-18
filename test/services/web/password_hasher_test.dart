// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/web/auth/password_hasher.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PasswordHasher (Argon2id)', () {
    final hasher = PasswordHasher();

    test('produces a PHC-format argon2id hash', () async {
      final encoded = await hasher.hash('correct horse battery staple');
      expect(encoded, startsWith(r'$argon2id$'));
    });

    test('verifies the correct password and rejects the wrong one', () async {
      final encoded = await hasher.hash('s3cret-passphrase');
      expect(await hasher.verify('s3cret-passphrase', encoded), isTrue);
      expect(await hasher.verify('wrong-passphrase', encoded), isFalse);
    });

    test('different calls produce different hashes (random salt)', () async {
      final a = await hasher.hash('same-input');
      final b = await hasher.hash('same-input');
      expect(a, isNot(equals(b)));
      expect(await hasher.verify('same-input', a), isTrue);
      expect(await hasher.verify('same-input', b), isTrue);
    });

    test('verify never throws on malformed encoded input', () async {
      expect(await hasher.verify('pw', 'not-a-valid-hash'), isFalse);
    });
  });
}
