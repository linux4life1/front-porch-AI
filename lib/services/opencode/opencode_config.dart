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

import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/opencode/opencode_paths.dart';
import 'package:front_porch_ai/services/opencode/opencode_voice_plugin.dart';

/// OpenCode 1.18.30 custom OpenAI-compatible adapter. Without this npm
/// field a `porch` provider is ignored (models.dev has no such catalog).
const kOpenCodeCompatibleNpm = '@ai-sdk/openai-compatible';

/// Isolated provider id. Model slot is always `current`; the live API id
/// is `models.current.id` so OpenRouter-style slashes stay one token.
const kOpenCodePorchProvider = 'porch';
const kOpenCodePorchModelSlot = 'current';

/// Isolated OpenCode config. Model is Porch's current OpenAI-compatible
/// backend (oMLX, OpenRouter, or Nano-GPT). Default agent is `waifu`.
/// Beside opencode.json, not config/plugins/ — that folder is auto-loaded
/// and listing the same file in `plugin` would run wrap-up twice.
String openCodeVoicePluginPath(OpenCodeCloset closet) =>
    p.join(closet.configDir, 'waifu-voice.js');

String openCodeVoicePluginSpec(OpenCodeCloset closet) =>
    Uri.file(openCodeVoicePluginPath(closet)).toString();

String openCodeVoicePluginStalePath(OpenCodeCloset closet) =>
    p.join(closet.configDir, 'plugins', 'waifu-voice.js');

/// Writes the voice plugin. True when serve must restart to load it.
Future<bool> writeOpenCodeVoicePluginFile(OpenCodeCloset closet) async {
  final file = File(openCodeVoicePluginPath(closet));
  await file.parent.create(recursive: true);
  final previous = await file.exists() ? await file.readAsString() : '';
  if (previous != kWaifuVoicePluginSource) {
    await file.writeAsString(kWaifuVoicePluginSource);
  }
  final stale = File(openCodeVoicePluginStalePath(closet));
  var removedStale = false;
  if (await stale.exists()) {
    await stale.delete();
    removedStale = true;
  }
  return previous != kWaifuVoicePluginSource || removedStale;
}

Map<String, dynamic> openCodeVoicePermissionMap() {
  return {
    'read': 'deny',
    'edit': 'deny',
    'glob': 'deny',
    'grep': 'deny',
    'list': 'deny',
    'todowrite': 'deny',
    'skill': 'deny',
    'bash': 'deny',
    'external_directory': 'deny',
  };
}

Map<String, dynamic> buildOpenCodeConfigMap({
  required String agentPrompt,
  required String baseUrl,
  required String apiKey,
  required String modelId,
  required Map<String, dynamic> permission,
  String defaultAgent = 'waifu',
  Map<String, dynamic>? mcp,
  String? voicePrompt,
  String? pluginPath,
}) {
  final slot = modelId.isEmpty ? kOpenCodePorchModelSlot : modelId;
  final voice = openCodeVoicePermissionMap();
  final porchModel = '$kOpenCodePorchProvider/$slot';
  return {
    '\$schema': 'https://opencode.ai/config.json',
    'autoupdate': false,
    'share': 'disabled',
    'plugin': [if (pluginPath != null && pluginPath.isNotEmpty) pluginPath],
    'default_agent': defaultAgent,
    // Catalog key IS the API model id so oMLX loads it the same way
    // regular chat does (POST /v1/chat/completions model=<id>).
    'model': porchModel,
    'enabled_providers': [kOpenCodePorchProvider],
    'provider': {
      kOpenCodePorchProvider: {
        'npm': kOpenCodeCompatibleNpm,
        'name': 'Front Porch',
        'options': {'baseURL': baseUrl, 'apiKey': apiKey},
        'models': {
          slot: {'id': slot, 'name': slot, 'tool_call': true},
        },
      },
    },
    'agent': {
      'waifu': {
        'description': 'Sit-down coworker',
        'mode': 'primary',
        'model': porchModel,
        'prompt': agentPrompt,
        'permission': permission,
      },
      'plan': {
        'mode': 'primary',
        'model': porchModel,
        'prompt': agentPrompt,
        'permission': permission,
      },
      if (voicePrompt != null && voicePrompt.isNotEmpty)
        'voice': {
          'description': 'In-character wrap-up after tools',
          'mode': 'primary',
          'model': porchModel,
          'prompt': voicePrompt,
          'permission': voice,
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
