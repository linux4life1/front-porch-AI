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

import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/services/web/facade/backend_facade.dart';
import 'package:front_porch_ai/services/web/facade/image_facade.dart';
import 'package:front_porch_ai/services/web/util/json_response.dart';
import 'package:front_porch_ai/services/web/util/request_body.dart';

/// Backend lifecycle + local-model switching + HuggingFace downloader, plus
/// image-generation config/generate. Progress is polled (GET /downloads), not
/// streamed — simpler and robust for mobile sleep/wake.
class WebBackendRoutes {
  WebBackendRoutes(Router router, {BackendFacade? backend, ImageFacade? image})
      : _backend = backend,
        _image = image {
    if (backend != null) {
      router.get('/api/backend/status', _status);
      router.post('/api/backend/restart', _restart);
      router.post('/api/backend/stop', _stop);
      router.get('/api/backend/models', _models);
      router.post('/api/backend/models/switch', _switchModel);
      router.post('/api/backend/models/delete', _deleteModel);
      router.get('/api/backend/models-folder', _modelsFolder);
      router.get('/api/backend/hf/search', _hfSearch);
      router.get('/api/backend/hf/files', _hfFiles);
      router.get('/api/backend/downloads', _downloads);
      router.post('/api/backend/downloads', _queueDownload);
      // Bulk controls registered before the <taskId> route — single-segment
      // paths won't collide with the two-segment per-task pattern, but keep them
      // grouped for clarity.
      router.post('/api/backend/downloads/pause-all', _pauseAll);
      router.post('/api/backend/downloads/resume-all', _resumeAll);
      router.post('/api/backend/downloads/clear-completed', _clearCompleted);
      router.post('/api/backend/downloads/<taskId>/cancel', _cancelDownload);
      router.post('/api/backend/downloads/<taskId>/pause', _pauseDownload);
      router.post('/api/backend/downloads/<taskId>/resume', _resumeDownload);
      router.get('/api/backend/hardware', _hardware);
      router.post('/api/backend/hardware/redetect', _redetectHardware);
      router.get('/api/backend/recommendations', _recommendations);
      router.post('/api/backend/remote-models', _remoteModels);
      router.post('/api/backend/test-connection', _testConnection);
    }
    if (image != null) {
      router.get('/api/image/config', _imageConfig);
      router.post('/api/image/config', _imageUpdateConfig);
      router.post('/api/image/generate', _imageGenerate);
      router.get('/api/image/saved/<name>', _imageSaved);
    }
  }

  final BackendFacade? _backend;
  final ImageFacade? _image;

  shelf.Response _status(shelf.Request r) => JsonResponse.ok(_backend!.status());

  Future<shelf.Response> _restart(shelf.Request r) async {
    await _backend!.restart();
    return JsonResponse.ok(_backend.status());
  }

  Future<shelf.Response> _stop(shelf.Request r) async {
    await _backend!.stop();
    return JsonResponse.ok(_backend.status());
  }

  Future<shelf.Response> _models(shelf.Request r) async =>
      JsonResponse.ok({'models': await _backend!.localModels()});

  Future<shelf.Response> _switchModel(shelf.Request r) async {
    final body = await _json(r);
    final path = body['path']?.toString();
    if (path == null || path.isEmpty) {
      return JsonResponse.badRequest('path is required');
    }
    final ok = await _backend!.switchModel(path);
    if (!ok) return JsonResponse.error(404, 'Model not found');
    return JsonResponse.ok(_backend.status());
  }

  Future<shelf.Response> _hfSearch(shelf.Request r) async {
    final q = r.url.queryParameters['q']?.trim() ?? '';
    if (q.isEmpty) return JsonResponse.ok({'models': []});
    return JsonResponse.ok({'models': await _backend!.searchHf(q)});
  }

  Future<shelf.Response> _hfFiles(shelf.Request r) async {
    final repoId = r.url.queryParameters['repoId'] ?? '';
    if (repoId.isEmpty) return JsonResponse.badRequest('repoId is required');
    return JsonResponse.ok({'files': await _backend!.modelFiles(repoId)});
  }

  Future<shelf.Response> _deleteModel(shelf.Request r) async {
    final body = await _json(r);
    final path = body['path']?.toString();
    if (path == null || path.isEmpty) {
      return JsonResponse.badRequest('path is required');
    }
    final ok = await _backend!.deleteModel(path);
    if (!ok) return JsonResponse.error(404, 'Model not found');
    return JsonResponse.ok({'models': await _backend.localModels()});
  }

  shelf.Response _modelsFolder(shelf.Request r) =>
      JsonResponse.ok(_backend!.modelsFolder());

  shelf.Response _downloads(shelf.Request r) =>
      JsonResponse.ok(_backend!.downloadsState());

  Future<shelf.Response> _queueDownload(shelf.Request r) async {
    final body = await _json(r);
    final repoId = body['repoId']?.toString();
    final filename = body['filename']?.toString();
    if (repoId == null || filename == null) {
      return JsonResponse.badRequest('repoId and filename are required');
    }
    final taskId = await _backend!.queueDownload(repoId, filename);
    if (taskId == null) return JsonResponse.error(404, 'File not found in repo');
    return JsonResponse.ok({'taskId': taskId, ..._backend.downloadsState()});
  }

  shelf.Response _cancelDownload(shelf.Request r, String taskId) {
    final ok = _backend!.cancelDownload(taskId);
    if (!ok) return JsonResponse.error(404, 'Download not found');
    return JsonResponse.ok(_backend.downloadsState());
  }

  shelf.Response _pauseDownload(shelf.Request r, String taskId) {
    final ok = _backend!.pauseDownload(taskId);
    if (!ok) return JsonResponse.error(404, 'Download not found or not active');
    return JsonResponse.ok(_backend.downloadsState());
  }

  shelf.Response _resumeDownload(shelf.Request r, String taskId) {
    final ok = _backend!.resumeDownload(taskId);
    if (!ok) return JsonResponse.error(404, 'Download not found or not paused');
    return JsonResponse.ok(_backend.downloadsState());
  }

  shelf.Response _pauseAll(shelf.Request r) {
    _backend!.pauseAllDownloads();
    return JsonResponse.ok(_backend.downloadsState());
  }

  shelf.Response _resumeAll(shelf.Request r) {
    _backend!.resumeAllDownloads();
    return JsonResponse.ok(_backend.downloadsState());
  }

  shelf.Response _clearCompleted(shelf.Request r) {
    _backend!.clearCompletedDownloads();
    return JsonResponse.ok(_backend.downloadsState());
  }

  shelf.Response _hardware(shelf.Request r) {
    final hw = _backend!.hardware();
    if (hw == null) return JsonResponse.error(404, 'Hardware info unavailable');
    return JsonResponse.ok(hw);
  }

  Future<shelf.Response> _redetectHardware(shelf.Request r) async {
    final hw = await _backend!.redetectHardware();
    if (hw == null) return JsonResponse.error(404, 'Hardware info unavailable');
    return JsonResponse.ok(hw);
  }

  shelf.Response _recommendations(shelf.Request r) =>
      JsonResponse.ok({'queries': _backend!.recommendations()});

  // ── Remote (OpenAI-compatible) model picker ──────────────────────────────
  // Optional apiUrl/apiKey in the body let the Settings page preview a provider
  // before saving; the facade falls back to the stored remote credentials.
  Future<shelf.Response> _remoteModels(shelf.Request r) async {
    final body = await _json(r);
    final models = await _backend!.remoteModels(
      apiUrl: body['apiUrl']?.toString(),
      apiKey: body['apiKey']?.toString(),
    );
    return JsonResponse.ok({'models': models});
  }

  Future<shelf.Response> _testConnection(shelf.Request r) async {
    final body = await _json(r);
    final message = await _backend!.testRemoteConnection(
      apiUrl: body['apiUrl']?.toString(),
      apiKey: body['apiKey']?.toString(),
    );
    return JsonResponse.ok({
      'ok': message.toLowerCase().contains('success'),
      'message': message,
    });
  }

  // ── Image generation ─────────────────────────────────────────────────────
  shelf.Response _imageConfig(shelf.Request r) =>
      JsonResponse.ok(_image!.config());

  Future<shelf.Response> _imageUpdateConfig(shelf.Request r) async {
    await _image!.updateConfig(await _json(r));
    return JsonResponse.ok(_image.config());
  }

  Future<shelf.Response> _imageGenerate(shelf.Request r) async {
    final body = await _json(r);
    if ((body['prompt']?.toString().trim() ?? '').isEmpty) {
      return JsonResponse.badRequest('prompt is required');
    }
    final result = await _image!.generate(body);
    if (result == null) {
      return JsonResponse.error(502, _image.config()['statusMessage']?.toString() ?? 'Generation failed');
    }
    return JsonResponse.ok(result);
  }

  Future<shelf.Response> _imageSaved(shelf.Request r, String name) async {
    final file = _image!.savedImageFile(name);
    if (file == null) return JsonResponse.error(404, 'Image not found');
    return shelf.Response.ok(
      file.openRead(),
      headers: {
        'Content-Type': 'image/png',
        'Cache-Control': 'private, max-age=86400',
      },
    );
  }

  Future<Map<String, dynamic>> _json(shelf.Request request) async {
    try {
      return await RequestBody.readJsonMap(request);
    } catch (_) {
      return const {};
    }
  }
}
