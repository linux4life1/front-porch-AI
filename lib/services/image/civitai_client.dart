// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/image/civitai_download.dart';
import 'package:front_porch_ai/services/image/civitai_files.dart';
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

/// PG search is anonymous on civitai.com. Adult search uses the same key
/// against civitai.red with `nsfw=true`. `browsingLevel` is omitted because
/// CivitAI rejects that query value. The key is never placed in the query.

Uri? civitaiModelsUri({
  required String query,
  required bool adult,
  required bool hasCredential,
  required bool lora,
  String baseModel = '',
}) {
  if (adult && !hasCredential) return null;
  return Uri.https(adult ? 'civitai.red' : 'civitai.com', '/api/v1/models', {
    'query': query,
    'limit': '20',
    'types': lora ? 'LORA' : 'Checkpoint',
    if (baseModel.trim().isNotEmpty) 'baseModels': baseModel.trim(),
    if (adult) 'nsfw': 'true',
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

/// What to show after a CivitAI search. Empty means the rows are the result.
String civitaiSearchNote({
  required CivitaiHttpKind kind,
  required bool hadKey,
  required int rows,
}) {
  switch (kind) {
    case CivitaiHttpKind.needsCredential:
      return hadKey
          ? 'That API key was refused. Paste a valid key and search again.'
          : 'Paste an API key to search adult models.';
    case CivitaiHttpKind.locked:
      return 'CivitAI refused this search.';
    case CivitaiHttpKind.failed:
      return 'CivitAI search failed.';
    case CivitaiHttpKind.ok:
      return rows == 0 ? 'CivitAI returned no models for that search.' : '';
  }
}

class CivitaiModelRow {
  final int id;
  final String name;
  final String type;
  final bool adult;
  final int? versionId;
  final String? filename;
  final String? previewUrl;
  final List<String> imageUrls;
  final String description;
  final int downloads;

  const CivitaiModelRow({
    required this.id,
    required this.name,
    required this.type,
    required this.adult,
    this.versionId,
    this.filename,
    this.previewUrl,
    this.imageUrls = const [],
    this.description = '',
    this.downloads = 0,
  });
}

/// One model object from search or from `/api/v1/models/{id}`.
CivitaiModelRow? parseCivitaiModel(String body, {required bool includeAdult}) {
  Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    return null;
  }
  if (decoded is! Map) return null;
  return _civitaiRow(decoded, includeAdult: includeAdult);
}

/// Turns CivitAI's HTML write-up into plain text.
String civitaiPlainText(String raw) {
  return raw
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll(RegExp(r'[ \t]+\n'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

Uri civitaiModelUri(int id, {required bool adult}) {
  return Uri.https(adult ? 'civitai.red' : 'civitai.com', '/api/v1/models/$id');
}

List<String> _civitaiImages(Map? version) {
  final images = version?['images'];
  if (images is! List) return const [];
  final out = <String>[];
  for (final image in images) {
    if (image is! Map) continue;
    final url = image['url'];
    if (url is! String || !url.startsWith('https://')) continue;
    if (out.contains(url)) continue;
    out.add(url);
  }
  return out;
}

String _civitaiDescription(Map item, Map? version) {
  final model = item['description']?.toString() ?? '';
  final plain = civitaiPlainText(model);
  if (plain.isNotEmpty) return plain;
  return civitaiPlainText(version?['description']?.toString() ?? '');
}

int _civitaiDownloads(Map item, Map? version) {
  int read(Object? stats) {
    if (stats is! Map) return 0;
    final count = stats['downloadCount'];
    return count is num ? count.toInt() : 0;
  }

  final fromVersion = read(version?['stats']);
  if (fromVersion > 0) return fromVersion;
  return read(item['stats']);
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
    final row = _civitaiRow(item, includeAdult: includeAdult);
    if (row != null) out.add(row);
  }
  return out;
}

CivitaiModelRow? _civitaiRow(Map item, {required bool includeAdult}) {
  final adult = item['nsfw'] == true;
  if (adult && !includeAdult) return null;
  final versions = item['modelVersions'];
  Map? version;
  if (versions is List && versions.isNotEmpty && versions.first is Map) {
    version = versions.first as Map;
  }
  final filename = civitaiPickFilename(version?['files']);
  final id = item['id'];
  if (id is! num) return null;
  final versionId = version?['id'];
  final images = _civitaiImages(version);
  return CivitaiModelRow(
    id: id.toInt(),
    name: item['name']?.toString() ?? '',
    type: item['type']?.toString() ?? '',
    adult: adult,
    versionId: versionId is num ? versionId.toInt() : null,
    filename: filename,
    previewUrl: images.isEmpty ? null : images.first,
    imageUrls: images,
    description: _civitaiDescription(item, version),
    downloads: _civitaiDownloads(item, version),
  );
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
  final String reason;

  const CivitaiDownloadPlan({
    required this.uri,
    required this.path,
    required this.authorization,
    required this.log,
    required this.refused,
    this.reason = '',
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

  Future<void> saveRed(String accountId, String token) {
    final trimmed = token.trim();
    if (trimmed.isEmpty) throw ArgumentError('token');
    return writeKey(civitaiRedCredentialKey(accountId), trimmed);
  }

  Future<String?> read(String accountId) async {
    final value = await readKey(civitaiCredentialKey(accountId));
    if (value == null || value.trim().isEmpty) return null;
    return value;
  }

  Future<String?> readRed(String accountId) async {
    final value = await readKey(civitaiRedCredentialKey(accountId));
    if (value == null || value.trim().isEmpty) return null;
    return value;
  }

  /// One key covers civitai.com and civitai.red. [adult] does not pick a
  /// second secret.
  Future<String?> readFor({
    required String accountId,
    required bool adult,
  }) async {
    final token = await read(accountId);
    if (token == null && adult) return null;
    return token;
  }

  /// Removes this account's key and leaves every other account in place.
  Future<void> signOut(String accountId) {
    return deleteKey(civitaiCredentialKey(accountId));
  }

  /// Removes this account's civitai.red key only.
  Future<void> clearRed(String accountId) {
    return deleteKey(civitaiRedCredentialKey(accountId));
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
    String baseModel = '',
  }) async {
    final token = await store.readFor(accountId: accountId, adult: adult);
    final has = token != null;
    return CivitaiSearchPlan(
      uri: civitaiModelsUri(
        query: query,
        adult: adult,
        hasCredential: has,
        lora: lora,
        baseModel: baseModel,
      ),
      authorization: token != null && adult ? civitaiBearer(token) : null,
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
    final token = await store.readFor(accountId: accountId, adult: adult);
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
      final reason = token == null
          ? 'Paste an API key. CivitAI will not send the file without one.'
          : folder == null
          ? (fromLoraSheet
                ? 'That file is not a LoRA this app can save.'
                : 'That file is not a model this app can save.')
          : "That file name can't be saved.";
      return CivitaiDownloadPlan(
        uri: null,
        path: null,
        authorization: null,
        log: log,
        refused: true,
        reason: reason,
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
