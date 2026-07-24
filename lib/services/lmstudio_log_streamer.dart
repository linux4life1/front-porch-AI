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
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/live_gen_progress.dart';

/// Live status source for a local LM Studio backend (truthful status bar).
///
/// LM Studio's REST API has no live per-request stats, but its bundled CLI
/// streams the llama.cpp runtime log, which prints exact prefill progress
/// per batch (captured empirically 2026-07-14):
///
///   `lms log stream --source runtime` →
///   `... prompt processing progress, n_tokens = 512, ... progress = 0.168754`
///
/// This service spawns that CLI (from LM Studio's standard install location,
/// `~/.lmstudio/bin/lms`, `lms.exe` on Windows) and feeds the lines into the
/// shared [LiveGenProgress]. Everything degrades silently: no binary, spawn
/// failure, or the process dying just means the status bar falls back to its
/// estimate labels — never an error the user sees.
class LmStudioLogStreamer {
  final LiveGenProgress progress = LiveGenProgress();

  Process? _process;
  bool _starting = false;

  /// LM Studio's CLI, shipped inside the user's home directory by the app
  /// itself — cross-platform per CLAUDE.md (HOME on Unix, USERPROFILE on
  /// Windows; never a hardcoded Unix path).
  static String? lmsBinaryPath() {
    final home = Platform.isWindows
        ? Platform.environment['USERPROFILE']
        : Platform.environment['HOME'];
    if (home == null || home.isEmpty) return null;
    final binary = Platform.isWindows ? 'lms.exe' : 'lms';
    final path = p.join(home, '.lmstudio', 'bin', binary);
    return File(path).existsSync() ? path : null;
  }

  bool get isRunning => _process != null;

  /// Spawn the log stream if LM Studio's CLI is present. Safe to call
  /// repeatedly (no-ops while running/starting).
  Future<void> start() async {
    if (_process != null || _starting) return;
    final lms = lmsBinaryPath();
    if (lms == null) return;
    _starting = true;
    try {
      final proc = await Process.start(
        lms,
        ['log', 'stream', '--source', 'runtime'],
        includeParentEnvironment: true,
      );
      _process = proc;
      proc.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen(progress.ingestLmStudioRuntimeLine);
      proc.stderr.drain<void>();
      proc.exitCode.then((code) {
        debugPrint('[LmStudioStatus] log stream exited ($code)');
        _process = null;
      });
      debugPrint('[LmStudioStatus] log stream attached (pid ${proc.pid})');
    } catch (e) {
      debugPrint('[LmStudioStatus] could not attach log stream: $e');
    } finally {
      _starting = false;
    }
  }

  void stop() {
    _process?.kill();
    _process = null;
    progress.reset();
  }
}
