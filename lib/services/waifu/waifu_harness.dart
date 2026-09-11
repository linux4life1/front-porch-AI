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

import 'package:front_porch_ai/services/opencode/opencode.dart';
import 'package:front_porch_ai/services/waifu/waifu_jail.dart';
import 'package:front_porch_ai/services/waifu/waifu_llm.dart';
import 'package:front_porch_ai/services/waifu/waifu_opencode.dart';
import 'package:front_porch_ai/services/waifu/waifu_permissions.dart';
import 'package:front_porch_ai/services/waifu/waifu_plan.dart';
import 'package:front_porch_ai/services/waifu/waifu_plan_codec.dart';
import 'package:front_porch_ai/services/waifu/waifu_question.dart';
import 'package:front_porch_ai/services/waifu/waifu_session.dart';
import 'package:front_porch_ai/services/waifu/waifu_skill_market.dart';
import 'package:front_porch_ai/services/waifu/waifu_sit_down.dart';
import 'package:front_porch_ai/services/waifu/waifu_store.dart';
import 'package:front_porch_ai/services/waifu/waifu_todos.dart';
import 'package:front_porch_ai/services/waifu/waifu_webfetch.dart';

const kWaifuPhotosUnsupported =
    'Photos are not in this OpenCode version — the text still went through.';

/// OpenCode client facade. Send records the user line first, then forwards.
class WaifuHarness implements OpenCodeEventSink {
  WaifuHarness({
    required this.session,
    this.llm,
    this.manager,
    OpenCodeClient? client,
    this.backend,
    this.onChanged,
    this.onAsk,
    this.onQuestion,
    this.store,
    this.mcpOptIn = false,
    this.mcpTools = const [],
    this.mcpToolsOf,
    this.mcpCall,
    this.mcpCallOf,
    this.webSearch,
    this.depth = 0,
    this.exploreOnly = false,
    WaifuSkillHub? skills,
  }) : _client = client,
       skills = skills ?? WaifuSkillHub(projectRoot: session.folderRoot);

  final WaifuSession session;
  final WaifuLlm? llm;
  final OpenCodeManager? manager;
  final OpenCodePorchBackend? backend;
  final WaifuStore? store;
  final int depth;
  final bool exploreOnly;
  final WaifuSkillHub skills;
  void Function()? onChanged;
  WaifuAskFn? onAsk;
  WaifuQuestionFn? onQuestion;
  bool mcpOptIn;
  final List<Map<String, dynamic>> mcpTools;
  final List<Map<String, dynamic>> Function()? mcpToolsOf;
  final WaifuMcpCallFn? mcpCall;
  final WaifuMcpCallFn? Function()? mcpCallOf;
  final WaifuWebSearchFn? webSearch;

  OpenCodeClient? _client;
  String? _sessionId;
  bool _aborted = false;
  int? _liveIndex;

  WaifuTodos get todos => session.todos;
  bool get isRunning => session.running;
  bool get canUndo => false;
  bool get canRedo => false;

  void applyPathMode(WaifuPathMode next) {
    session.pathMode = next;
    _emit();
  }

  void refreshMeter() => _emit();

  Future<void> undo() async {}

  Future<void> redo() async {}

  Future<void> compact() async {
    await store?.saveLast(session);
    _emit();
  }

  Future<WaifuPlan?> acceptActivePlan({String? editedBody}) async {
    final plan = await waifuAcceptPlan(
      session: session,
      todos: todos,
      editedBody: editedBody,
    );
    await store?.saveLast(session);
    _emit();
    return plan;
  }

  Future<WaifuPlan?> reviseActivePlan({String? editedBody}) async {
    final plan = await waifuRevisePlan(
      session: session,
      editedBody: editedBody,
    );
    await store?.saveLast(session);
    _emit();
    return plan;
  }

  Future<void> discardActivePlan() async {
    await waifuDiscardPlan(session);
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
    );
    _sessionId = info.id;
    _client ??= OpenCodeClient(
      baseUri: mgr.baseUri,
      directory: session.folderRoot,
    );
    return _client;
  }

  @override
  void onTextDelta(String delta) {
    if (delta.isEmpty) return;
    if (_liveIndex == null) {
      session.transcript.add(WaifuMessage.assistant(delta));
      _liveIndex = session.transcript.length - 1;
    } else {
      final cur = session.transcript[_liveIndex!];
      session.transcript[_liveIndex!] = cur.copyWith(text: '${cur.text}$delta');
    }
    _emit();
  }

  @override
  void onTool({
    required String name,
    required String detail,
    required bool ok,
    bool pending = false,
  }) {
    session.transcript.add(
      WaifuMessage.tool(name: name, output: detail, ok: pending ? true : ok),
    );
    final idx = _liveIndex;
    if (idx != null) {
      final cur = session.transcript[idx];
      session.transcript[idx] = cur.copyWith(
        chips: [
          ...cur.chips,
          WaifuToolChip(name: name, detail: detail, ok: ok, pending: pending),
        ],
      );
    }
    _emit();
  }

  @override
  void onPermissionAsk(OpenCodePermissionAsked ask) {
    unawaited(_replyPermission(ask));
  }

  @override
  void onTodo(List<OpenCodeTodoItem> todos) {
    session.todos.write([
      for (var i = 0; i < todos.length; i++)
        {
          'id': '${i + 1}',
          'content': todos[i].content,
          'status': todos[i].status,
        },
    ]);
    _emit();
  }

  @override
  void onIdle() {
    _liveIndex = null;
    _emit();
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

  void _emit() => onChanged?.call();
}
