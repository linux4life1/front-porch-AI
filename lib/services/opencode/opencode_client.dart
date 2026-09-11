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

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:front_porch_ai/services/opencode/opencode_events.dart';

class OpenCodeHealth {
  const OpenCodeHealth({required this.healthy, required this.version});
  final bool healthy;
  final String version;
}

class OpenCodeSessionInfo {
  const OpenCodeSessionInfo({required this.id, this.title = ''});
  final String id;
  final String title;
}

/// Thin HTTP client for `opencode serve`. Not a second agent.
class OpenCodeClient {
  OpenCodeClient({required this.baseUri, this.directory, this.clientFactory});

  final Uri baseUri;
  final String? directory;
  final http.Client Function()? clientFactory;

  http.Client _newClient() => clientFactory?.call() ?? http.Client();

  Future<OpenCodeHealth> health() async {
    final client = _newClient();
    try {
      final resp = await client.get(_uri('/global/health'));
      if (resp.statusCode != 200) {
        return const OpenCodeHealth(healthy: false, version: '');
      }
      final json = jsonDecode(resp.body);
      if (json is! Map) {
        return const OpenCodeHealth(healthy: false, version: '');
      }
      return OpenCodeHealth(
        healthy: json['healthy'] == true,
        version: json['version']?.toString() ?? '',
      );
    } finally {
      client.close();
    }
  }

  Future<OpenCodeSessionInfo> createSession({
    String? title,
    String? agent,
  }) async {
    final client = _newClient();
    try {
      final resp = await client.post(
        _uri('/session'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({?'title': title, ?'agent': agent}),
      );
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw StateError('OpenCode session create failed: ${resp.statusCode}');
      }
      final json = jsonDecode(resp.body);
      if (json is! Map) {
        throw StateError('OpenCode session create returned no id');
      }
      return OpenCodeSessionInfo(
        id: json['id']?.toString() ?? '',
        title: json['title']?.toString() ?? title ?? '',
      );
    } finally {
      client.close();
    }
  }

  Future<void> promptAsync({
    required String sessionId,
    required List<Map<String, dynamic>> parts,
    String? agent,
    String? system,
  }) async {
    final client = _newClient();
    try {
      final resp = await client.post(
        _uri('/session/$sessionId/prompt_async'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'parts': parts, ?'agent': agent, ?'system': system}),
      );
      if (resp.statusCode != 204 &&
          (resp.statusCode < 200 || resp.statusCode >= 300)) {
        throw StateError('OpenCode prompt failed: ${resp.statusCode}');
      }
    } finally {
      client.close();
    }
  }

  Future<void> abort(String sessionId) async {
    final client = _newClient();
    try {
      await client.post(_uri('/session/$sessionId/abort'));
    } finally {
      client.close();
    }
  }

  Future<void> respondPermission({
    required String sessionId,
    required String permissionId,
    required String response,
  }) async {
    final client = _newClient();
    try {
      await client.post(
        _uri('/session/$sessionId/permissions/$permissionId'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'response': response}),
      );
    } finally {
      client.close();
    }
  }

  /// Subscribe to `/event`, send the prompt, pump into [sink] until idle.
  Future<void> promptAndPump({
    required String sessionId,
    required List<Map<String, dynamic>> parts,
    required OpenCodeEventSink sink,
    String? agent,
    String? system,
  }) async {
    final client = _newClient();
    final idle = Completer<void>();
    StreamSubscription<List<int>>? sub;
    try {
      final req = http.Request('GET', _uri('/event'))
        ..headers['accept'] = 'text/event-stream';
      final streamed = await client.send(req);
      final parser = OpenCodeSseParser();
      sub = streamed.stream.listen(
        (chunk) {
          for (final event in parser.add(utf8.decode(chunk))) {
            final sid = switch (event) {
              OpenCodeTextDelta(:final sessionId) => sessionId,
              OpenCodeToolEvent(:final sessionId) => sessionId,
              OpenCodeSessionIdle(:final sessionId) => sessionId,
              OpenCodePermissionAsked(:final sessionId) => sessionId,
              OpenCodeTodoUpdated(:final sessionId) => sessionId,
              OpenCodeErrorEvent() => sessionId,
            };
            if (sid.isNotEmpty && sid != sessionId) continue;
            dispatchOpenCodeEvent(event, sink);
            if (event is OpenCodeSessionIdle && !idle.isCompleted) {
              idle.complete();
            }
            if (event is OpenCodeErrorEvent && !idle.isCompleted) {
              idle.completeError(StateError(event.message));
            }
          }
        },
        onError: (Object e, StackTrace st) {
          if (!idle.isCompleted) idle.completeError(e, st);
        },
      );
      await promptAsync(
        sessionId: sessionId,
        parts: parts,
        agent: agent,
        system: system,
      );
      await idle.future;
    } finally {
      await sub?.cancel();
      client.close();
    }
  }

  Uri _uri(String path) {
    return baseUri.replace(
      path: path,
      queryParameters: {
        if (directory != null && directory!.isNotEmpty) 'directory': directory,
      },
    );
  }
}
