// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Test double: real test/analyze commands don't run against a temp folder.

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';

class WaifuAnalyzeBash extends WaifuBash {
  WaifuAnalyzeBash(super.root, {this.pass = true, super.pathMode});

  final bool pass;

  @override
  Future<WaifuToolResult> run(Map<String, dynamic> args) async {
    final cmd = (args['command'] ?? args['cmd'] ?? '').toString();
    if (waifuLooksVerifyCommand(cmd)) {
      return WaifuToolResult(
        ok: pass,
        output: pass ? 'No issues found!' : 'error • slop at line 1',
      );
    }
    return super.run(args);
  }
}

class WaifuQueuedAnalyzeBash extends WaifuBash {
  WaifuQueuedAnalyzeBash(super.root, this.passes, {super.pathMode});

  final List<bool> passes;

  @override
  Future<WaifuToolResult> run(Map<String, dynamic> args) async {
    final cmd = (args['command'] ?? args['cmd'] ?? '').toString();
    if (waifuLooksVerifyCommand(cmd)) {
      final ok = passes.isEmpty ? false : passes.removeAt(0);
      return WaifuToolResult(
        ok: ok,
        output: ok ? 'No issues found!' : 'error • slop at line 1',
      );
    }
    return super.run(args);
  }
}

const kWaifuAnalyzeCall = LlmToolCall(
  name: 'bash',
  arguments: {'command': 'dart analyze'},
);
