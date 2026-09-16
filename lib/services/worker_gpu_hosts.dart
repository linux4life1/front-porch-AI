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

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:front_porch_ai/services/capability/capability.dart';
import 'package:front_porch_ai/services/worker_gpu_swap.dart';

typedef SwapHttpSend =
    Future<http.Response> Function(
      String method,
      Uri uri,
      Map<String, String> headers,
      String? body,
    );

/// Documented oMLX / LM Studio / Kobold admin calls. Nothing invented.
class HttpGpuSwapHost implements GpuSwapHost {
  HttpGpuSwapHost({
    required this.kind,
    required this.apiUrl,
    required this.modelId,
    this.apiKey = '',
    SwapHttpSend? send,
  }) : _send = send ?? _defaultSend;

  final LocalSwapKind kind;
  final String apiUrl;
  final String modelId;
  final String apiKey;
  final SwapHttpSend _send;

  @override
  String get label => '${kind.name}:$modelId';

  static Future<http.Response> _defaultSend(
    String method,
    Uri uri,
    Map<String, String> headers,
    String? body,
  ) {
    final req = http.Request(method, uri);
    req.headers.addAll(headers);
    if (body != null) req.body = body;
    return req.send().then(http.Response.fromStream);
  }

  Map<String, String> get _headers {
    final h = <String, String>{'Accept': 'application/json'};
    if (apiKey.trim().isNotEmpty) {
      h['Authorization'] = 'Bearer ${apiKey.trim()}';
    }
    return h;
  }

  @override
  Future<void> unload() => switch (kind) {
    LocalSwapKind.omlx => _omlx('unload'),
    LocalSwapKind.lmStudio => _lmStudioUnload(),
    LocalSwapKind.koboldProcess => _koboldAdmin('unload_model'),
  };

  @override
  Future<void> restore() => switch (kind) {
    LocalSwapKind.omlx => _omlx('load'),
    LocalSwapKind.lmStudio => _lmStudioLoad(),
    LocalSwapKind.koboldProcess => _koboldAdmin('initial_model'),
  };

  Future<void> _omlx(String action) async {
    if (modelId.trim().isEmpty) {
      throw StateError('oMLX $action needs a model id');
    }
    final id = modelId.trim();
    final primary = _omlxUri(['v1', 'models', id, action]);
    if (primary == null) {
      throw StateError('oMLX URL is not a usable origin: $apiUrl');
    }
    final ok = await _postEmpty(primary);
    if (ok) return;
    final admin = _omlxUri(['admin', 'api', 'models', id, action]);
    if (admin != null && await _postEmpty(admin)) return;
    throw StateError('oMLX $action failed for $modelId');
  }

  Uri? _omlxUri(List<String> segments) {
    final origin = originEndpointUri(apiUrl, segments.first);
    if (origin == null) return null;
    return origin.replace(
      pathSegments: [
        ...origin.pathSegments.where((s) => s.isNotEmpty),
        ...segments.skip(1),
      ],
    );
  }

  Future<void> _lmStudioUnload() async {
    final uri = originEndpointUri(apiUrl, 'api/v1/models/unload');
    if (uri == null) throw StateError('LM Studio URL is not a usable origin');
    final instanceId = await _lmStudioInstanceId();
    final resp = await _postJson(uri, {'instance_id': instanceId});
    if (resp.statusCode >= 200 && resp.statusCode < 300) return;
    throw StateError('LM Studio unload HTTP ${resp.statusCode}');
  }

  /// Documented `GET /api/v1/models` → `loaded_instances[].id`. The unload
  /// example also accepts the model key as `instance_id` when list misses.
  Future<String> _lmStudioInstanceId() async {
    final wanted = modelId.trim();
    final listUri = originEndpointUri(apiUrl, 'api/v1/models');
    if (listUri != null) {
      try {
        final resp = await _send('GET', listUri, _headers, null);
        if (resp.statusCode >= 200 && resp.statusCode < 300) {
          final resolved = instanceIdFromLmStudioModels(resp.body, wanted);
          if (resolved != null) return resolved;
        }
      } catch (e) {
        debugPrint('[GpuSwap] LM Studio model list missed: $e');
      }
    }
    return wanted;
  }

  Future<void> _lmStudioLoad() async {
    final uri = originEndpointUri(apiUrl, 'api/v1/models/load');
    if (uri == null) throw StateError('LM Studio URL is not a usable origin');
    final resp = await _postJson(uri, {'model': modelId.trim()});
    if (resp.statusCode >= 200 && resp.statusCode < 300) return;
    throw StateError('LM Studio load HTTP ${resp.statusCode}');
  }

  Future<void> _koboldAdmin(String filename) async {
    final uri = originEndpointUri(apiUrl, 'api/admin/reload_config');
    if (uri == null) {
      throw StateError('Kobold admin URL is not a usable origin');
    }
    final resp = await _postJson(uri, {'filename': filename});
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      try {
        final body = jsonDecode(resp.body);
        if (body is Map && body['success'] == true) return;
      } catch (_) {}
    }
    throw StateError('Kobold admin $filename HTTP ${resp.statusCode}');
  }

  Future<bool> _postEmpty(Uri uri) async {
    final resp = await _send('POST', uri, _headers, null);
    return resp.statusCode >= 200 && resp.statusCode < 300;
  }

  Future<http.Response> _postJson(Uri uri, Map<String, Object> body) {
    return _send('POST', uri, {
      ..._headers,
      'Content-Type': 'application/json',
    }, jsonEncode(body));
  }
}

/// Pure parse of LM Studio `GET /api/v1/models` for a loaded instance id.
String? instanceIdFromLmStudioModels(String body, String wanted) {
  if (wanted.isEmpty) return null;
  try {
    final decoded = jsonDecode(body);
    if (decoded is! Map) return null;
    final models = decoded['models'];
    if (models is! List) return null;
    for (final raw in models) {
      if (raw is! Map) continue;
      final key = raw['key']?.toString() ?? '';
      final instances = raw['loaded_instances'];
      if (instances is! List || instances.isEmpty) continue;
      final first = instances.first;
      if (first is! Map) continue;
      final id = first['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      if (key == wanted || id == wanted) return id;
    }
  } catch (_) {}
  return null;
}

/// Managed KoboldCpp process. Admin HTTP first; process stop/start is the
/// equivalent the app already owns when `--admin` is off.
class KoboldProcessHost implements GpuSwapHost {
  KoboldProcessHost({
    required this.baseUrl,
    required this.stopProcess,
    required this.startProcess,
    this.isProcessRunning,
    this.waitUntilReady,
    this.markNotReady,
    HttpGpuSwapHost? admin,
  }) : _admin = admin;

  final String baseUrl;
  final Future<void> Function() stopProcess;
  final Future<void> Function() startProcess;
  final bool Function()? isProcessRunning;
  final Future<void> Function()? waitUntilReady;
  final void Function()? markNotReady;
  final HttpGpuSwapHost? _admin;
  bool _usedAdmin = false;

  @override
  String get label => 'kobold:$baseUrl';

  @override
  Future<void> unload() async {
    final admin = _admin;
    if (admin != null) {
      try {
        await admin.unload();
        _usedAdmin = true;
        markNotReady?.call();
        return;
      } catch (e) {
        debugPrint(
          '[GpuSwap] Kobold admin unload missed, stopping process: $e',
        );
      }
    }
    _usedAdmin = false;
    await stopProcess();
  }

  @override
  Future<void> restore() async {
    var reloaded = false;
    if (_usedAdmin && _admin != null) {
      try {
        await _admin.restore();
        reloaded = true;
      } catch (e) {
        debugPrint(
          '[GpuSwap] Kobold admin restore missed, restarting process: $e',
        );
      }
    }
    if (!reloaded) {
      if (isProcessRunning?.call() == true) {
        await stopProcess();
      }
      await startProcess();
    }
    await waitUntilReady?.call();
  }
}
