// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/services/image/civitai_client.dart';
import 'package:front_porch_ai/services/image/civitai_credentials.dart';
import 'package:front_porch_ai/services/image/civitai_errors.dart';
import 'package:front_porch_ai/services/image/civitai_fetch.dart';
import 'package:front_porch_ai/services/image/civitai_images.dart';
import 'package:front_porch_ai/services/image/civitai_installed.dart';
import 'package:front_porch_ai/services/image/civitai_jobs.dart';
import 'package:front_porch_ai/services/image/civitai_search_pages.dart';
import 'package:front_porch_ai/services/image/civitai_version.dart';
import 'package:front_porch_ai/services/image/studio_model_roots.dart';
import 'package:front_porch_ai/services/web/auth/auth_service.dart';
import 'package:front_porch_ai/services/web/middleware/auth_middleware.dart';
import 'package:front_porch_ai/services/web/util/util.dart';

/// Phone relay for CivitAI. The account id comes from the session cookie.
/// The key is sent as a header and is not written to the log. Saving or
/// deleting the key needs a password step-up, like every other credential.
/// Adult search and adult downloads need the app's adult setting on.
class CivitaiRoutes {
  CivitaiRoutes(
    Router router, {
    required AuthService auth,
    required bool Function() adultAllowed,
    CivitaiRelay? relay,
    String? Function(String backend)? rootFor,
    Future<String?> Function(String backend)? rootForAsync,
    CivitaiDownloads? downloads,
    CivitaiVersionFetch? versionFetch,
    Future<int> Function(String root)? sweep,
    Future<bool> Function(String backend)? rootGone,
    Future<Map<String, String>> Function(String backend, String root)?
    typeFoldersFor,
    Future<List<String>> Function()? trustedRootsFor,
  }) : _auth = auth,
       _adultAllowed = adultAllowed,
       _relay = relay,
       _rootFor = rootFor ?? ((_) => null),
       _rootForAsync = rootForAsync,
       _downloads = downloads ?? CivitaiDownloads(),
       _versionFetch = versionFetch ?? fetchCivitaiVersion,
       _sweep = sweep ?? sweepCivitaiParts,
       _rootGone = rootGone ?? studioSavedRootMissing,
       _typeFoldersFor = typeFoldersFor ?? _noTypeFolders,
       _trustedRootsFor = trustedRootsFor ?? _noTrustedRoots {
    _ready = relay == null
        ? CivitaiCredentialStore.open().then(CivitaiRelay.new)
        : Future<CivitaiRelay>.value(relay);
    router.get('/api/image/civitai/search', search);
    router.get('/api/image/civitai/installed', installedFiles);
    router.get('/api/image/civitai/credential', credentialStatus);
    router.post('/api/image/civitai/credential', saveCredential);
    router.delete('/api/image/civitai/credential', signOut);
    router.post('/api/image/civitai/download', download);
    router.get('/api/image/civitai/download/status', downloadStatus);
    router.delete('/api/image/civitai/download', cancelDownload);
    router.post('/api/image/civitai/download/cancel', cancelDownload);
  }

  final AuthService _auth;
  final bool Function() _adultAllowed;
  final CivitaiRelay? _relay;
  final String? Function(String backend) _rootFor;
  final Future<String?> Function(String backend)? _rootForAsync;
  final CivitaiDownloads _downloads;
  final CivitaiVersionFetch _versionFetch;
  final Future<int> Function(String root) _sweep;
  final Future<bool> Function(String backend) _rootGone;
  final Future<Map<String, String>> Function(String backend, String root)
  _typeFoldersFor;

  final Future<List<String>> Function() _trustedRootsFor;

  static Future<Map<String, String>> _noTypeFolders(String _, String _) async =>
      const {};
  static Future<List<String>> _noTrustedRoots() async => const [];
  late final Future<CivitaiRelay> _ready;

  Future<String?> _savedRoot(String backend) {
    final asyncRoot = _rootForAsync;
    if (asyncRoot != null) return asyncRoot(backend);
    return Future<String?>.value(_rootFor(backend));
  }

  shelf.Response _fail(int status, String code, String message) {
    return JsonResponse.error(status, message, extra: {'code': code});
  }

  shelf.Response? _adultRefused(bool wantsAdult) {
    if (!wantsAdult || _adultAllowed()) return null;
    return _fail(
      403,
      'adult_disabled',
      'Adult models are turned off. Turn them on in Settings first.',
    );
  }

  shelf.Response _keyStoreDown(CivitaiKeyStoreException e) {
    return _fail(503, 'key_store', e.message);
  }

  String? _account(shelf.Request request) {
    return civitaiRelayAccount(
      request.context[kAuthUserIdContextKey]?.toString(),
    );
  }

  Future<shelf.Response> search(shelf.Request request) async {
    final account = _account(request);
    if (account == null) {
      return JsonResponse.unauthorized('Authentication required');
    }
    final query = request.url.queryParameters;
    final adult = query['adult'] == 'true';
    final refused = _adultRefused(adult);
    if (refused != null) return refused;
    final lora = query['sheet'] == 'lora';
    final relay = _relay ?? await _ready;
    final CivitaiSearchPlan plan;
    try {
      plan = await relay.planSearch(
        accountId: account,
        query: query['q'] ?? '',
        adult: adult,
        lora: lora,
        baseModel: query['base'] ?? '',
      );
    } on CivitaiKeyStoreException catch (e) {
      return _keyStoreDown(e);
    }
    debugPrint(plan.log);
    if (plan.uri == null) {
      return JsonResponse.ok({
        'items': <Object>[],
        'needsCredential': plan.needsCredential,
      });
    }
    final headers = <String, String>{
      if (plan.authorization != null) 'Authorization': plan.authorization!,
    };
    final CivitaiSearchPages found;
    try {
      found = await civitaiSearchPages(
        first: plan.uri!,
        headers: headers,
        includeAdult: adult,
        cursor: _cursor(query['cursor']),
      );
    } catch (e) {
      debugPrint('civitai search failed: ${e.runtimeType}');
      return _fail(502, 'network', 'CivitAI search failed');
    }
    final hadKey = plan.authorization != null;
    final kind = found.kind;
    // A page after the first that fails keeps the rows already found.
    if (found.rows.isEmpty || kind == CivitaiHttpKind.ok) {
      if (kind == CivitaiHttpKind.needsCredential) {
        return _fail(
          401,
          hadKey ? 'key_refused' : 'key_missing',
          civitaiSearchNote(kind: kind, hadKey: hadKey, rows: 0),
        );
      }
      if (kind == CivitaiHttpKind.locked) {
        return _fail(403, 'locked', 'CivitAI refused this search');
      }
      if (kind != CivitaiHttpKind.ok) {
        return _fail(502, 'http', 'CivitAI search failed');
      }
    }
    return JsonResponse.ok({
      'items': [
        for (final row in found.rows)
          {
            'id': row.id,
            'name': row.name,
            'type': row.type,
            'adult': row.adult,
            'versionId': row.versionId,
            'filename': row.filename,
            // Only CivitAI's own image host: it is the one host the phone's
            // Content-Security-Policy lets a picture load from.
            'previewUrl': _phoneImages(row).firstOrNull,
            'images': _phoneImages(row),
            'description': row.description,
            'downloads': row.downloads,
          },
      ],
      'needsCredential': false,
      'nextCursor': found.nextCursor,
      'note': found.note(hadKey: hadKey),
    });
  }

  /// CivitAI's own cursor, passed back as it came; anything odd starts over.
  static String? _cursor(String? raw) {
    final cursor = raw?.trim() ?? '';
    if (cursor.isEmpty || cursor.length > 512) return null;
    return cursor;
  }

  List<String> _phoneImages(CivitaiModelRow row) => [
    for (final url in row.imageUrls)
      if (civitaiPhoneImage(url) != null) url,
  ];

  Future<shelf.Response> installedFiles(shelf.Request request) async {
    final account = _account(request);
    if (account == null) {
      return JsonResponse.unauthorized('Authentication required');
    }
    final backend = request.url.queryParameters['backend'] ?? '';
    final root = await _savedRoot(backend);
    if (root == null || root.trim().isEmpty) {
      return JsonResponse.ok({
        'bases': <String>[],
        'models': <String>[],
        'loras': <String>[],
      });
    }
    final kinds = await _typeFoldersFor(backend, root);
    final models = await civitaiSlotNames(
      root: root,
      backend: backend,
      lora: false,
      typeFolders: kinds,
    );
    final loras = await civitaiSlotNames(
      root: root,
      backend: backend,
      lora: true,
      typeFolders: kinds,
    );
    return JsonResponse.ok({
      'bases': await civitaiInstalledBases(
        root: root,
        backend: backend,
        typeFolders: kinds,
      ),
      'models': models,
      'loras': loras,
    });
  }

  Future<shelf.Response> credentialStatus(shelf.Request request) async {
    final account = _account(request);
    if (account == null) {
      return JsonResponse.unauthorized('Authentication required');
    }
    final relay = _relay ?? await _ready;
    try {
      return JsonResponse.ok({
        'saved': await relay.store.read(account) != null,
      });
    } on CivitaiKeyStoreException catch (e) {
      return _keyStoreDown(e);
    }
  }

  Future<shelf.Response> saveCredential(shelf.Request request) async {
    final body = await _body(request);
    final account = _account(request);
    if (account == null) {
      return JsonResponse.unauthorized('Authentication required');
    }
    final denied = await denyUnlessSteppedUp(
      auth: _auth,
      body: body,
      request: request,
    );
    if (denied != null) return denied;
    final token = pastedCivitaiToken(body);
    if (token == null) {
      return _fail(400, 'bad_request', 'token is required');
    }
    final relay = _relay ?? await _ready;
    try {
      await relay.store.save(account, token);
    } on CivitaiKeyStoreException catch (e) {
      return _keyStoreDown(e);
    }
    debugPrint(civitaiLog(action: 'save', accountId: account));
    return JsonResponse.ok({'saved': true});
  }

  Future<shelf.Response> signOut(shelf.Request request) async {
    final body = await _body(request);
    final account = _account(request);
    if (account == null) {
      return JsonResponse.unauthorized('Authentication required');
    }
    final denied = await denyUnlessSteppedUp(
      auth: _auth,
      body: body,
      request: request,
    );
    if (denied != null) return denied;
    final relay = _relay ?? await _ready;
    try {
      await relay.store.signOut(account);
    } on CivitaiKeyStoreException catch (e) {
      return _keyStoreDown(e);
    }
    debugPrint(civitaiLog(action: 'sign-out', accountId: account));
    return JsonResponse.ok({'signedOut': true});
  }

  Future<shelf.Response> download(shelf.Request request) async {
    final body = await _body(request);
    final account = _account(request);
    if (account == null) {
      return JsonResponse.unauthorized('Authentication required');
    }
    final version = body['versionId'];
    if (version is! num || version.toInt() <= 0) {
      return _fail(400, 'bad_request', 'versionId is required');
    }
    final adult = body['adult'] == true;
    final refused = _adultRefused(adult);
    if (refused != null) return refused;
    final backend = body['backend']?.toString() ?? '';
    final savedRoot = await _savedRoot(backend);
    if (backend == 'comfyui' &&
        (savedRoot == null || savedRoot.trim().isEmpty) &&
        await comfyStudioIsRemote()) {
      return _fail(
        400,
        'remote_comfy',
        'This ComfyUI is on another computer. Save the download on that computer.',
      );
    }
    final gone =
        (savedRoot == null || savedRoot.trim().isEmpty) &&
        await _rootGone(backend);
    final blocked = civitaiBlockedDownload(
      backend: backend,
      savedRoot: savedRoot,
      savedGone: gone,
    );
    if (blocked != null) {
      return _fail(400, gone ? 'folder_missing' : 'no_folder', blocked);
    }
    final relay = _relay ?? await _ready;
    try {
      final key = await relay.store.read(account);
      if (key == null) return _refusal(CivitaiFailure.keyMissing);
      final lookup = await _versionFetch(
        versionId: version.toInt(),
        adult: adult,
        authorization: civitaiBearer(key),
      );
      final found = lookup.version;
      if (lookup.kind != CivitaiLookupKind.ok || found == null) {
        return _lookupFailure(lookup.kind);
      }
      final wanted = body['filename']?.toString().trim() ?? '';
      final file = wanted.isEmpty ? civitaiPickVersionFile(found) : null;
      final plan = await relay.planDownload(
        accountId: account,
        version: found,
        filename: wanted.isEmpty ? (file?.name ?? '') : wanted,
        adult: adult,
        adultAllowed: _adultAllowed(),
        savedRoot: savedRoot,
        fromLoraSheet: body['lora'] == true,
        backend: backend,
        typeFolders: await _typeFoldersFor(backend, savedRoot!),
        trustedRoots: await _trustedRootsFor(),
      );
      debugPrint(plan.log);
      if (plan.refused || plan.path == null) {
        return _refusal(plan.failure ?? CivitaiFailure.unsafe, plan.reason);
      }
      final kinds = await _typeFoldersFor(backend, savedRoot);
      for (final folder in {plan.root ?? savedRoot, ...kinds.values}) {
        await _sweepQuietly(folder);
      }
      final job = await _downloads.start(account, plan);
      return shelf.Response(
        202,
        body: jsonEncode(job.toJson()),
        headers: const {'Content-Type': 'application/json; charset=utf-8'},
      );
    } on CivitaiKeyStoreException catch (e) {
      return _keyStoreDown(e);
    } on CivitaiDownloadException catch (e) {
      debugPrint('civitai download refused: ${e.code}');
      return _refusal(e.kind, e.message);
    }
  }

  Future<shelf.Response> downloadStatus(shelf.Request request) async {
    final account = _account(request);
    if (account == null) {
      return JsonResponse.unauthorized('Authentication required');
    }
    final job = _downloads.job(
      request.url.queryParameters['job'] ?? '',
      account,
    );
    if (job == null) return _fail(404, 'not_found', 'No such download');
    return JsonResponse.ok(job.toJson());
  }

  Future<shelf.Response> cancelDownload(shelf.Request request) async {
    final account = _account(request);
    if (account == null) {
      return JsonResponse.unauthorized('Authentication required');
    }
    final body = await _body(request);
    final id =
        request.url.queryParameters['job'] ?? body['job']?.toString() ?? '';
    if (!_downloads.cancel(id, account)) {
      return _fail(404, 'not_found', 'No such download');
    }
    return JsonResponse.ok({'cancelled': true});
  }

  /// One place that turns a failure into an HTTP answer, so a status never
  /// depends on which code path found the problem.
  shelf.Response _refusal(CivitaiFailure kind, [String? message]) {
    final error = CivitaiDownloadException(kind, message ?? '');
    final text = message == null || message.isEmpty ? error.message : message;
    final status = switch (kind) {
      CivitaiFailure.busy ||
      CivitaiFailure.exists ||
      CivitaiFailure.nameTaken ||
      CivitaiFailure.cancelled => 409,
      CivitaiFailure.tooMany => 429,
      CivitaiFailure.diskFull => 507,
      CivitaiFailure.tooLarge => 413,
      CivitaiFailure.unsafe || CivitaiFailure.keyMissing => 400,
      CivitaiFailure.keyRefused ||
      CivitaiFailure.locked ||
      CivitaiFailure.adultBlocked => 403,
      CivitaiFailure.notFound => 404,
      _ => 502,
    };
    return JsonResponse.error(
      status,
      text,
      extra: {'code': error.code, 'installed': kind == CivitaiFailure.exists},
      extraHeaders: kind == CivitaiFailure.tooMany
          ? const {'Retry-After': '30'}
          : null,
    );
  }

  /// Clearing old partial files is housekeeping; if it fails, the download
  /// still goes ahead.
  Future<void> _sweepQuietly(String root) async {
    try {
      await _sweep(root);
    } catch (e) {
      debugPrint('civitai part sweep failed: ${e.runtimeType}');
    }
  }

  shelf.Response _lookupFailure(CivitaiLookupKind kind) {
    return switch (kind) {
      CivitaiLookupKind.needsCredential => _refusal(CivitaiFailure.keyRefused),
      CivitaiLookupKind.locked => _refusal(CivitaiFailure.locked),
      CivitaiLookupKind.notFound => _refusal(CivitaiFailure.notFound),
      _ => _refusal(CivitaiFailure.network),
    };
  }

  Future<Map<String, Object?>> _body(shelf.Request request) async {
    try {
      final raw = await RequestBody.readJsonMap(request);
      return raw.map((key, value) => MapEntry(key, value));
    } catch (_) {
      return const {};
    }
  }
}
