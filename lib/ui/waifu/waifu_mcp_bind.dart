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

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';

/// Character-chat MCP servers are gone. Kept so older call sites compile.
Map<String, dynamic> openCodeMcpFromServers(Iterable<Object> _) => const {};

/// Points OpenCode at the Porch tools adapter when opt-in and cards exist.
Future<Map<String, dynamic>> waifuOpenCodeMcpMap(
  BuildContext? context, {
  required bool optIn,
  Directory? toolsDir,
  PorchToolsMcpHost? host,
}) {
  if (!optIn) return Future.value(const {});
  final dir = toolsDir ?? _toolsDirOf(context);
  if (dir == null) return Future.value(const {});
  return buildPorchToolsMcpMap(optIn: true, toolsDir: dir, host: host);
}

int waifuLoadedToolCardCount(Directory? toolsDir) {
  if (toolsDir == null) return 0;
  return loadUserToolCards(toolsDir).length;
}

Directory? _toolsDirOf(BuildContext? context) {
  if (context == null) return null;
  try {
    return Provider.of<StorageService>(context, listen: false).toolsDir;
  } catch (_) {
    return null;
  }
}
