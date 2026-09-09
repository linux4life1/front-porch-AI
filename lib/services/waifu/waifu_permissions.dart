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

import 'package:front_porch_ai/services/waifu/waifu_ask_why.dart';
import 'package:front_porch_ai/services/waifu/waifu_call.dart';
import 'package:front_porch_ai/services/waifu/waifu_deny.dart';
import 'package:front_porch_ai/services/waifu/waifu_jail.dart';
import 'package:front_porch_ai/services/waifu/waifu_plan.dart';
import 'package:front_porch_ai/services/waifu/waifu_sit_down.dart';
import 'package:front_porch_ai/services/waifu/waifu_tools.dart';

export 'package:front_porch_ai/services/waifu/waifu_call.dart';
export 'package:front_porch_ai/services/waifu/waifu_deny.dart';

enum WaifuAskDecision { allowOnce, allowAlways, deny }

class WaifuAskRequest {
  const WaifuAskRequest({
    required this.toolName,
    required this.summary,
    this.why = '',
    this.doomLoop = false,
  });

  final String toolName;
  final String summary;
  final String why;
  final bool doomLoop;
}

typedef WaifuAskFn = Future<WaifuAskDecision> Function(WaifuAskRequest request);

class _WaifuAlways {
  bool on = false;
}

/// Plan / Build / Yolo plus doom-loop and Always-this-session.
/// Hard floor lives in [waifu_deny.dart] — Yolo does not skip it.
class WaifuPermissions {
  WaifuPermissions({
    this.mode = WaifuMode.build,
    this.workingDirectory,
    this.pathMode = WaifuPathMode.folderJail,
  }) : _always = _WaifuAlways();

  WaifuPermissions._share({
    required this.mode,
    this.workingDirectory,
    this.pathMode = WaifuPathMode.folderJail,
    required _WaifuAlways always,
  }) : _always = always;

  WaifuMode mode;
  String? workingDirectory;
  WaifuPathMode pathMode;
  final _WaifuAlways _always;
  final _counts = <String, int>{};

  WaifuPermissions fork({required WaifuMode mode}) => WaifuPermissions._share(
    mode: mode,
    workingDirectory: workingDirectory,
    pathMode: pathMode,
    always: _always,
  );

  String fingerprint(String name, Map<String, dynamic> args) =>
      '${canonicalWaifuToolName(name)}:${jsonEncode(args)}';

  WaifuDecision decide(WaifuCall call, {WaifuPathMode? pathMode}) {
    final scope = pathMode ?? this.pathMode;
    final floor = _hardFloor(call);
    if (floor != null) return WaifuDecision.deny(floor);
    if (mode == WaifuMode.plan) {
      final plan = _planGate(call);
      if (plan != null) return WaifuDecision.deny(plan);
      return const WaifuDecision.allow();
    }
    if (!call.mutates) return const WaifuDecision.allow();
    if (isDoom(call.name, call.args)) return const WaifuDecision.ask();
    if (_always.on) return const WaifuDecision.allow();
    if (mode != WaifuMode.build) return const WaifuDecision.allow();
    if (call.name == kWaifuToolTodoWrite) return const WaifuDecision.allow();
    if (_fileToolOnPorch(call, scope)) return const WaifuDecision.allow();
    return const WaifuDecision.ask();
  }

  String? _hardFloor(WaifuCall call) {
    final path = call.path;
    if (path != null && waifuIsProtectedSecretPath(path)) {
      return 'denied: .env, .ssh, and .aws secrets stay off the workbench';
    }
    if (path != null &&
        (call.name == kWaifuToolWrite ||
            call.name == kWaifuToolEdit ||
            call.name == kWaifuToolApplyPatch) &&
        waifuIsCriticalSystemMutationPath(
          path,
          workingDirectory: workingDirectory,
        )) {
      return 'denied: direct writes to operating-system files are not allowed';
    }
    if (call.name == kWaifuToolBash) {
      return waifuDeniedCommand(
        call.command,
        workingDirectory: workingDirectory,
      );
    }
    return null;
  }

  String? _planGate(WaifuCall call) {
    if (!call.isLocal && call.mutates) {
      return 'plan mode cannot ${call.original}: switch to Build or Yolo '
          'to change files';
    }
    return waifuPlanMutationBlock(
      name: call.name,
      args: call.args,
      root: workingDirectory,
    );
  }

  String? hardBlock({
    required String name,
    required Map<String, dynamic> args,
    bool? mutates,
  }) {
    final decision = decide(WaifuCall.parse(name, args, mcpMutates: mutates));
    return decision.kind == WaifuDecisionKind.deny ? decision.reason : null;
  }

  bool isDoom(String name, Map<String, dynamic> args) =>
      (_counts[fingerprint(name, args)] ?? 0) >= 2;

  bool needsAsk({
    required String name,
    required Map<String, dynamic> args,
    bool? mutates,
  }) {
    return decide(WaifuCall.parse(name, args, mcpMutates: mutates)).kind ==
        WaifuDecisionKind.ask;
  }

  bool _fileToolOnPorch(WaifuCall call, WaifuPathMode scope) {
    if (call.name != kWaifuToolWrite &&
        call.name != kWaifuToolEdit &&
        call.name != kWaifuToolApplyPatch) {
      return false;
    }
    final path = call.path;
    final root = workingDirectory;
    if (path == null || root == null || root.isEmpty) return false;
    return WaifuJail.resolve(root, path, pathMode: scope).ok;
  }

  String whyFor({
    required String name,
    required Map<String, dynamic> args,
    bool doomLoop = false,
  }) => waifuAskWhy(name: name, args: args, doomLoop: doomLoop);

  void record({required String name, required Map<String, dynamic> args}) {
    final fp = fingerprint(name, args);
    _counts[fp] = (_counts[fp] ?? 0) + 1;
  }

  void allowAlways() => _always.on = true;

  String summaryFor(String name, Map<String, dynamic> args) {
    final path = waifuToolPathArg(args);
    if (path != null) return path;
    final cmd = args['command']?.toString() ?? args['cmd']?.toString();
    if (cmd != null && cmd.isNotEmpty) return cmd;
    return canonicalWaifuToolName(name);
  }
}
