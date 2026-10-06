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

import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/web/facade/chargen_facade.dart';
import 'package:front_porch_ai/services/web/util/util.dart';

/// AI character creator endpoints. Generation runs in the background and reports
/// progress over the WebSocket hub (chargen_status / chargen_done /
/// chargen_error); these endpoints only start it and report availability.
class WebChargenRoutes {
  WebChargenRoutes(this._facade, Router router) {
    router.get('/api/chargen/status', _status);
    router.post('/api/chargen/create', _create);
    router.post('/api/chargen/enhance', _enhance);
    router.post('/api/chargen/enhance-chats', _enhanceChats);
    router.post('/api/chargen/lore/urls', _loreUrls);
    router.post('/api/chargen/lore/file', _loreFile);
    // The creator's Greetings step (#370). Rewrite/add start a run and
    // answer at once; the text arrives over the hub (chargen_greeting_*).
    router.post('/api/chargen/greeting', _greeting);
    router.post('/api/chargen/greeting/add', _greetingAdd);
    router.post('/api/chargen/greeting/delete', _greetingDelete);
    router.post('/api/chargen/greeting/stop', _greetingStop);
  }

  final ChargenFacade _facade;

  Future<Map<String, dynamic>> _json(shelf.Request r) async {
    try {
      return await RequestBody.readJsonMap(r);
    } catch (_) {
      return const {};
    }
  }

  /// A facade answer as a response: its `status` and `error` when refused.
  shelf.Response _answer(Map<String, dynamic> result, Object Function() ok) {
    if (result['ok'] == true) return JsonResponse.ok(ok());
    return JsonResponse.error(
      (result['status'] as int?) ?? 400,
      result['error']?.toString() ?? 'Bad request',
    );
  }

  /// Body: `{characterId, index, direction?}`; index 0 is the first message.
  Future<shelf.Response> _greeting(shelf.Request r) async {
    final result = _facade.startGreeting(await _json(r));
    return _answer(
      result,
      () => {'status': 'started', 'index': result['index']},
    );
  }

  /// Body: `{characterId}`. Writes a new alternate, up to the cap.
  Future<shelf.Response> _greetingAdd(shelf.Request r) async {
    final result = _facade.startGreeting(await _json(r), add: true);
    return _answer(
      result,
      () => {'status': 'started', 'index': result['index']},
    );
  }

  /// Body: `{characterId, index}` (index 1 and up). Returns the greetings.
  Future<shelf.Response> _greetingDelete(shelf.Request r) async {
    final body = await _json(r);
    final raw = body['index'];
    final result = await _facade.deleteGreeting(
      body['characterId']?.toString().trim() ?? '',
      raw is num ? raw.toInt() : int.tryParse('$raw') ?? -1,
    );
    return _answer(
      result,
      () => {
        'firstMessage': result['firstMessage'],
        'alternateGreetings': result['alternateGreetings'],
      },
    );
  }

  /// Body: `{characterId}`. `{stopped}` is false when nothing was running.
  Future<shelf.Response> _greetingStop(shelf.Request r) async {
    final id = (await _json(r))['characterId']?.toString().trim() ?? '';
    return JsonResponse.ok({'stopped': _facade.stopGreeting(id)});
  }

  shelf.Response _status(shelf.Request r) =>
      JsonResponse.ok({'available': _facade.available});

  Future<shelf.Response> _create(shelf.Request r) async {
    Map<String, dynamic> body;
    try {
      body = await RequestBody.readJsonMap(r);
    } catch (_) {
      body = const {};
    }
    final result = _facade.startCreate(body);
    if (result['ok'] != true) {
      return JsonResponse.error(
        400,
        result['error']?.toString() ?? 'Bad request',
      );
    }
    return JsonResponse.ok({'status': 'started'});
  }

  /// Start an AI Enhance run (see [ChargenFacade.startEnhance]); the result
  /// arrives over the hub as `chargen_enhance_done` and saves nothing itself.
  Future<shelf.Response> _enhance(shelf.Request r) async {
    Map<String, dynamic> body;
    try {
      body = await RequestBody.readJsonMap(r);
    } catch (_) {
      body = const {};
    }
    final result = _facade.startEnhance(body);
    if (result['ok'] != true) {
      return JsonResponse.error(
        400,
        result['error']?.toString() ?? 'Bad request',
      );
    }
    return JsonResponse.ok({'status': 'started'});
  }

  /// Bring the base character's chats along onto the saved "(Enhanced)"
  /// copy — the web twin of the desktop wizard's last step. Body:
  /// `{fromId, toId}` (character dbIds); returns `{copied}`. 409 when a
  /// reply is mid-flight (same contract as the chat import route).
  Future<shelf.Response> _enhanceChats(shelf.Request r) async {
    Map<String, dynamic> body;
    try {
      body = await RequestBody.readJsonMap(r);
    } catch (_) {
      body = const {};
    }
    final fromId = body['fromId']?.toString().trim() ?? '';
    final toId = body['toId']?.toString().trim() ?? '';
    if (fromId.isEmpty || toId.isEmpty) {
      return JsonResponse.badRequest('fromId and toId are required');
    }
    try {
      final result = await _facade.copyEnhanceChats(fromId, toId);
      if (result['ok'] != true) {
        return JsonResponse.error(
          400,
          result['error']?.toString() ?? 'Bad request',
        );
      }
      return JsonResponse.ok({'copied': result['copied']});
    } on ChatImportBusy catch (e) {
      return JsonResponse.error(409, e.toString());
    } catch (e) {
      // Same posture as the chat import route: a mid-copy failure surfaces
      // as a friendly 500, never a raw shelf error page.
      debugPrint('[enhance-chats] $e');
      return JsonResponse.error(
        500,
        'Could not copy the chats. Try again, or copy on desktop.',
      );
    }
  }

  /// Scrape lore from one or more URLs. Body: `{urls: [..]}` (or `{urls: "a,b"}`).
  Future<shelf.Response> _loreUrls(shelf.Request r) async {
    Map<String, dynamic> body;
    try {
      body = await RequestBody.readJsonMap(r);
    } catch (_) {
      return JsonResponse.badRequest('Invalid JSON');
    }
    final raw = body['urls'];
    final urls = raw is List
        ? raw
              .map((e) => e.toString().trim())
              .where((s) => s.isNotEmpty)
              .toList()
        : raw
              .toString()
              .split(',')
              .map((e) => e.trim())
              .where((s) => s.isNotEmpty)
              .toList();
    if (urls.isEmpty) return JsonResponse.badRequest('No URLs provided');
    return JsonResponse.ok(await _facade.extractLoreFromUrls(urls));
  }

  /// Extract lore text from an uploaded file (raw bytes; `?filename=` gives type).
  Future<shelf.Response> _loreFile(shelf.Request r) async {
    final filename = r.url.queryParameters['filename'] ?? 'lore.txt';
    final List<int> bytes;
    try {
      bytes = await RequestBody.readBytes(
        r,
        maxBytes: RequestBody.uploadMaxBytes,
      );
    } catch (_) {
      return JsonResponse.error(413, 'File too large');
    }
    if (bytes.isEmpty) return JsonResponse.badRequest('Empty upload');
    return JsonResponse.ok(await _facade.extractLoreFromFile(bytes, filename));
  }
}
