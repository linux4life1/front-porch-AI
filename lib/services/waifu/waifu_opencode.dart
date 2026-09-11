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
import 'dart:typed_data';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/waifu/waifu_coworker_prompt.dart';
import 'package:front_porch_ai/services/waifu/waifu_jail.dart';
import 'package:front_porch_ai/services/waifu/waifu_sit_down.dart';

class OpenCodePorchBackend {
  const OpenCodePorchBackend({
    required this.baseUrl,
    required this.apiKey,
    required this.modelId,
  });

  final String baseUrl;
  final String apiKey;
  final String modelId;
}

OpenCodePorchBackend openCodeBackendFromProvider(LLMService svc) {
  if (svc is OpenRouterService) {
    return OpenCodePorchBackend(
      baseUrl: svc.apiUrl,
      apiKey: svc.apiKey.isEmpty ? 'x' : svc.apiKey,
      modelId: svc.modelName.isEmpty ? 'current' : svc.modelName,
    );
  }
  if (svc is KoboldService) {
    var url = svc.baseUrl;
    if (!url.endsWith('/v1')) url = '$url/v1';
    return OpenCodePorchBackend(baseUrl: url, apiKey: 'x', modelId: 'local');
  }
  throw StateError('No OpenAI-compatible backend for OpenCode');
}

String openCodeAgentForMode(WaifuMode mode) =>
    mode == WaifuMode.plan ? 'plan' : 'waifu';

List<Map<String, dynamic>> openCodePromptParts({
  required String text,
  Uint8List? imagePng,
}) {
  return [
    {'type': 'text', 'text': text},
    if (imagePng != null)
      {
        'type': 'file',
        'mime': 'image/png',
        'filename': 'photo.png',
        'url': 'data:image/png;base64,${base64Encode(imagePng)}',
      },
  ];
}

Future<void> writeWaifuOpenCodeConfig({
  required OpenCodeCloset closet,
  required CharacterCard coworker,
  required OpenCodePorchBackend backend,
  required WaifuPathMode pathMode,
  required WaifuMode mode,
  Map<String, dynamic>? mcp,
}) {
  return writeOpenCodeConfigFile(
    closet,
    buildOpenCodeConfigMap(
      agentPrompt: buildWaifuOpenCodeAgentPrompt(coworker),
      baseUrl: backend.baseUrl,
      apiKey: backend.apiKey,
      modelId: backend.modelId,
      permission: openCodePermissionMap(
        folderJail: pathMode == WaifuPathMode.folderJail,
        yolo: mode == WaifuMode.yolo,
      ),
      defaultAgent: 'waifu',
      mcp: mcp,
    ),
  );
}

/// Sit-down handshake: write isolated config, start our serve, open a session.
Future<OpenCodeSessionInfo> waifuOpenCodeSitDown({
  required OpenCodeManager manager,
  required OpenCodeClient Function(Uri base, String directory) clientOf,
  required CharacterCard coworker,
  required String folderRoot,
  required WaifuPathMode pathMode,
  required WaifuMode mode,
  required OpenCodePorchBackend backend,
  Map<String, dynamic>? mcp,
}) async {
  await writeWaifuOpenCodeConfig(
    closet: manager.closet,
    coworker: coworker,
    backend: backend,
    pathMode: pathMode,
    mode: mode,
    mcp: mcp,
  );
  await manager.start(workingDirectory: folderRoot);
  final client = clientOf(manager.baseUri, folderRoot);
  return client.createSession(
    title: coworker.name,
    agent: openCodeAgentForMode(mode),
  );
}
