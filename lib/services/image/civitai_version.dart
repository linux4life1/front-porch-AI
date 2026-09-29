// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:http/http.dart' as http;

/// Only these are saved. Pickle formats (`.ckpt`, `.pt`, `.pth`, `.bin`) can
/// run code when a loader opens them, so they are refused.
const Set<String> kCivitaiSafeExtensions = {'.safetensors', '.gguf'};

/// One file of a model version, as CivitAI lists it.
class CivitaiVersionFile {
  const CivitaiVersionFile({
    required this.name,
    required this.type,
    required this.primary,
    this.format = '',
    this.sizeBytes,
    this.sha256,
    this.downloadUri,
    this.flaggedDangerous = false,
  });

  final String name;

  /// CivitAI's file type: `Model`, `Pruned Model`, `VAE`, `Config`...
  final String type;
  final bool primary;

  /// `SafeTensor`, `PickleTensor`, `GGUF`, `Other`.
  final String format;
  final int? sizeBytes;

  /// Lowercase hex, when CivitAI lists one.
  final String? sha256;
  final Uri? downloadUri;

  /// CivitAI's own scanners marked this file dangerous.
  final bool flaggedDangerous;

  /// A weight this app is willing to save.
  bool get isSafeWeight {
    if (flaggedDangerous) return false;
    if (format.toLowerCase().contains('pickle')) return false;
    final lower = name.toLowerCase();
    return kCivitaiSafeExtensions.any(lower.endsWith);
  }
}

/// CivitAI's `nsfwLevel` is a bit set: 1 PG, 2 PG-13, 4 R, 8 X, 16 XXX. Any
/// value from 4 up means the version has content rated R or stronger, which
/// the model's own `nsfw` flag does not always say.
const int kCivitaiAdultLevel = 4;

/// One model version from `/api/v1/model-versions/{id}`.
class CivitaiVersion {
  const CivitaiVersion({
    required this.id,
    required this.modelType,
    required this.files,
    this.adult = false,
    this.nsfwLevel = 0,
  });

  final int id;

  /// `Checkpoint`, `LORA`, `TextualInversion`... The phone never supplies it.
  final String modelType;
  final bool adult;
  final int nsfwLevel;
  final List<CivitaiVersionFile> files;

  /// Rated adult by the model's flag or by the version's level.
  bool get isAdultRated => adult || nsfwLevel >= kCivitaiAdultLevel;
}

Uri civitaiVersionUri(int versionId, {required bool adult}) {
  return Uri.https(
    adult ? 'civitai.red' : 'civitai.com',
    '/api/v1/model-versions/$versionId',
  );
}

CivitaiVersion? parseCivitaiVersion(String body) {
  Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    return null;
  }
  if (decoded is! Map) return null;
  final id = decoded['id'];
  final model = decoded['model'];
  final files = decoded['files'];
  if (id is! num || model is! Map || files is! List) return null;
  final out = <CivitaiVersionFile>[];
  for (final item in files) {
    if (item is! Map) continue;
    final name = item['name']?.toString() ?? '';
    if (name.isEmpty) continue;
    out.add(_parseFile(item, name));
  }
  return CivitaiVersion(
    id: id.toInt(),
    modelType: model['type']?.toString() ?? '',
    adult: model['nsfw'] == true,
    nsfwLevel: decoded['nsfwLevel'] is num
        ? (decoded['nsfwLevel'] as num).toInt()
        : 0,
    files: out,
  );
}

CivitaiVersionFile _parseFile(Map item, String name) {
  final meta = item['metadata'];
  final hashes = item['hashes'];
  final kb = item['sizeKB'];
  final sha = hashes is Map ? hashes['SHA256']?.toString().trim() : null;
  final url = item['downloadUrl']?.toString();
  return CivitaiVersionFile(
    name: name,
    type: item['type']?.toString() ?? '',
    primary: item['primary'] == true,
    format: meta is Map ? (meta['format']?.toString() ?? '') : '',
    sizeBytes: kb is num ? (kb * 1024).round() : null,
    sha256: sha == null || sha.isEmpty ? null : sha.toLowerCase(),
    downloadUri: url == null ? null : Uri.tryParse(url),
    flaggedDangerous:
        item['pickleScanResult'] == 'Danger' ||
        item['virusScanResult'] == 'Danger',
  );
}

/// The file CivitAI lists under exactly [name], or null. A name the phone
/// made up is not a file of this version.
CivitaiVersionFile? civitaiVersionFile(CivitaiVersion version, String name) {
  for (final file in version.files) {
    if (file.name == name) return file;
  }
  return null;
}

/// The file to save when the caller names none: a safe weight, the primary
/// one first, then a full model over a pruned one or an extra, then the
/// larger. Null when the version has no safe file.
CivitaiVersionFile? civitaiPickVersionFile(CivitaiVersion version) {
  CivitaiVersionFile? best;
  var bestScore = -1;
  for (final file in version.files) {
    if (!file.isSafeWeight) continue;
    var score = 0;
    if (file.primary) score += 8;
    final type = file.type.toLowerCase();
    if (type == 'model' || type == 'pruned model') score += 4;
    final size = file.sizeBytes ?? 0;
    final bestSize = best?.sizeBytes ?? 0;
    if (score > bestScore || (score == bestScore && size > bestSize)) {
      best = file;
      bestScore = score;
    }
  }
  return best;
}

/// Where to fetch [file]: its own download URL when that stays on the
/// expected CivitAI host and names this version, else the version's default
/// download when [file] is the primary one, else null.
Uri? civitaiFileDownloadUri(
  CivitaiVersionFile file, {
  required int versionId,
  required bool adult,
}) {
  final host = adult ? 'civitai.red' : 'civitai.com';
  final own = file.downloadUri;
  if (own != null &&
      own.scheme == 'https' &&
      own.host == host &&
      !own.hasPort &&
      own.userInfo.isEmpty &&
      own.path == '/api/download/models/$versionId') {
    return own;
  }
  return file.primary
      ? Uri.https(host, '/api/download/models/$versionId')
      : null;
}

enum CivitaiLookupKind { ok, needsCredential, locked, notFound, failed }

class CivitaiVersionLookup {
  const CivitaiVersionLookup(this.kind, [this.version]);

  final CivitaiLookupKind kind;
  final CivitaiVersion? version;
}

typedef CivitaiVersionFetch =
    Future<CivitaiVersionLookup> Function({
      required int versionId,
      required bool adult,
      String? authorization,
    });

/// Asks CivitAI what [versionId] contains. The bearer goes to the host this
/// URL is built for and nowhere else.
Future<CivitaiVersionLookup> fetchCivitaiVersion({
  required int versionId,
  required bool adult,
  String? authorization,
  Duration timeout = const Duration(seconds: 20),
}) async {
  final http.Response response;
  try {
    response = await http
        .get(
          civitaiVersionUri(versionId, adult: adult),
          headers: {
            if (authorization != null && authorization.isNotEmpty)
              'Authorization': authorization,
          },
        )
        .timeout(timeout);
  } catch (_) {
    return const CivitaiVersionLookup(CivitaiLookupKind.failed);
  }
  switch (response.statusCode) {
    case 200:
      final version = parseCivitaiVersion(response.body);
      if (version == null || version.id != versionId) {
        return const CivitaiVersionLookup(CivitaiLookupKind.failed);
      }
      return CivitaiVersionLookup(CivitaiLookupKind.ok, version);
    case 401:
      return const CivitaiVersionLookup(CivitaiLookupKind.needsCredential);
    case 403:
      return const CivitaiVersionLookup(CivitaiLookupKind.locked);
    case 404:
      return const CivitaiVersionLookup(CivitaiLookupKind.notFound);
    default:
      return const CivitaiVersionLookup(CivitaiLookupKind.failed);
  }
}
