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

import 'package:http/http.dart' as http;

import 'package:front_porch_ai/services/live_gen_progress.dart';
import 'package:front_porch_ai/services/llm_provider/backend_type.dart';
import 'package:front_porch_ai/services/lmstudio_log_streamer.dart';
import 'package:front_porch_ai/services/omlx_status_poller.dart';
import 'package:front_porch_ai/services/worker_backend.dart';

/// Live generation status sources for the non-Kobold backends (truthful
/// status bar). The oMLX poller only issues HTTP while [isGenerationActive]
/// says a chat generation is running, and the LM Studio log stream only
/// spawns for a localhost OpenAI backend with LM Studio's CLI present.
class LiveStatusSources {
  LiveStatusSources({required bool Function() isGenerationActive})
    : _omlx = OmlxStatusPoller(isActive: isGenerationActive);

  final OmlxStatusPoller _omlx;
  final LmStudioLogStreamer _lmStudio = LmStudioLogStreamer();

  /// The live progress source for [active], or null when none can exist
  /// (plain remote APIs — providers expose no prefill data). [kobold] is the
  /// app's own engine's.
  LiveGenProgress? progressFor(
    BackendType active, {
    required LiveGenProgress? kobold,
  }) => switch (active) {
    BackendType.kobold => kobold,
    BackendType.omlx => _omlx.progress,
    // LM Studio presents as an OpenAI backend on localhost; its runtime
    // log is only attachable when its CLI exists on this machine.
    BackendType.openRouter => _lmStudio.isRunning ? _lmStudio.progress : null,
  };

  bool get omlxStarted => _omlx.isStarted;

  /// Start/stop each source for the [active] mouth. [runOmlx]: the oMLX
  /// poller runs, against the mouth's [mouthUrl] when oMLX is the mouth and
  /// otherwise the helper's oMLX address from [workerUrl].
  void sync({
    required BackendType active,
    required bool runOmlx,
    required String mouthUrl,
    required String workerUrl,
  }) {
    if (runOmlx) {
      _omlx.start(
        active == BackendType.omlx
            ? mouthUrl
            : resolvedLaneApiUrl('omlx', workerUrl),
      );
    } else {
      _omlx.stop();
    }
    final isLocalOpenAi =
        active == BackendType.openRouter &&
        (mouthUrl.contains('localhost') || mouthUrl.contains('127.0.0.1'));
    if (isLocalOpenAi) {
      // Only attach to servers that really ARE LM Studio: its /api/v0/models
      // endpoint is the same signature the vision resolver uses. Without
      // this check, `lms log stream` could spawn against someone else's
      // local OpenAI server (llama.cpp, text-gen-webui) and — worse — wake
      // LM Studio's background service uninvited.
      _startLmStudioIfConfirmed(mouthUrl);
    } else {
      _lmStudio.stop();
    }
  }

  void stop() {
    _omlx.stop();
    _lmStudio.stop();
  }

  Future<void> _startLmStudioIfConfirmed(String apiUrl) async {
    if (_lmStudio.isRunning) return;
    if (LmStudioLogStreamer.lmsBinaryPath() == null) return;
    try {
      final base = apiUrl.replaceFirst(RegExp(r'/v1/?$'), '');
      final resp = await http
          .get(Uri.parse('$base/api/v0/models'))
          .timeout(const Duration(seconds: 2));
      if (resp.statusCode == 200) {
        await _lmStudio.start();
      }
    } catch (_) {
      // Not LM Studio (or not up) — stay detached; a later backend switch
      // re-probes.
    }
  }
}
