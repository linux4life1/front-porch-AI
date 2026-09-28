// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/services/image/civitai_client.dart';
import 'package:front_porch_ai/services/image/studio_model_roots.dart';
import 'package:front_porch_ai/services/web/middleware/auth_middleware.dart';
import 'package:front_porch_ai/services/web/util/util.dart';

/// Phone relay for CivitAI. The account id comes from the session cookie.
/// The key is sent as a header and is not written to the log.
class CivitaiRoutes {
  CivitaiRoutes(
    Router router, {
    CivitaiRelay? relay,
    String? Function(String backend)? rootFor,
    Future<String?> Function(String backend)? rootForAsync,
    Future<void> Function(CivitaiDownloadPlan plan)? startDownload,
  }) : _relay = relay,
       _rootFor = rootFor ?? ((_) => null),
       _rootForAsync = rootForAsync,
       _startDownload = startDownload {
    _ready = relay == null
        ? CivitaiCredentialStore.open().then(CivitaiRelay.new)
        : Future<CivitaiRelay>.value(relay);
    router.get('/api/image/civitai/search', search);
    router.post('/api/image/civitai/credential', saveCredential);
    router.delete('/api/image/civitai/credential', signOut);
    router.post('/api/image/civitai/download', download);
  }

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
    final lora = query['sheet'] == 'lora';
    final relay = _relay ?? await _ready;
    final plan = await relay.planSearch(
      accountId: account,
      query: query['q'] ?? '',
      adult: adult,
      lora: lora,
      baseModel: query['base'] ?? '',
    );
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
      return JsonResponse.unauthorized('CivitAI needs your API key');
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

  Future<shelf.Response> saveCredential(shelf.Request request) async {
    final body = await _body(request);
    final account = _account(request);
    if (account == null) {
      return JsonResponse.unauthorized('Authentication required');
    }
    final token = pastedCivitaiToken(body);
    if (token == null) return JsonResponse.badRequest('token is required');
    final relay = _relay ?? await _ready;
    if (body['red'] == true) {
      await relay.store.saveRed(account, token);
    } else {
      await relay.store.save(account, token);
    }
    debugPrint(civitaiLog(action: 'save', accountId: account));
    return JsonResponse.ok({'saved': true});
  }

  Future<shelf.Response> signOut(shelf.Request request) async {
    final account = _account(request);
    if (account == null) {
      return JsonResponse.unauthorized('Authentication required');
    }
    final relay = _relay ?? await _ready;
    await relay.store.signOut(account);
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
    final backend = body['backend']?.toString() ?? '';
    final savedRoot = await _savedRoot(backend);
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
      return JsonResponse.badRequest('CivitAI download was refused');
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
