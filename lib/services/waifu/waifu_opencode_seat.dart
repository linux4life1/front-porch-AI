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

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/waifu/waifu_coworker_prompt.dart';
import 'package:front_porch_ai/services/waifu/waifu_jail.dart';
import 'package:front_porch_ai/services/waifu/waifu_opencode.dart';
import 'package:front_porch_ai/services/waifu/waifu_session.dart';
import 'package:front_porch_ai/services/waifu/waifu_todos.dart';
import 'package:front_porch_ai/services/waifu/waifu_tools_mcp.dart';

/// What the running serve was started with. Prompts, permission maps, MCP
/// servers and plugins load only at serve start, so a change to any of
/// these restarts the serve. Plan/Build/Yolo is not here: both agents are
/// always written and Yolo is answered in Dart. [persona] carries the card
/// and today's date, so an edited card or a new day lands on the next turn.
class WaifuSeatSignature {
  const WaifuSeatSignature({
    required this.backend,
    required this.pathMode,
    required this.mcpOptIn,
    required this.persona,
  });

  final OpenCodePorchBackend backend;
  final WaifuPathMode pathMode;
  final bool mcpOptIn;
  final String persona;

  bool sameAs(WaifuSeatSignature other) =>
      openCodeBackendSame(backend, other.backend) &&
      pathMode == other.pathMode &&
      mcpOptIn == other.mcpOptIn &&
      persona == other.persona;
}

/// The harness's connection to managed OpenCode: one client, one OpenCode
/// session, and the signature the serve was started with.
class WaifuOpenCodeSeat {
  WaifuOpenCodeSeat({
    required this.session,
    this.manager,
    OpenCodeClient? client,
    String? sessionId,
    OpenCodePorchBackend? backend,
    this.backendOf,
    this.mcpConfigOf,
    this.skillsDirOf,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       _client = client,
       _sessionId = sessionId,
       _backend = backend {
    if (backend != null) _seated = _signatureFor(backend);
  }

  final WaifuSession session;
  final OpenCodeManager? manager;
  final OpenCodePorchBackend? Function()? backendOf;
  final FutureOr<Map<String, dynamic>> Function()? mcpConfigOf;
  final Directory? Function()? skillsDirOf;
  final OpenCodePorchBackend? _backend;
  final DateTime Function() _clock;

  OpenCodeClient? _client;
  String? _sessionId;
  WaifuSeatSignature? _seated;

  OpenCodeClient? get client => _client;
  String? get sessionId => _sessionId;

  OpenCodePorchBackend? get _liveBackend => backendOf?.call() ?? _backend;

  /// The model id OpenCode's porch provider was given for this backend.
  String get modelSlot {
    final id = _liveBackend?.modelId ?? _seated?.backend.modelId ?? '';
    return id.isEmpty ? kOpenCodePorchModelSlot : id;
  }

  /// True when the next turn would restart the serve to pick up a change.
  bool get needsReseat {
    final seated = _seated;
    final back = _liveBackend;
    if (seated == null || back == null) return false;
    return !_signatureFor(back).sameAs(seated);
  }

  /// The serve went away. The next [ensure] sits down again and resumes.
  void drop() {
    _client = null;
    _sessionId = null;
    _seated = null;
  }

  /// A client on a live session whose serve matches the current settings.
  /// Restarts the serve when they changed; the OpenCode session resumes.
  Future<OpenCodeClient?> ensure() async {
    final back = _liveBackend;
    final mgr = manager;
    final client = _client;
    final sid = _sessionId;
    if (client != null && sid != null && sid.isNotEmpty) {
      if (mgr == null) return client;
      final reseat =
          needsReseat || await writeOpenCodeVoicePluginFile(mgr.closet);
      if (!reseat) return client;
      await mgr.stop();
      drop();
    }
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
      mcp: await porchToolsMcpForSitDown(
        optIn: session.mcpOptIn,
        mcpConfigOf: mcpConfigOf,
      ),
      skillsDir: skillsDirOf?.call(),
      resumeSessionId: session.openCodeSessionId,
    );
    _sessionId = info.id;
    session.openCodeSessionId = info.id;
    _seated = _signatureFor(back);
    _client ??= OpenCodeClient(
      baseUri: mgr.baseUri,
      directory: session.folderRoot,
    );
    await waifuLoadTodos(session.folderRoot, session.todos);
    return _client;
  }

  WaifuSeatSignature _signatureFor(OpenCodePorchBackend backend) =>
      WaifuSeatSignature(
        backend: backend,
        pathMode: session.pathMode,
        mcpOptIn: session.mcpOptIn,
        persona: buildWaifuCardPersona(session.coworker, now: _clock()),
      );
}
