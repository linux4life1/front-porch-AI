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
import 'dart:math';

import 'package:drift/drift.dart' show Variable;
import 'package:hashlib/hashlib.dart' as hashlib;
import 'package:uuid/uuid.dart';

import 'package:front_porch_ai/database/database.dart';

/// One signed-in web device.
class WebSessionInfo {
  WebSessionInfo({
    required this.id,
    required this.createdAt,
    required this.lastSeenAt,
    required this.expiresAt,
    this.userAgent,
    this.ip,
  });

  final String id;
  final int createdAt;
  final int lastSeenAt;
  final int expiresAt;
  final String? userAgent;
  final String? ip;

  Map<String, Object?> toJson() => {
        'id': id,
        'createdAt': createdAt,
        'lastSeenAt': lastSeenAt,
        'expiresAt': expiresAt,
        'userAgent': userAgent,
        'ip': ip,
      };
}

/// Persisted web-login sessions backed by the `web_auth_sessions` table.
///
/// The raw cookie token never touches the database — only its SHA-256 — so a DB
/// leak cannot be replayed as a live session. Uses raw SQL (the dominant style
/// for service-level DB access in this codebase, e.g. db_reunification_service).
class SessionStore {
  SessionStore(this._db, {int Function()? nowMs})
      : _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final AppDatabase _db;
  final int Function() _nowMs;
  static const _uuid = Uuid();

  /// Absolute session lifetime. Long enough for a phone PWA to stay signed in.
  static const Duration sessionTtl = Duration(days: 30);

  /// Create a session for [userId] and return the RAW token to put in the
  /// cookie (only the hash is stored).
  Future<String> create(
    String userId, {
    String? userAgent,
    String? ip,
  }) async {
    final rawToken = _generateToken();
    final now = _nowMs();
    await _db.customInsert(
      'INSERT INTO web_auth_sessions '
      '(id, token_hash, user_id, created_at, last_seen_at, expires_at, user_agent, ip, revoked) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0)',
      variables: [
        Variable<String>(_uuid.v4()),
        Variable<String>(_hashToken(rawToken)),
        Variable<String>(userId),
        Variable<int>(now),
        Variable<int>(now),
        Variable<int>(now + sessionTtl.inMilliseconds),
        Variable<String>(userAgent),
        Variable<String>(ip),
      ],
    );
    return rawToken;
  }

  /// Return the userId for a valid [rawToken], bumping last-seen; null if the
  /// session is unknown, revoked, or expired (expired rows are pruned).
  Future<String?> validate(String rawToken) async {
    if (rawToken.isEmpty) return null;
    final hash = _hashToken(rawToken);
    final now = _nowMs();
    final rows = await _db.customSelect(
      'SELECT user_id, expires_at, revoked FROM web_auth_sessions WHERE token_hash = ? LIMIT 1',
      variables: [Variable<String>(hash)],
    ).get();
    if (rows.isEmpty) return null;
    final row = rows.first.data;
    if ((row['revoked'] as int? ?? 0) != 0) return null;
    if ((row['expires_at'] as int? ?? 0) <= now) {
      await _db.customStatement(
        'DELETE FROM web_auth_sessions WHERE token_hash = ?',
        [hash],
      );
      return null;
    }
    await _db.customStatement(
      'UPDATE web_auth_sessions SET last_seen_at = ? WHERE token_hash = ?',
      [now, hash],
    );
    return row['user_id'] as String?;
  }

  /// Revoke a single session by its raw cookie token.
  Future<void> revoke(String rawToken) async {
    if (rawToken.isEmpty) return;
    await _db.customStatement(
      'UPDATE web_auth_sessions SET revoked = 1 WHERE token_hash = ?',
      [_hashToken(rawToken)],
    );
  }

  /// Revoke a single session by its internal row id (for "this device" UIs).
  Future<void> revokeById(String sessionId) async {
    await _db.customStatement(
      'UPDATE web_auth_sessions SET revoked = 1 WHERE id = ?',
      [sessionId],
    );
  }

  /// Log out everywhere for [userId].
  Future<void> revokeAllFor(String userId) async {
    await _db.customStatement(
      'UPDATE web_auth_sessions SET revoked = 1 WHERE user_id = ?',
      [userId],
    );
  }

  /// Delete expired or revoked rows. Cheap; safe to call periodically/at start.
  Future<void> sweep() async {
    await _db.customStatement(
      'DELETE FROM web_auth_sessions WHERE revoked = 1 OR expires_at <= ?',
      [_nowMs()],
    );
  }

  /// Active (non-revoked, non-expired) sessions for [userId].
  Future<List<WebSessionInfo>> listActive(String userId) async {
    final rows = await _db.customSelect(
      'SELECT id, created_at, last_seen_at, expires_at, user_agent, ip '
      'FROM web_auth_sessions WHERE user_id = ? AND revoked = 0 AND expires_at > ? '
      'ORDER BY last_seen_at DESC',
      variables: [Variable<String>(userId), Variable<int>(_nowMs())],
    ).get();
    return rows
        .map((r) => WebSessionInfo(
              id: r.data['id'] as String,
              createdAt: r.data['created_at'] as int? ?? 0,
              lastSeenAt: r.data['last_seen_at'] as int? ?? 0,
              expiresAt: r.data['expires_at'] as int? ?? 0,
              userAgent: r.data['user_agent'] as String?,
              ip: r.data['ip'] as String?,
            ))
        .toList();
  }

  String _generateToken() {
    final rng = Random.secure();
    final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  String _hashToken(String rawToken) =>
      hashlib.sha256.convert(utf8.encode(rawToken)).hex();
}
