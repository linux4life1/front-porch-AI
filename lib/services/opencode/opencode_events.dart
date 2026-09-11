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

sealed class OpenCodeBusEvent {
  const OpenCodeBusEvent();
}

class OpenCodeTextDelta extends OpenCodeBusEvent {
  const OpenCodeTextDelta({
    required this.sessionId,
    required this.delta,
    this.messageId = '',
  });
  final String sessionId;
  final String messageId;
  final String delta;
}

class OpenCodeToolEvent extends OpenCodeBusEvent {
  const OpenCodeToolEvent({
    required this.sessionId,
    required this.name,
    required this.detail,
    required this.ok,
    this.pending = false,
  });
  final String sessionId;
  final String name;
  final String detail;
  final bool ok;
  final bool pending;
}

class OpenCodeSessionIdle extends OpenCodeBusEvent {
  const OpenCodeSessionIdle(this.sessionId);
  final String sessionId;
}

class OpenCodePermissionAsked extends OpenCodeBusEvent {
  const OpenCodePermissionAsked({
    required this.permissionId,
    required this.sessionId,
    required this.permission,
    required this.patterns,
  });
  final String permissionId;
  final String sessionId;
  final String permission;
  final List<String> patterns;
}

class OpenCodeTodoItem {
  const OpenCodeTodoItem({
    required this.content,
    required this.status,
    required this.priority,
  });
  final String content;
  final String status;
  final String priority;
}

class OpenCodeTodoUpdated extends OpenCodeBusEvent {
  const OpenCodeTodoUpdated({required this.sessionId, required this.todos});
  final String sessionId;
  final List<OpenCodeTodoItem> todos;
}

class OpenCodeErrorEvent extends OpenCodeBusEvent {
  const OpenCodeErrorEvent(this.message);
  final String message;
}

/// Dumb consumer the UI/harness implements. No Dart gym, no ledger.
abstract class OpenCodeEventSink {
  void onTextDelta(String delta, {String messageId = ''});
  void onTool({
    required String name,
    required String detail,
    required bool ok,
    bool pending = false,
  });
  void onPermissionAsk(OpenCodePermissionAsked ask);
  void onTodo(List<OpenCodeTodoItem> todos);
  void onIdle();
  void onError(String message);
}

void dispatchOpenCodeEvent(OpenCodeBusEvent event, OpenCodeEventSink sink) {
  switch (event) {
    case OpenCodeTextDelta(:final delta, :final messageId):
      if (delta.isNotEmpty) {
        sink.onTextDelta(delta, messageId: messageId);
      }
    case OpenCodeToolEvent():
      sink.onTool(
        name: event.name,
        detail: event.detail,
        ok: event.ok,
        pending: event.pending,
      );
    case OpenCodePermissionAsked():
      sink.onPermissionAsk(event);
    case OpenCodeTodoUpdated(:final todos):
      sink.onTodo(todos);
    case OpenCodeSessionIdle():
      sink.onIdle();
    case OpenCodeErrorEvent(:final message):
      sink.onError(message);
  }
}

List<OpenCodeBusEvent> parseOpenCodeSse(String raw) {
  final out = <OpenCodeBusEvent>[];
  final blocks = raw.replaceAll('\r\n', '\n').split('\n\n');
  for (final block in blocks) {
    final dataLines = <String>[];
    for (final line in block.split('\n')) {
      if (line.startsWith('data:')) {
        dataLines.add(line.substring(5).trimLeft());
      }
    }
    if (dataLines.isEmpty) continue;
    final payload = dataLines.join('\n');
    if (payload.isEmpty || payload == '[DONE]') continue;
    try {
      final json = jsonDecode(payload);
      if (json is Map<String, dynamic>) {
        final event = openCodeEventFromJson(json);
        if (event != null) out.add(event);
      } else if (json is Map) {
        final event = openCodeEventFromJson(Map<String, dynamic>.from(json));
        if (event != null) out.add(event);
      }
    } catch (_) {}
  }
  return out;
}

OpenCodeBusEvent? openCodeEventFromJson(Map<String, dynamic> json) {
  final type = json['type']?.toString() ?? '';
  final props = json['properties'];
  final data = json['data'];
  Map<String, dynamic> map;
  if (props is Map) {
    map = Map<String, dynamic>.from(props);
  } else if (data is Map) {
    map = Map<String, dynamic>.from(data);
  } else {
    map = json;
  }
  switch (type) {
    case 'message.part.delta':
      final field = map['field']?.toString().toLowerCase() ?? 'text';
      // Nano-GPT / OpenCode CoT — never paint as the coworker bubble.
      if (field != 'text') return null;
      return OpenCodeTextDelta(
        sessionId: map['sessionID']?.toString() ?? '',
        messageId: map['messageID']?.toString() ?? '',
        delta: map['delta']?.toString() ?? '',
      );
    case 'message.part.updated':
      return _toolFromPart(map);
    case 'session.idle':
      return OpenCodeSessionIdle(map['sessionID']?.toString() ?? '');
    case 'permission.asked':
    case 'permission.v2.asked':
      return _permissionAsked(map);
    case 'todo.updated':
      return OpenCodeTodoUpdated(
        sessionId: map['sessionID']?.toString() ?? '',
        todos: [
          for (final t in map['todos'] as List? ?? const [])
            if (t is Map)
              OpenCodeTodoItem(
                content: t['content']?.toString() ?? '',
                status: t['status']?.toString() ?? 'pending',
                priority: t['priority']?.toString() ?? 'medium',
              ),
        ],
      );
    case 'session.error':
      return OpenCodeErrorEvent(map['error']?.toString() ?? 'session error');
    default:
      return null;
  }
}

OpenCodePermissionAsked? _permissionAsked(Map<String, dynamic> map) {
  final nested = map['data'];
  final inner = nested is Map ? Map<String, dynamic>.from(nested) : map;
  var id = inner['id']?.toString() ?? '';
  if (!id.startsWith('per')) {
    id = inner['requestID']?.toString() ?? map['requestID']?.toString() ?? '';
  }
  if (!id.startsWith('per')) return null;
  final patterns = inner['patterns'] ?? inner['resources'] ?? map['patterns'];
  return OpenCodePermissionAsked(
    permissionId: id,
    sessionId: inner['sessionID']?.toString() ?? '',
    permission:
        inner['permission']?.toString() ?? inner['action']?.toString() ?? '',
    patterns: [for (final p in patterns as List? ?? const []) p.toString()],
  );
}

OpenCodeToolEvent? _toolFromPart(Map<String, dynamic> map) {
  final part = map['part'];
  if (part is! Map) return null;
  final partType = part['type']?.toString() ?? '';
  if (partType == 'reasoning' || partType == 'thinking') return null;
  if (partType != 'tool') return null;
  final state = part['state'];
  final status = state is Map
      ? state['status']?.toString() ?? ''
      : state?.toString() ?? '';
  final pending = status == 'pending' || status == 'running';
  final ok = status == 'completed' || status == 'success';
  final detail = state is Map
      ? (state['title'] ?? state['output'] ?? status).toString()
      : status;
  return OpenCodeToolEvent(
    sessionId: map['sessionID']?.toString() ?? '',
    name: part['tool']?.toString() ?? 'tool',
    detail: detail,
    ok: ok,
    pending: pending,
  );
}

class OpenCodeSseParser {
  String _buf = '';

  List<OpenCodeBusEvent> add(String chunk) {
    _buf += chunk.replaceAll('\r\n', '\n');
    final out = <OpenCodeBusEvent>[];
    while (true) {
      final idx = _buf.indexOf('\n\n');
      if (idx < 0) break;
      final block = _buf.substring(0, idx);
      _buf = _buf.substring(idx + 2);
      out.addAll(parseOpenCodeSse('$block\n\n'));
    }
    return out;
  }
}
