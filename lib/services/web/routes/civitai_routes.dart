// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/services/image/civitai_client.dart';
import 'package:front_porch_ai/services/image/civitai_credentials.dart';
import 'package:front_porch_ai/services/image/civitai_installed.dart';
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
    Future<void> Function(CivitaiDownloadPlan plan)? startDownload,
  }) : _auth = auth,
       _adultAllowed = adultAllowed,
       _relay = relay,
       _rootFor = rootFor ?? ((_) => null),
       _rootForAsync = rootForAsync,
       _startDownload = startDownload {
    _ready = relay == null
        ? CivitaiCredentialStore.open().then(CivitaiRelay.new)
        : Future<CivitaiRelay>.value(relay);
    router.get('/api/image/civitai/search', search);
    router.get('/api/image/civitai/installed', installedFiles);
    router.get('/api/image/civitai/credential', credentialStatus);
    router.post('/api/image/civitai/credential', saveCredential);
    router.delete('/api/image/civitai/credential', signOut);
    router.post('/api/image/civitai/download', download);
  }

  final AuthService _auth;
  final bool Function() _adultAllowed;
  final CivitaiRelay? _relay;
  final String? Function(String backend) _rootFor;
  final Future<String?> Function(String backend)? _rootForAsync;
  final Future<void> Function(CivitaiDownloadPlan plan)? _startDownload;
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
    final http.Response response;
    try {
      response = await http
          .get(plan.uri!, headers: headers)
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      debugPrint('civitai search failed: ${e.runtimeType}');
      return JsonResponse.error(502, 'CivitAI search failed');
    }
    final kind = civitaiHttpKind(response.statusCode);
    if (kind == CivitaiHttpKind.needsCredential) {
      return JsonResponse.unauthorized(
        civitaiSearchNote(
          kind: kind,
          hadKey: plan.authorization != null,
          rows: 0,
        ),
      );
    }
    if (kind == CivitaiHttpKind.locked) {
      return JsonResponse.forbidden('CivitAI refused this search');
    }
    if (kind != CivitaiHttpKind.ok) {
      return JsonResponse.error(502, 'CivitAI search failed');
    }
    final rows = parseCivitaiModels(response.body, includeAdult: adult);
    return JsonResponse.ok({
      'items': [
        for (final row in rows)
          {
            'id': row.id,
            'name': row.name,
            'type': row.type,
            'adult': row.adult,
            'versionId': row.versionId,
            'filename': row.filename,
            'previewUrl': row.previewUrl,
            'images': row.imageUrls,
            'description': row.description,
            'downloads': row.downloads,
          },
      ],
      'needsCredential': false,
    });
  }

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
    final models = await civitaiSlotNames(
      root: root,
      backend: backend,
      lora: false,
    );
    final loras = await civitaiSlotNames(
      root: root,
      backend: backend,
      lora: true,
    );
    return JsonResponse.ok({
      'bases': await civitaiInstalledBases(root: root, backend: backend),
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
    if (version is! num) {
      return JsonResponse.badRequest('versionId is required');
    }
    final refused = _adultRefused(body['adult'] == true);
    if (refused != null) return refused;
    final backend = body['backend']?.toString() ?? '';
    final savedRoot = await _savedRoot(backend);
    if (backend == 'comfyui' &&
        (savedRoot == null || savedRoot.trim().isEmpty) &&
        await comfyStudioIsRemote()) {
      return JsonResponse.badRequest(
        'This ComfyUI is on another computer. Save the download on that computer.',
      );
    }
    final blocked = civitaiBlockedDownload(
      backend: backend,
      savedRoot: savedRoot,
    );
    if (blocked != null) return JsonResponse.badRequest(blocked);
    final relay = _relay ?? await _ready;
    final plan = await relay.planDownload(
      accountId: account,
      versionId: version.toInt(),
      adult: body['adult'] == true,
      savedRoot: savedRoot,
      filename: body['filename']?.toString() ?? '',
      civitaiType: body['type']?.toString() ?? '',
      fromLoraSheet: body['lora'] == true,
      backend: backend,
    );
    debugPrint(plan.log);
    if (plan.refused || plan.path == null) {
      return JsonResponse.badRequest(
        plan.reason.isEmpty ? 'CivitAI download was refused' : plan.reason,
      );
    }
    final start = _startDownload;
    if (start == null) {
      return JsonResponse.error(
        501,
        'CivitAI file download starts on this computer',
        extra: {'downloaded': false, 'path': plan.path},
      );
    }
    try {
      await start(plan);
    } catch (e) {
      debugPrint('civitai download failed: ${e.runtimeType}');
      return JsonResponse.error(502, 'CivitAI download failed');
    }
    return JsonResponse.ok({'downloaded': true, 'path': plan.path});
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
