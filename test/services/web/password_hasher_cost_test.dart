// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Tests of the login flow hash at a cheap Argon2 cost (PasswordHasher's
// `security`). The web login the app builds (`AuthService(db)`, as the web
// server host does) must still hash at the app's cost: 64 MiB, 3 passes,
// 4 lanes.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/web/auth/auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the web login the app builds hashes at the full Argon2 cost', () async {
    final db = AppDatabase.forTesting();
    addTearDown(db.close);

    final auth = AuthService(db);
    await auth.setupAccount(
      'admin',
      'password123',
      isDirectLoopbackClient: true,
    );

    final row = await db
        .customSelect(
          "SELECT password_hash FROM web_auth_credentials WHERE id = 'local'",
        )
        .getSingle();
    expect(row.data['password_hash'] as String, contains(r'$m=65536,t=3,p=4$'));
  });
}
