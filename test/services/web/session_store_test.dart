// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/web/auth/session_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SessionStore', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase.forTesting());
    tearDown(() => db.close());

    test('create returns a raw token that validates to the user id', () async {
      final store = SessionStore(db);
      final token = await store.create('local', userAgent: 'UA', ip: '1.1.1.1');
      expect(token, isNotEmpty);
      expect(await store.validate(token), 'local');
    });

    test('an unknown token does not validate', () async {
      final store = SessionStore(db);
      expect(await store.validate('nope'), isNull);
    });

    test('revoke invalidates the session', () async {
      final store = SessionStore(db);
      final token = await store.create('local');
      await store.revoke(token);
      expect(await store.validate(token), isNull);
    });

    test('revokeOthers keeps only the given session alive', () async {
      final store = SessionStore(db);
      final phone = await store.create('local', userAgent: 'phone');
      final laptop = await store.create('local', userAgent: 'laptop');
      final current = await store.create('local', userAgent: 'desktop');
      await store.revokeOthers('local', current);
      expect(await store.validate(current), 'local');
      expect(await store.validate(phone), isNull);
      expect(await store.validate(laptop), isNull);
    });

    test('an expired session is rejected and pruned', () async {
      var now = 1700000000000;
      final issuer = SessionStore(db, nowMs: () => now);
      final token = await issuer.create('local');
      // Fast-forward beyond the absolute TTL.
      now += SessionStore.sessionTtl.inMilliseconds + 1000;
      expect(await issuer.validate(token), isNull);
    });

    test('listActive reflects live sessions and revokeAll clears them',
        () async {
      final store = SessionStore(db);
      await store.create('local', userAgent: 'A');
      await store.create('local', userAgent: 'B');
      expect((await store.listActive('local')).length, 2);
      await store.revokeAllFor('local');
      expect((await store.listActive('local')), isEmpty);
    });
  });
}
