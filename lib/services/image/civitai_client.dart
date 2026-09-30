// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/image/civitai_credentials.dart';
import 'package:front_porch_ai/services/image/civitai_download.dart';
import 'package:front_porch_ai/services/image/civitai_errors.dart';
import 'package:front_porch_ai/services/image/civitai_files.dart';
import 'package:front_porch_ai/services/image/civitai_version.dart';

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

/// Lets plain http to this computer through, so a test can run a real file
/// host on loopback. Only tests turn this on; the shipped app never does, and
/// every CivitAI address it builds is https.
@visibleForTesting
bool civitaiAllowLoopbackForTests = false;

bool _isLoopback(String host) {
  if (!civitaiAllowLoopbackForTests) return false;
  return host == 'localhost' || host == '127.0.0.1' || host == '::1';
}

/// A download, and every redirect on the way, may only use https.
bool civitaiHopAllowed(Uri to) => to.scheme == 'https' || _isLoopback(to.host);

/// The bearer goes only to the origin the download started at. [from] is
/// that original URL, never the previous hop, so a chain that passes through
/// a CDN cannot pick the key back up on a later hop.
Map<String, String> civitaiFollowHeaders({
  required Uri from,
  required Uri to,
  required String? authorization,
}) {
  if (authorization == null || authorization.isEmpty) return const {};
  if (!civitaiHopAllowed(to)) return const {};
  if (from.scheme != to.scheme ||
      from.host != to.host ||
      from.port != to.port) {
    return const {};
  }
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

/// The one host a listing's pictures may load from on the phone.
const String kCivitaiImageHost = 'image.civitai.com';

/// [url] when it is an https picture on [kCivitaiImageHost], else null.
String? civitaiPhoneImage(String? url) {
  final uri = url == null ? null : Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https') return null;
  return uri.host == kCivitaiImageHost ? url : null;
}

/// True when a listing's picture is rated X or above. A model that is fine to
/// list can still carry one, and it is not shown unless adult results are on.
bool civitaiImageIsAdult(Map image) {
  final level = image['nsfwLevel'];
  if (level is num && (level.toInt() & kCivitaiImageAdultMask) != 0) {
    return true;
  }
  final legacy = image['nsfw'];
  if (legacy is bool) return legacy;
  return legacy is String && {'mature', 'x'}.contains(legacy.toLowerCase());
}

List<String> _civitaiImages(Map? version, {required bool includeAdult}) {
  final images = version?['images'];
  if (images is! List) return const [];
  final out = <String>[];
  for (final image in images) {
    if (image is! Map) continue;
    if (!includeAdult && civitaiImageIsAdult(image)) continue;
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
  final images = _civitaiImages(version, includeAdult: includeAdult);
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
  final CivitaiFailure? failure;

  /// The models folder [path] must stay inside once links are resolved.
  final String? root;

  /// What CivitAI lists for the file. Both are checked before the file is
  /// moved into place.
  final int? expectedBytes;
  final String? sha256;

  /// Where a checkpoint that carries its own encoders and VAE belongs. The
  /// name alone cannot tell, so the downloaded header decides.
  final String? allInOnePath;

  /// CivitAI's base model for the version, for tagging a saved LoRA.
  final String baseModel;

  /// The models folders the person saved, each as it resolved when they saved
  /// it. A folder the backend's config names for one kind of file is only
  /// written to inside [root] or one of these.
  final List<String> trustedRoots;

  const CivitaiDownloadPlan({
    required this.uri,
    required this.path,
    required this.authorization,
    required this.log,
    required this.refused,
    this.reason = '',
    this.failure,
    this.root,
    this.expectedBytes,
    this.sha256,
    this.allInOnePath,
    this.baseModel = '',
    this.trustedRoots = const [],
  });

  factory CivitaiDownloadPlan.refusal(
    CivitaiFailure failure, {
    required String log,
    String detail = '',
  }) {
    return CivitaiDownloadPlan(
      uri: null,
      path: null,
      authorization: null,
      log: log,
      refused: true,
      reason: CivitaiDownloadException(failure, detail).message,
      failure: failure,
    );
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
    // Only adult search sends the key, so a key store that cannot be read
    // must not stop an ordinary search.
    final token = adult ? await store.read(accountId) : null;
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

  /// [version] comes from CivitAI, not from the caller. The file name has
  /// to be one of its files; its type, size, checksum and address all come
  /// from that listing. A version rated adult is refused unless
  /// [adultAllowed], whichever host [adult] points at.
  Future<CivitaiDownloadPlan> planDownload({
    required String accountId,
    required CivitaiVersion version,
    required String filename,
    required bool adult,
    required bool adultAllowed,
    required String? savedRoot,
    required bool fromLoraSheet,
    required String backend,
    Map<String, String> typeFolders = const {},
    List<String> trustedRoots = const [],
  }) async {
    final log = civitaiLog(
      action: 'download',
      accountId: accountId,
      adult: adult,
    );
    CivitaiDownloadPlan refuse(CivitaiFailure kind, [String detail = '']) {
      return CivitaiDownloadPlan.refusal(kind, log: log, detail: detail);
    }

    if (version.isAdultRated && !adultAllowed) {
      return refuse(CivitaiFailure.adultBlocked);
    }
    final token = await store.read(accountId);
    if (token == null) return refuse(CivitaiFailure.keyMissing);
    final file = civitaiVersionFile(version, filename);
    if (file == null) {
      return refuse(
        CivitaiFailure.unsafe,
        'CivitAI does not list that file for this model.',
      );
    }
    if (!file.isSafeWeight) {
      return refuse(
        CivitaiFailure.unsafe,
        'Only .safetensors and .gguf files are saved. That file is not one '
        'of those, or CivitAI flagged it.',
      );
    }
    final uri = civitaiFileDownloadUri(
      file,
      versionId: version.id,
      adult: adult,
    );
    if (uri == null) {
      return refuse(
        CivitaiFailure.unsafe,
        'CivitAI gave no download address for that file.',
      );
    }
    final folder = civitaiSlotFolder(
      fromLoraSheet: fromLoraSheet,
      civitaiType: version.modelType,
      filename: file.name,
      backend: backend,
    );
    if (folder == null) {
      return refuse(
        CivitaiFailure.unsafe,
        fromLoraSheet
            ? 'That file is not a LoRA this app can save.'
            : 'That file is not a model this app can save.',
      );
    }
    final root = savedRoot?.trim() ?? '';
    final path = root.isEmpty
        ? null
        : civitaiDownloadPath(
            root: root,
            folder: folder,
            name: file.name,
            typeFolders: typeFolders,
          );
    if (path == null) return refuse(CivitaiFailure.unsafe);
    return CivitaiDownloadPlan(
      uri: uri,
      path: path,
      authorization: civitaiBearer(token),
      log: log,
      refused: false,
      root: root,
      expectedBytes: file.sizeBytes,
      sha256: file.sha256,
      baseModel: version.baseModel,
      trustedRoots: trustedRoots,
      allInOnePath: civitaiAllInOnePath(
        root: root,
        backend: backend,
        folder: folder,
        modelType: version.modelType,
        name: file.name,
        typeFolders: typeFolders,
      ),
    );
  }
}
