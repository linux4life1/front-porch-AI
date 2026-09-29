// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'civitai_oauth.dart';

/// Read, write, and delete one string.
typedef CivitaiKeyRead = Future<String?> Function(String key);
typedef CivitaiKeyWrite = Future<void> Function(String key, String value);
typedef CivitaiKeyDelete = Future<void> Function(String key);

/// Shown when the OS key store will not give the saved key back, as happens
/// with ad-hoc signed macOS builds. Search without a key still works.
const String kCivitaiKeyUnreadable =
    "Couldn't read your saved CivitAI key. Searching without a key still "
    'works; downloads and adult results need it.';

/// The OS key store could not be read or written. The caller shows
/// [message]; a silent fallback to plain storage would defeat the store.
class CivitaiKeyStoreException implements Exception {
  const CivitaiKeyStoreException(this.message);

  final String message;

  @override
  String toString() => 'CivitaiKeyStoreException: $message';
}

/// One pasted key per Front Porch account, under [civitaiCredentialKey],
/// in the OS secure store. One key covers civitai.com and civitai.red.
class CivitaiCredentialStore {
  final CivitaiKeyRead readKey;
  final CivitaiKeyWrite writeKey;
  final CivitaiKeyDelete deleteKey;

  CivitaiCredentialStore({
    required this.readKey,
    required this.writeKey,
    required this.deleteKey,
  });

  factory CivitaiCredentialStore.secure([
    FlutterSecureStorage storage = const FlutterSecureStorage(
      mOptions: MacOsOptions(usesDataProtectionKeychain: false),
    ),
  ]) {
    return CivitaiCredentialStore(
      readKey: (key) => storage.read(key: key),
      writeKey: (key, value) => storage.write(key: key, value: value),
      deleteKey: (key) => storage.delete(key: key),
    );
  }

  /// A test can hand in its own store, for example one that cannot be read.
  @visibleForTesting
  static CivitaiCredentialStore? debugStore;

  static Future<CivitaiCredentialStore> open() async {
    return debugStore ?? CivitaiCredentialStore.secure();
  }

  Future<T> _guard<T>(String action, Future<T> Function() run) async {
    try {
      return await run();
    } on ArgumentError {
      rethrow;
    } catch (e) {
      debugPrint('civitai key store $action failed: ${e.runtimeType}');
      throw CivitaiKeyStoreException(
        action == 'read'
            ? kCivitaiKeyUnreadable
            : 'Could not save the CivitAI key.',
      );
    }
  }

  Future<void> save(String accountId, String token) {
    final trimmed = token.trim();
    if (trimmed.isEmpty) throw ArgumentError('token');
    final key = civitaiCredentialKey(accountId);
    return _guard('write', () => writeKey(key, trimmed));
  }

  Future<String?> read(String accountId) {
    final key = civitaiCredentialKey(accountId);
    return _guard('read', () async {
      final value = await readKey(key);
      if (value == null || value.trim().isEmpty) return null;
      return value;
    });
  }

  /// Removes this account's key and leaves every other account in place.
  /// Also clears the second key that a pre-release build could leave behind.
  Future<void> signOut(String accountId) {
    final key = civitaiCredentialKey(accountId);
    return _guard('write', () async {
      await deleteKey(key);
      await deleteKey(civitaiRedCredentialKey(accountId));
    });
  }
}
