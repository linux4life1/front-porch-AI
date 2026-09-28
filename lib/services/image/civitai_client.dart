// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/image/civitai_download.dart';
import 'package:front_porch_ai/services/image/civitai_oauth.dart';

/// A pasted personal API key. A password field is refused.
String? pastedCivitaiToken(Map<String, Object?> body) {
  if (body.containsKey('password')) return null;
  final token = body['token'];
  if (token is! String) return null;
  final trimmed = token.trim();
  if (trimmed.isEmpty) return null;
  return trimmed;
}

/// The phone relay uses the cookie account. Callers must not pass a body id.
String? civitaiRelayAccount(String? cookieAccount) {
  final cookie = cookieAccount?.trim() ?? '';
  if (cookie.isEmpty) return null;
  return cookie;
}

/// PG search is anonymous on civitai.com. Adult search needs a credential
/// and uses civitai.red. The key is never placed in the query.
Uri? civitaiModelsUri({
  required String query,
  required bool adult,
  required bool hasCredential,
  required bool lora,
}) {
  if (adult && !hasCredential) return null;
  return Uri.https(adult ? 'civitai.red' : 'civitai.com', '/api/v1/models', {
    'query': query,
    'limit': '20',
    'types': lora ? 'LORA' : 'Checkpoint',
    if (adult) 'nsfw': 'true',
    if (adult) 'browsingLevel': '31',
  });
}

/// File download. Any file 401s without a bearer, including a public one.
Uri civitaiDownloadUri(int versionId, {bool adult = false}) {
  final host = adult ? 'civitai.red' : 'civitai.com';
  return Uri.https(host, '/api/download/models/$versionId');
}

String civitaiBearer(String token) => 'Bearer $token';

/// Keep the bearer on the same host. Drop it when the file moves elsewhere.
Map<String, String> civitaiFollowHeaders({
  required Uri from,
  required Uri to,
  required String? authorization,
}) {
  if (authorization == null || authorization.isEmpty) return const {};
  if (from.host != to.host) return const {};
  return {'Authorization': authorization};
}

/// Log text for one relay action. The key is not included.
String civitaiLog({
  required String action,
  required String accountId,
  bool adult = false,
}) {
  return 'civitai $action account=$accountId adult=$adult';
}

enum CivitaiHttpKind { ok, needsCredential, locked, failed }

/// 401 asks for a key. 403 is a locked file and is not retried.
CivitaiHttpKind civitaiHttpKind(int status) {
  if (status == 200) return CivitaiHttpKind.ok;
  if (status == 401) return CivitaiHttpKind.needsCredential;
  if (status == 403) return CivitaiHttpKind.locked;
  return CivitaiHttpKind.failed;
}

class CivitaiModelRow {
  final int id;
  final String name;
  final String type;
  final bool adult;
  final int? versionId;
  final String? filename;

  const CivitaiModelRow({
    required this.id,
    required this.name,
    required this.type,
    required this.adult,
    this.versionId,
    this.filename,
  });
}

/// Rows from a models JSON body. Adult rows are omitted unless asked for.
List<CivitaiModelRow> parseCivitaiModels(
  String body, {
  required bool includeAdult,
}) {
  Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    return const [];
  }
  if (decoded is! Map) return const [];
  final items = decoded['items'];
  if (items is! List) return const [];
  final out = <CivitaiModelRow>[];
  for (final item in items) {
    if (item is! Map) continue;
    final adult = item['nsfw'] == true;
    if (adult && !includeAdult) continue;
    final versions = item['modelVersions'];
    Map? version;
    if (versions is List && versions.isNotEmpty && versions.first is Map) {
      version = versions.first as Map;
    }
    String? filename;
    final files = version?['files'];
    if (files is List && files.isNotEmpty && files.first is Map) {
      final name = (files.first as Map)['name'];
      if (name is String && name.trim().isNotEmpty) filename = name.trim();
    }
    final id = item['id'];
    if (id is! num) continue;
    final versionId = version?['id'];
    out.add(
      CivitaiModelRow(
        id: id.toInt(),
        name: item['name']?.toString() ?? '',
        type: item['type']?.toString() ?? '',
        adult: adult,
        versionId: versionId is num ? versionId.toInt() : null,
        filename: filename,
      ),
    );
  }
  return out;
}

class CivitaiSearchPlan {
  final Uri? uri;
  final String? authorization;
  final String log;
  final bool needsCredential;

  const CivitaiSearchPlan({
    required this.uri,
    required this.authorization,
    required this.log,
    required this.needsCredential,
  });
}

class CivitaiDownloadPlan {
  final Uri? uri;
  final String? path;
  final String? authorization;
  final String log;
  final bool refused;

  const CivitaiDownloadPlan({
    required this.uri,
    required this.path,
    required this.authorization,
    required this.log,
    required this.refused,
  });
}

/// Read, write, and delete one string. Production uses SharedPreferences.
typedef CivitaiKeyRead = Future<String?> Function(String key);
typedef CivitaiKeyWrite = Future<void> Function(String key, String value);
typedef CivitaiKeyDelete = Future<void> Function(String key);

/// One pasted key per Front Porch account, under [civitaiCredentialKey].
///
/// SharedPreferences is the same durable store as the other API keys. The
/// macOS keychain comes back empty on ad-hoc launches. The name has no
/// `beta_` prefix. The value is not part of the image-gen settings blob.
class CivitaiCredentialStore {
  final CivitaiKeyRead readKey;
  final CivitaiKeyWrite writeKey;
  final CivitaiKeyDelete deleteKey;

  CivitaiCredentialStore({
    required this.readKey,
    required this.writeKey,
    required this.deleteKey,
  });

  factory CivitaiCredentialStore.prefs(SharedPreferences prefs) {
    return CivitaiCredentialStore(
      readKey: (key) async => prefs.getString(key),
      writeKey: (key, value) async {
        await prefs.setString(key, value);
      },
      deleteKey: (key) async {
        await prefs.remove(key);
      },
    );
  }

  static Future<CivitaiCredentialStore> open() async {
    return CivitaiCredentialStore.prefs(await SharedPreferences.getInstance());
  }

  Future<void> save(String accountId, String token) {
    final trimmed = token.trim();
    if (trimmed.isEmpty) throw ArgumentError('token');
    return writeKey(civitaiCredentialKey(accountId), trimmed);
  }

  Future<String?> read(String accountId) async {
    final value = await readKey(civitaiCredentialKey(accountId));
    if (value == null || value.trim().isEmpty) return null;
    return value;
  }

  /// Removes this account's key and leaves every other account in place.
  Future<void> signOut(String accountId) {
    return deleteKey(civitaiCredentialKey(accountId));
  }
}

class CivitaiRelay {
  final CivitaiCredentialStore store;

  CivitaiRelay(this.store);

  Future<CivitaiSearchPlan> planSearch({
    required String accountId,
    required String query,
    required bool adult,
    required bool lora,
  }) async {
    final token = await store.read(accountId);
    final has = token != null;
    return CivitaiSearchPlan(
      uri: civitaiModelsUri(
        query: query,
        adult: adult,
        hasCredential: has,
        lora: lora,
      ),
      authorization: has && adult ? civitaiBearer(token) : null,
      log: civitaiLog(action: 'search', accountId: accountId, adult: adult),
      needsCredential: adult && !has,
    );
  }

  Future<CivitaiDownloadPlan> planDownload({
    required String accountId,
    required int versionId,
    required bool adult,
    required String? savedRoot,
    required String filename,
    required String civitaiType,
    required bool fromLoraSheet,
    required String backend,
  }) async {
    final token = await store.read(accountId);
    final folder = civitaiSlotFolder(
      fromLoraSheet: fromLoraSheet,
      civitaiType: civitaiType,
      filename: filename,
      backend: backend,
    );
    final root = savedRoot?.trim() ?? '';
    final path = folder == null || root.isEmpty
        ? null
        : civitaiDownloadPath(root: root, folder: folder, name: filename);
    final log = civitaiLog(
      action: 'download',
      accountId: accountId,
      adult: adult,
    );
    if (token == null || path == null) {
      return CivitaiDownloadPlan(
        uri: null,
        path: null,
        authorization: null,
        log: log,
        refused: true,
      );
    }
    return CivitaiDownloadPlan(
      uri: civitaiDownloadUri(versionId, adult: adult),
      path: path,
      authorization: civitaiBearer(token),
      log: log,
      refused: false,
    );
  }
}
