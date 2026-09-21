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

import 'package:flutter/material.dart';

/// Character-chat MCP servers are gone. OpenCode still accepts an `mcp`
/// block; we send an empty one so Waifu Coder compiles without a Docker
/// MCP path.
Map<String, dynamic> openCodeMcpFromServers(Iterable<Object> _) => const {};

/// Empty when opt-in is off, and empty when it is on — there is no Porch
/// MCP catalog left to forward.
Map<String, dynamic> waifuOpenCodeMcpMap(
  BuildContext _, {
  required bool optIn,
}) {
  if (!optIn) return const {};
  return const {};
}
