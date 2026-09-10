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

import 'package:front_porch_ai/services/waifu/waifu_deny.dart';
import 'package:front_porch_ai/services/waifu/waifu_tools.dart';
import 'package:front_porch_ai/services/waifu/waifu_verify.dart';

enum WaifuDecisionKind { allow, ask, deny }

class WaifuDecision {
  const WaifuDecision.allow() : kind = WaifuDecisionKind.allow, reason = '';
  const WaifuDecision.ask() : kind = WaifuDecisionKind.ask, reason = '';
  const WaifuDecision.deny(this.reason) : kind = WaifuDecisionKind.deny;

  final WaifuDecisionKind kind;
  final String reason;
}

class WaifuCall {
  WaifuCall({
    required this.original,
    required this.name,
    required this.args,
    this.mcpMutates,
    this.verifyContext = const WaifuVerifyContext(),
  });

  final String original;
  final String name;
  final Map<String, dynamic> args;
  final bool? mcpMutates;
  final WaifuVerifyContext verifyContext;

  String? get path => waifuToolPathArg(args);
  String get command => (args['command'] ?? args['cmd'] ?? '').toString();
  String get contents =>
      (args['contents'] ?? args['content'] ?? args['text'] ?? '').toString();

  bool get isLocal {
    const local = {
      kWaifuToolRead,
      kWaifuToolEdit,
      kWaifuToolApplyPatch,
      kWaifuToolWrite,
      kWaifuToolGlob,
      kWaifuToolGrep,
      kWaifuToolBash,
      kWaifuToolTodoRead,
      kWaifuToolTodoWrite,
      kWaifuToolQuestion,
      kWaifuToolSkill,
      kWaifuToolSkillInstall,
      kWaifuToolWebFetch,
      kWaifuToolWebSearch,
      kWaifuToolTask,
      kWaifuToolWorkflow,
    };
    return local.contains(name);
  }

  bool get mutates {
    if (!isLocal) return mcpMutates != false;
    return waifuToolMutates(name, args: args, context: verifyContext);
  }

  static WaifuCall parse(
    String name,
    Map<String, dynamic> args, {
    bool? mcpMutates,
    WaifuVerifyContext verifyContext = const WaifuVerifyContext(),
  }) {
    return WaifuCall(
      original: name,
      name: canonicalWaifuToolName(name),
      args: waifuNormalizeToolArgs(name, args),
      mcpMutates: mcpMutates,
      verifyContext: verifyContext,
    );
  }
}

bool waifuToolMutates(
  String name, {
  Map<String, dynamic>? args,
  WaifuVerifyContext? context,
}) {
  switch (canonicalWaifuToolName(name)) {
    case kWaifuToolBash:
      final cmd =
          args?['command']?.toString() ?? args?['cmd']?.toString() ?? '';
      return waifuBashMutates(cmd, context: context);
    case kWaifuToolEdit:
    case kWaifuToolApplyPatch:
    case kWaifuToolWrite:
    case kWaifuToolTodoWrite:
    case kWaifuToolSkillInstall:
      return true;
    default:
      return false;
  }
}
