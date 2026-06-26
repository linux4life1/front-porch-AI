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

import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:hashlib/hashlib.dart';

/// Argon2id password hashing for the web secure-login.
///
/// The full PHC-format string (`$argon2id$v=19$m=...,t=...,p=...$salt$hash`) is
/// stored, so the embedded parameters are used for verification and the cost can
/// be raised later without invalidating existing hashes.
///
/// Hashing/verification run in a background isolate ([Isolate.run]) so a ~64 MB
/// Argon2 pass never janks the Flutter UI thread during login.
class PasswordHasher {
  /// Tuned for a single desktop host (OWASP-ish, second-factor optional):
  /// 64 MiB memory, 3 iterations, 4 lanes, 32-byte output.
  static const Argon2Security _security = Argon2Security(
    'fpa',
    m: 65536,
    t: 3,
    p: 4,
  );
  static const int _hashLength = 32;
  static const int _saltBytes = 16;

  /// Produce a PHC-encoded Argon2id hash for [password].
  Future<String> hash(String password) {
    final rng = Random.secure();
    final salt = List<int>.generate(_saltBytes, (_) => rng.nextInt(256));
    final pwBytes = utf8.encode(password);
    return Isolate.run(() {
      return argon2id(
        pwBytes,
        salt,
        hashLength: _hashLength,
        security: _security,
      ).encoded();
    });
  }

  /// Constant-time-ish verification of [password] against a stored PHC [encoded]
  /// hash. Returns false (never throws) on malformed input.
  Future<bool> verify(String password, String encoded) {
    final pwBytes = utf8.encode(password);
    return Isolate.run(() {
      try {
        return argon2Verify(encoded, pwBytes);
      } catch (_) {
        return false;
      }
    });
  }
}
