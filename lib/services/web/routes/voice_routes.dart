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

import 'package:front_porch_ai/services/web/facade/voice_facade.dart';
import 'package:front_porch_ai/services/web/util/json_response.dart';
import 'package:front_porch_ai/services/web/util/request_body.dart';

/// Voice endpoints: text-to-speech synthesis (played on the *client* device) and
/// speech-to-text over an uploaded mic recording. The host never plays or
/// records — synthesis returns bytes, transcription consumes uploaded bytes.
class WebVoiceRoutes {
  WebVoiceRoutes(this._facade, Router router) {
    router.get('/api/voice/status', _status);
    router.post('/api/tts/speak', _speak);
    router.post('/api/stt/transcribe', _transcribe);
  }

  final VoiceFacade _facade;

  shelf.Response _status(shelf.Request r) => JsonResponse.ok(_facade.status());

  Future<shelf.Response> _speak(shelf.Request r) async {
    Map<String, dynamic> body;
    try {
      body = await RequestBody.readJsonMap(r);
    } catch (_) {
      body = const {};
    }
    final text = body['text']?.toString() ?? '';
    if (text.trim().isEmpty) return JsonResponse.badRequest('text is required');
    final voiceKey = body['voiceKey']?.toString();
    final audio = await _facade.speak(text, voiceKey: voiceKey);
    if (audio == null) {
      return JsonResponse.error(503, 'TTS is off or produced no audio');
    }
    return shelf.Response.ok(
      audio.bytes,
      headers: {
        'Content-Type': audio.contentType,
        'Cache-Control': 'no-store',
      },
    );
  }

  Future<shelf.Response> _transcribe(shelf.Request r) async {
    final bytes = await RequestBody.readBytes(
      r,
      maxBytes: RequestBody.uploadMaxBytes,
    );
    if (bytes.isEmpty) return JsonResponse.badRequest('audio body is required');
    final ext = r.url.queryParameters['ext'];
    final text = await _facade.transcribe(bytes, ext: ext);
    if (text == null || text.isEmpty) {
      return JsonResponse.error(422, 'No speech detected or STT unavailable');
    }
    return JsonResponse.ok({'text': text});
  }
}
