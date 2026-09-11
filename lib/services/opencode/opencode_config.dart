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

import 'package:front_porch_ai/services/opencode/opencode_paths.dart';

/// OpenCode 1.18.30 custom OpenAI-compatible adapter. Without this npm
/// field a `porch` provider is ignored (models.dev has no such catalog).
const kOpenCodeCompatibleNpm = '@ai-sdk/openai-compatible';

/// Isolated provider id. Model slot is always `current`; the live API id
/// is `models.current.id` so OpenRouter-style slashes stay one token.
const kOpenCodePorchProvider = 'porch';
const kOpenCodePorchModelSlot = 'current';

/// Isolated OpenCode config. Model is Porch's current OpenAI-compatible
/// backend (oMLX, OpenRouter, or Nano-GPT). Default agent is `waifu`.
Map<String, dynamic> buildOpenCodeConfigMap({
  required String agentPrompt,
  required String baseUrl,
  required String apiKey,
  required String modelId,
  required Map<String, dynamic> permission,
  String defaultAgent = 'waifu',
  Map<String, dynamic>? mcp,
}) {
  final slot = modelId.isEmpty ? kOpenCodePorchModelSlot : modelId;
  return {
    '\$schema': 'https://opencode.ai/config.json',
    'autoupdate': false,
    'share': 'disabled',
    'plugin': <String>[],
    'default_agent': defaultAgent,
    'model': '$kOpenCodePorchProvider/$kOpenCodePorchModelSlot',
    'enabled_providers': [kOpenCodePorchProvider],
    'provider': {
      kOpenCodePorchProvider: {
        'npm': kOpenCodeCompatibleNpm,
        'name': 'Front Porch',
        'options': {'baseURL': baseUrl, 'apiKey': apiKey},
        'models': {
          kOpenCodePorchModelSlot: {
            'id': slot,
            'name': slot,
            'tool_call': true,
          },
        },
      },
    },
    'agent': {
      'waifu': {
        'description': 'Sit-down coworker',
        'mode': 'primary',
        'prompt': agentPrompt,
        'permission': permission,
      },
      'plan': {
        'mode': 'primary',
        'prompt': agentPrompt,
        'permission': permission,
      },
    },
    'permission': permission,
    if (mcp != null && mcp.isNotEmpty) 'mcp': mcp,
  };
}

Future<void> writeOpenCodeConfigFile(
  OpenCodeCloset closet,
  Map<String, dynamic> config,
) async {
  await closet.ensureLayout();
  await File(
    closet.configFilePath,
  ).writeAsString(const JsonEncoder.withIndent('  ').convert(config));
}

Map<String, dynamic> openCodePermissionMap({
  required bool folderJail,
  required bool yolo,
}) {
  final askOrAllow = yolo ? 'allow' : 'ask';
  return {
    'read': askOrAllow,
    'edit': askOrAllow,
    'glob': askOrAllow,
    'grep': askOrAllow,
    'list': askOrAllow,
    'todowrite': askOrAllow,
    'skill': askOrAllow,
    'bash': {
      '*': askOrAllow,
      'rm -rf *': 'deny',
      'git push --force*': 'deny',
      'git reset --hard*': 'deny',
    },
    'external_directory': folderJail ? 'deny' : askOrAllow,
  };
}
