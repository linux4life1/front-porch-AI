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
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/waifu/waifu_jail.dart';
import 'package:front_porch_ai/services/waifu/waifu_opencode.dart';
import 'package:front_porch_ai/services/waifu/waifu_opencode_seat.dart';
import 'package:front_porch_ai/services/waifu/waifu_permissions.dart';
import 'package:front_porch_ai/services/waifu/waifu_question.dart';
import 'package:front_porch_ai/services/waifu/waifu_session.dart';
import 'package:front_porch_ai/services/waifu/waifu_sit_down.dart';
import 'package:front_porch_ai/services/waifu/waifu_speech.dart';
import 'package:front_porch_ai/services/waifu/waifu_stage.dart';
import 'package:front_porch_ai/services/waifu/waifu_store.dart';
import 'package:front_porch_ai/services/waifu/waifu_todos.dart';
import 'package:front_porch_ai/services/waifu/waifu_tool_rows.dart';

/// OpenCode client facade. Send records the user line first, then forwards.
class WaifuHarness implements OpenCodeEventSink, OpenCodeToolMessageSink {
  WaifuHarness({
    required this.session,
    OpenCodeManager? manager,
    OpenCodeClient? client,
    String? sessionId,
    OpenCodePorchBackend? backend,
    OpenCodePorchBackend? Function()? backendOf,
    this.keepLoaded,
    this.onChanged,
    this.onAsk,
    this.onQuestion,
    this.store,
    FutureOr<Map<String, dynamic>> Function()? mcpConfigOf,
    Directory? Function()? skillsDirOf,
  }) : seat = WaifuOpenCodeSeat(
         session: session,
         manager: manager,
         client: client,
         sessionId: sessionId,
         backend: backend,
         backendOf: backendOf,
         mcpConfigOf: mcpConfigOf,
         skillsDirOf: skillsDirOf,
       );

  final WaifuSession session;
  final WaifuOpenCodeSeat seat;

  /// Runs a turn with the model loaded: OpenCode asks the app's KoboldCpp
  /// itself, so a model unloaded for being idle is loaded back first.
  final Future<void> Function(Future<void> Function() turn)? keepLoaded;
  final WaifuStore? store;
  void Function()? onChanged;
  WaifuAskFn? onAsk;
  WaifuQuestionFn? onQuestion;

  bool _aborted = false;
  int? _liveIndex;
  String? _lastAssistantMessageId;

  /// First OpenCode message of this turn's coding pass (else of the turn).
  /// Revert removes that message and everything after it: the whole turn.
  String? _turnCodingId;
  String? _turnFirstId;
  var _canRedo = false;
  var _voicePass = true;
  final _think = WaifuThinkGate();

  WaifuTodos get todos => session.todos;
  bool get isRunning => session.running;
  bool get canUndo =>
      !session.running &&
      seat.sessionId != null &&
      _lastAssistantMessageId != null &&
      !_canRedo;
  bool get canRedo => !session.running && seat.sessionId != null && _canRedo;

  /// Takes effect on the next send: the seat restarts the serve with the
  /// new fence and resumes the same OpenCode session.
  void applyPathMode(WaifuPathMode next) {
    session.pathMode = next;
    _emit();
  }

  /// Plan/Build pick the agent per prompt; Yolo is answered per ask, so a
  /// switch mid-turn already covers the next tool call.
  void applyMode(WaifuMode next) {
    session.mode = next;
    _emit();
  }

  /// Library tools are MCP servers in the serve config: next send reseats.
  void applyToolsOptIn(bool optIn) {
    session.mcpOptIn = optIn;
    _emit();
  }

  /// Tool turn: OpenCode text is Thought until idle starts the voice pass.
  void beginCodingPass() => _voicePass = false;

  void refreshMeter() => _emit();

  Future<void> undo() async {
    final client = seat.client;
    final sid = seat.sessionId;
    var mid = _turnCodingId ?? _turnFirstId ?? _lastAssistantMessageId;
    if (client == null || sid == null || session.running) return;
    mid ??= waifuTurnStartAssistantId(await client.listMessages(sid));
    if (mid == null || mid.isEmpty) {
      session.transcript.add(_stage.nothingToUndo());
      _emit();
      return;
    }
    try {
      await client.revert(sessionId: sid, messageId: mid);
      _lastAssistantMessageId = mid;
      _canRedo = true;
      session.transcript.add(_stage.reverted());
    } catch (e) {
      session.transcript.add(_stage.snag(e));
    }
    _emit();
    await store?.saveLast(session);
  }

  Future<void> redo() async {
    final client = seat.client;
    final sid = seat.sessionId;
    if (client == null || sid == null || !_canRedo || session.running) return;
    try {
      await client.unrevert(sid);
      _canRedo = false;
      session.transcript.add(_stage.restored());
    } catch (e) {
      session.transcript.add(_stage.snag(e));
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
    if (!session.toolsSupported) {
      // The banner already says so; the turn must not run regardless.
      session.transcript
        ..add(WaifuMessage.user(text, imagePath: imagePath))
        ..add(_stage.noTools());
      _emit();
      await store?.saveLast(session);
      return;
    }
    _aborted = false;
    _liveIndex = null;
    _canRedo = false;
    _turnCodingId = null;
    _turnFirstId = null;
    beginCodingPass();
    session.running = true;
    session.transcript.add(WaifuMessage.user(text, imagePath: imagePath));
    if (session.title.isEmpty) session.title = waifuTitleFrom(text);
    _emit();
    try {
      final hold = keepLoaded;
      Future<void> turn() => _forward(text, imagePng: imagePng);
      try {
        await (hold == null ? turn() : hold(turn));
      } on LlmToolTransportException catch (e) {
        // The model could not be loaded back; the words say what to do.
        session.transcript.add(_stage.cannotReachModel(e.message));
      }
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
    final id = seat.sessionId;
    final client = seat.client;
    if (id != null && client != null) {
      unawaited(
        client.abort(id).catchError((Object e) {
          debugPrint('[waifu] OpenCode abort failed: $e');
        }),
      );
    }
    if (session.running) {
      session.transcript.add(_stage.stopped());
    }
    _emit();
  }

  Future<void> _forward(String text, {Uint8List? imagePng}) async {
    final client = await seat.ensure();
    final sid = seat.sessionId;
    _emit();
    if (client == null || sid == null) return;
    Future<void> pump(Uint8List? png) => client.promptAndPump(
      sessionId: sid,
      parts: openCodePromptParts(text: text, imagePng: png),
      agent: openCodeAgentForMode(session.mode),
      providerID: kOpenCodePorchProvider,
      modelID: seat.modelSlot,
      sink: this,
    );
    try {
      try {
        await pump(imagePng);
      } on OpenCodeStreamClosed {
        rethrow;
      } catch (e) {
        if (imagePng == null) rethrow;
        debugPrint('[waifu] photo turn failed, retrying as text: $e');
        session.transcript.add(_stage.noPhotos());
        await pump(null);
      }
      if (!_aborted && !waifuTurnSpoke(session.transcript, orNarrated: true)) {
        session.transcript.add(_stage.quietFinish());
      }
    } on OpenCodeStreamClosed catch (e) {
      // The serve is gone. Next send sits down again and resumes the session.
      seat.drop();
      session.transcript.add(_stage.lostLine(e));
    } catch (e) {
      session.transcript.add(_stage.snag(e));
    }
  }

  @override
  void onTextDelta(
    String delta, {
    String messageId = '',
    bool thinking = false,
  }) {
    if (messageId.isNotEmpty) onToolMessage(messageId);
    if (delta.isEmpty) return;
    if (thinking && waifuThinkingNoise(delta)) return;
    final asThink = waifuDeltaGoesToThought(
      voicePass: _voicePass,
      thinking: thinking,
    );
    final idx = _ensureLiveAssistant(thinking: asThink);
    session.transcript[idx] = _think.applyDelta(
      session.transcript[idx],
      delta,
      thinking: asThink,
    );
    _emit();
  }

  @override
  void onToolMessage(String messageId) {
    _lastAssistantMessageId = messageId;
    _turnFirstId ??= messageId;
    if (!_voicePass) _turnCodingId ??= messageId;
  }

  @override
  void onTool({
    required String name,
    required String detail,
    required bool ok,
    bool pending = false,
    String callId = '',
  }) {
    waifuUpsertToolRow(
      session.transcript,
      name: name,
      detail: detail,
      ok: ok,
      pending: pending,
      callId: callId,
    );
    final idx = _ensureLiveAssistant(thinking: false);
    session.transcript[idx] = waifuWithToolChip(
      session.transcript[idx],
      WaifuToolChip(
        name: name,
        detail: detail,
        ok: ok,
        pending: pending,
        callId: callId,
      ),
    );
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
      var next = cur;
      if (start != null && cur.thinkingMs == 0) {
        next = next.copyWith(
          thinkingMs: DateTime.now().millisecondsSinceEpoch - start,
        );
      }
      if (_voicePass &&
          next.text.trim().isEmpty &&
          next.reasoning.trim().isNotEmpty) {
        next = next.copyWith(text: next.reasoning.trim());
      }
      session.transcript[idx] = next;
    }
    // Voice plugin starts a new OpenCode assistant after coding idle.
    _liveIndex = null;
    _voicePass = true;
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
    session.transcript.add(_stage.snag(message));
    _emit();
  }

  @override
  void onTokens({required int promptTokens, required int outputTokens}) {
    final used = promptTokens + outputTokens;
    if (used <= 0) return;
    session.tokensUsed = used;
    session.tokensFromApi = true;
    _emit();
  }

  Future<void> _replyPermission(OpenCodePermissionAsked ask) async {
    final client = seat.client;
    final id = seat.sessionId;
    if (client == null || id == null) return;
    String response;
    if (session.mode == WaifuMode.yolo) {
      response = 'once';
    } else {
      final decision =
          await onAsk?.call(
            WaifuAskRequest(
              toolName: ask.permission,
              summary: ask.patterns.join('\n'),
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

  WaifuStage get _stage => WaifuStage.of(session);

  void _emit() => onChanged?.call();
}
