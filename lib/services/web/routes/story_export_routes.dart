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

import 'package:front_porch_ai/services/web/facade/story_export_facade.dart';
import 'package:front_porch_ai/services/web/util/json_response.dart';
import 'package:front_porch_ai/services/web/util/request_body.dart';

/// Host-bound Porch Stories export endpoints: EPUB ebook download, background
/// audiobook compilation + download, and per-scene "read to me" narration. All
/// synthesis runs on the host; the browser only downloads/plays the artifact.
/// Registered after [WebStoryRoutes] — the `<id>/ebook|audiobook|narrate` paths
/// have an extra segment so they never collide with `/api/stories/<id>`.
class WebStoryExportRoutes {
  WebStoryExportRoutes(this._facade, Router router) {
    router.get('/api/stories/<id>/ebook', _ebook);
    router.post('/api/stories/<id>/audiobook', _startAudiobook);
    router.get('/api/stories/<id>/audiobook', _downloadAudiobook);
    router.get('/api/stories/<id>/audiobook/status', _audiobookStatus);
    router.post('/api/stories/<id>/audiobook/cancel', _cancelAudiobook);
    router.post('/api/stories/<id>/narrate', _narrate);
  }

  final StoryExportFacade _facade;

  Future<shelf.Response> _ebook(shelf.Request r, String id) async {
    final bytes = await _facade.epub(id);
    if (bytes == null) {
      return JsonResponse.error(404, 'Story not found or has no content');
    }
    return shelf.Response.ok(
      bytes,
      headers: {
        'Content-Type': 'application/epub+zip',
        'Content-Disposition': 'attachment; filename="story.epub"',
        'Cache-Control': 'no-store',
      },
    );
  }

  Future<shelf.Response> _startAudiobook(shelf.Request r, String id) async {
    if (!_facade.ttsAvailable) {
      return JsonResponse.error(503, 'TTS is off — enable it to make audio');
    }
    final ok = await _facade.startAudiobook(id);
    if (!ok) {
      return JsonResponse.error(
        409,
        'Unknown story or an audiobook is already compiling',
      );
    }
    return JsonResponse.ok({'status': 'started'});
  }

  shelf.Response _audiobookStatus(shelf.Request r, String id) =>
      JsonResponse.ok(_facade.audiobookStatus());

  shelf.Response _cancelAudiobook(shelf.Request r, String id) {
    _facade.cancelAudiobook();
    return JsonResponse.ok({'status': 'cancelled'});
  }

  Future<shelf.Response> _downloadAudiobook(shelf.Request r, String id) async {
    final file = _facade.audiobookFile(id);
    if (file == null) {
      return JsonResponse.error(404, 'Audiobook not ready');
    }
    final bytes = await file.readAsBytes();
    return shelf.Response.ok(
      bytes,
      headers: {
        'Content-Type': 'audio/wav',
        'Content-Disposition': 'attachment; filename="audiobook.wav"',
        'Cache-Control': 'no-store',
      },
    );
  }

  Future<shelf.Response> _narrate(shelf.Request r, String id) async {
    if (!_facade.ttsAvailable) {
      return JsonResponse.error(503, 'TTS is off — enable it to read aloud');
    }
    Map<String, dynamic> body;
    try {
      body = await RequestBody.readJsonMap(r);
    } catch (_) {
      body = const {};
    }
    final actIndex = body['actIndex'] is int ? body['actIndex'] as int : -1;
    final sceneIndex = body['sceneIndex'] is int
        ? body['sceneIndex'] as int
        : -1;
    final file = await _facade.narrateScene(id, actIndex, sceneIndex);
    if (file == null) {
      return JsonResponse.error(404, 'No prose to read for that scene');
    }
    final bytes = await file.readAsBytes();
    return shelf.Response.ok(
      bytes,
      headers: {'Content-Type': 'audio/wav', 'Cache-Control': 'no-store'},
    );
  }
}
