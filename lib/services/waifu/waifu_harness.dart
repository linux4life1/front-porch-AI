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
import 'dart:typed_data';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/waifu/waifu_honesty.dart';
import 'package:front_porch_ai/services/waifu/waifu_jail.dart';
import 'package:front_porch_ai/services/waifu/waifu_opencode.dart';
import 'package:front_porch_ai/services/waifu/waifu_permissions.dart';
import 'package:front_porch_ai/services/waifu/waifu_question.dart';
import 'package:front_porch_ai/services/waifu/waifu_session.dart';
import 'package:front_porch_ai/services/waifu/waifu_sit_down.dart';
import 'package:front_porch_ai/services/waifu/waifu_store.dart';
import 'package:front_porch_ai/services/waifu/waifu_todos.dart';

const kWaifuPhotosUnsupported =
    'Photos are not in this OpenCode version — the text still went through.';

/// OpenCode client facade. Send records the user line first, then forwards.
class WaifuHarness implements OpenCodeEventSink {
  WaifuHarness({
    required this.session,
    this.manager,
    OpenCodeClient? client,
    String? sessionId,
    this.backend,
    this.onChanged,
    this.onAsk,
    this.onQuestion,
    this.store,
    this.mcpOptIn = false,
    this.mcpConfigOf,
  }) : _client = client,
       _sessionId = sessionId;

  final WaifuSession session;
  final OpenCodeManager? manager;
  final OpenCodePorchBackend? backend;
  final WaifuStore? store;
  void Function()? onChanged;
  WaifuAskFn? onAsk;
  WaifuQuestionFn? onQuestion;
  bool mcpOptIn;
  final Map<String, dynamic> Function()? mcpConfigOf;

  OpenCodeClient? _client;
  String? _sessionId;
  bool _aborted = false;
  int? _liveIndex;
  String? _lastAssistantMessageId;
  var _canRedo = false;
  var _afterTool = false;

  WaifuTodos get todos => session.todos;
  bool get isRunning => session.running;
  bool get canUndo =>
      !session.running &&
      _sessionId != null &&
      _lastAssistantMessageId != null &&
      !_canRedo;
  bool get canRedo => !session.running && _sessionId != null && _canRedo;

  void applyPathMode(WaifuPathMode next) {
    session.pathMode = next;
    _emit();
  }

  void refreshMeter() => _emit();

  Future<void> undo() async {
    final client = _client;
    final sid = _sessionId;
    var mid = _lastAssistantMessageId;
    if (client == null || sid == null || session.running) return;
    mid ??= await _lastAssistantId(client, sid);
    if (mid == null || mid.isEmpty) {
      session.transcript.add(const WaifuMessage.assistant(kWaifuUndoNeedsTurn));
      _emit();
      return;
    }
    try {
      await client.revert(sessionId: sid, messageId: mid);
      _lastAssistantMessageId = mid;
      _canRedo = true;
      session.transcript.add(
        const WaifuMessage.assistant('Reverted the last OpenCode turn.'),
      );
    } catch (e) {
      session.transcript.add(WaifuMessage.assistant('$e'));
    }
    _emit();
    await store?.saveLast(session);
  }

  Future<void> redo() async {
    final client = _client;
    final sid = _sessionId;
    if (client == null || sid == null || !_canRedo || session.running) return;
    try {
      await client.unrevert(sid);
      _canRedo = false;
      session.transcript.add(
        const WaifuMessage.assistant('Restored the reverted OpenCode turn.'),
      );
    } catch (e) {
      session.transcript.add(WaifuMessage.assistant('$e'));
    }
    _emit();
    await store?.saveLast(session);
  }

  Future<void> compact() async {
    await store?.saveLast(session);
    _emit();
  }

  Future<void> send(
    String task, {
    Uint8List? imagePng,
    String? imagePath,
  }) async {
    var text = task.trim();
    if (text.isEmpty && imagePng == null) return;
    if (session.running) {
      session.queued.add(
        WaifuQueuedFollowUp(
          text: text.isEmpty ? '(photo)' : text,
          imagePng: imagePng,
          imagePath: imagePath,
        ),
      );
      _emit();
      return;
    }
    if (text.isEmpty) text = '(photo)';
    _aborted = false;
    _liveIndex = null;
    _canRedo = false;
    _afterTool = false;
    session.running = true;
    session.transcript.add(WaifuMessage.user(text, imagePath: imagePath));
    if (session.title.isEmpty) session.title = waifuTitleFrom(text);
    _emit();
    try {
      await _forward(text, imagePng: imagePng);
      await store?.saveLast(session);
    } finally {
      session.running = false;
      _liveIndex = null;
      _emit();
    }
    if (_aborted || session.queued.isEmpty) return;
    final next = session.queued.removeAt(0);
    await send(next.text, imagePng: next.imagePng, imagePath: next.imagePath);
  }

  void abort() {
    _aborted = true;
    session.queued.clear();
    final id = _sessionId;
    final client = _client;
    if (id != null && client != null) {
      unawaited(client.abort(id));
    }
    if (session.running) {
      session.transcript.add(const WaifuMessage.assistant('Stopped.'));
    }
    _emit();
  }

  Future<void> _forward(String text, {Uint8List? imagePng}) async {
    final client = await _ensureClient();
    if (client == null || _sessionId == null) return;
    try {
      await client.promptAndPump(
        sessionId: _sessionId!,
        parts: openCodePromptParts(text: text, imagePng: imagePng),
        agent: openCodeAgentForMode(session.mode),
        sink: this,
      );
    } catch (e) {
      if (imagePng != null) {
        session.transcript.add(
          const WaifuMessage.assistant(kWaifuPhotosUnsupported),
        );
        try {
          await client.promptAndPump(
            sessionId: _sessionId!,
            parts: openCodePromptParts(text: text),
            agent: openCodeAgentForMode(session.mode),
            sink: this,
          );
        } catch (e2) {
          session.transcript.add(WaifuMessage.assistant('$e2'));
        }
      } else {
        session.transcript.add(WaifuMessage.assistant('$e'));
      }
    }
  }

  Future<OpenCodeClient?> _ensureClient() async {
    if (_client != null && _sessionId != null) return _client;
    final mgr = manager;
    final back = backend;
    if (mgr == null || back == null) return _client;
    final info = await waifuOpenCodeSitDown(
      manager: mgr,
      clientOf: (base, directory) {
        return _client = OpenCodeClient(baseUri: base, directory: directory);
      },
      coworker: session.coworker,
      folderRoot: session.folderRoot,
      pathMode: session.pathMode,
      mode: session.mode,
      backend: back,
      mcp: session.mcpOptIn ? mcpConfigOf?.call() : null,
    );
    _sessionId = info.id;
    _client ??= OpenCodeClient(
      baseUri: mgr.baseUri,
      directory: session.folderRoot,
    );
    await waifuLoadTodos(session.folderRoot, session.todos);
    _emit();
    return _client;
  }

  @override
  void onTextDelta(
    String delta, {
    String messageId = '',
    bool thinking = false,
  }) {
    if (messageId.isNotEmpty) _lastAssistantMessageId = messageId;
    if (delta.isEmpty) return;
    if (thinking && waifuThinkingNoise(delta)) return;
    final idx = _ensureLiveAssistant(
      thinking: thinking || waifuLooksLikeThinkingDump(delta),
    );
    final cur = session.transcript[idx];
    final asThink =
        !waifuLooksLikeSpoken(delta) &&
        (!_afterTool || thinking) &&
        (thinking || (cur.text.isEmpty && waifuLooksLikeThinkingDump(delta)));
    if (asThink) {
      if (waifuThinkingNoise(delta)) return;
      var next = '${cur.reasoning}$delta';
      if (thinking &&
          cur.reasoning.isNotEmpty &&
          (delta.startsWith(cur.reasoning) ||
              cur.reasoning.startsWith(delta))) {
        next = delta.length >= cur.reasoning.length ? delta : cur.reasoning;
      }
      if (waifuThinkingNoise(next)) return;
      final start =
          cur.thinkingStartMs ?? DateTime.now().millisecondsSinceEpoch;
      session.transcript[idx] = cur.copyWith(
        reasoning: next,
        thinkingStartMs: start,
      );
    } else {
      session.transcript[idx] = cur.copyWith(text: '${cur.text}$delta');
    }
    _emit();
  }

  @override
  void onTool({
    required String name,
    required String detail,
    required bool ok,
    bool pending = false,
    String callId = '',
  }) {
    if (!pending) _afterTool = true;
    session.transcript.add(
      WaifuMessage.tool(name: name, output: detail, ok: pending ? true : ok),
    );
    _ensureLiveAssistant(thinking: false);
    final idx = _liveIndex;
    if (idx != null) {
      final cur = session.transcript[idx];
      final chips = [...cur.chips];
      var i = -1;
      if (callId.isNotEmpty) {
        i = chips.indexWhere((c) => c.callId == callId);
      }
      if (i < 0) {
        i = chips.indexWhere((c) => c.pending && c.name == name);
      }
      final chip = WaifuToolChip(
        name: name,
        detail: detail,
        ok: ok,
        pending: pending,
        callId: callId,
      );
      if (i >= 0) {
        chips[i] = chip;
      } else {
        chips.add(chip);
      }
      session.transcript[idx] = cur.copyWith(chips: chips);
    }
    _emit();
  }

  @override
  void onPermissionAsk(OpenCodePermissionAsked ask) {
    unawaited(_replyPermission(ask));
  }

  @override
  void onTodo(List<OpenCodeTodoItem> todos) {
    if (todos.isEmpty) return;
    session.todos.write([
      for (var i = 0; i < todos.length; i++)
        {
          'id': '${i + 1}',
          'content': todos[i].content,
          'status': todos[i].status,
        },
    ]);
    unawaited(waifuSaveTodos(session.folderRoot, session.todos));
    _emit();
  }

  @override
  void onIdle() {
    final idx = _liveIndex;
    if (idx != null && idx < session.transcript.length) {
      final cur = session.transcript[idx];
      final start = cur.thinkingStartMs;
      if (start != null && cur.thinkingMs == 0) {
        session.transcript[idx] = cur.copyWith(
          thinkingMs: DateTime.now().millisecondsSinceEpoch - start,
        );
      }
    }
    _emit();
  }

  int _ensureLiveAssistant({required bool thinking}) {
    if (_liveIndex != null &&
        _liveIndex! >= 0 &&
        _liveIndex! < session.transcript.length &&
        session.transcript[_liveIndex!].kind == WaifuMsgKind.assistant) {
      return _liveIndex!;
    }
    for (var i = session.transcript.length - 1; i >= 0; i--) {
      final k = session.transcript[i].kind;
      if (k == WaifuMsgKind.user) break;
      if (k == WaifuMsgKind.assistant) {
        _liveIndex = i;
        return i;
      }
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    session.transcript.add(
      WaifuMessage.assistant('', thinkingStartMs: thinking ? now : null),
    );
    _liveIndex = session.transcript.length - 1;
    return _liveIndex!;
  }

  @override
  void onError(String message) {
    session.transcript.add(WaifuMessage.assistant(message));
    _emit();
  }

  Future<void> _replyPermission(OpenCodePermissionAsked ask) async {
    final client = _client;
    final id = _sessionId;
    if (client == null || id == null) return;
    String response;
    if (session.mode == WaifuMode.yolo) {
      response = 'once';
    } else {
      final decision =
          await onAsk?.call(
            WaifuAskRequest(
              toolName: ask.permission,
              summary: ask.patterns.join(', '),
            ),
          ) ??
          WaifuAskDecision.deny;
      response = switch (decision) {
        WaifuAskDecision.allowOnce => 'once',
        WaifuAskDecision.allowAlways => 'always',
        WaifuAskDecision.deny => 'reject',
      };
    }
    await client.respondPermission(
      sessionId: id,
      permissionId: ask.permissionId,
      response: response,
    );
  }

  Future<String?> _lastAssistantId(OpenCodeClient client, String sid) async {
    final msgs = await client.listMessages(sid);
    for (final m in msgs.reversed) {
      if (m.role == 'assistant' && m.id.isNotEmpty) return m.id;
    }
    return null;
  }

  void _emit() => onChanged?.call();
}

/// Nano-GPT dumps CoT as normal text. Same porch as chat think chips.
bool waifuLooksLikeThinkingDump(String raw) {
  final t = raw.trimLeft().toLowerCase();
  if (t.startsWith('<think')) return true;
  if (t.startsWith('the user wants')) return true;
  if (t.startsWith('let me ')) return true;
  if (t.startsWith("i'll read")) return true;
  if (t.contains('i have the todo list')) return true;
  if (t.contains('the todos are:')) return true;
  return false;
}

bool waifuThinkingNoise(String raw) {
  final t = raw.trim().toLowerCase();
  if (t.isEmpty) return true;
  return t == 'thought' || t == 'thinking' || t == '...' || t == '…';
}

/// Victory speech, quotes, markdown — not CoT.
bool waifuLooksLikeSpoken(String raw) {
  final t = raw.trimLeft();
  if (t.isEmpty) return false;
  if (t.startsWith('"') || t.startsWith('*') || t.startsWith('#')) return true;
  if (t.startsWith('YES') || t.startsWith('Done')) return true;
  if (t.contains('Mission Accomplished')) return true;
  return false;
}
