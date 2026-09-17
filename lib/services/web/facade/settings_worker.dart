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

import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/services.dart';

/// Additive worker-lane keys for Settings GET/POST. Older PWAs ignore them.
Map<String, dynamic> readWorkerSettings(
  StorageService storage,
  LLMProvider llm,
) {
  return {
    'workerBackend': storage.workerBackendType,
    'workerRemoteApiUrl': storage.workerRemoteApiUrl,
    'workerRemoteModelName': storage.workerRemoteModelName,
    'workerKoboldModelPath': storage.workerKoboldModelPath ?? '',
    'workerKoboldKcppsPath': storage.workerKoboldKcppsPath ?? '',
    'lastUsedModelPath': storage.lastUsedModelPath ?? '',
    'activeKcppsPath': storage.activeKcppsPath ?? '',
    'localKcpps': _localKcpps(storage),
    'workerEnabled': llm.workerService != null,
    'workerRefusedDualLocal': llm.workerRefusedDualLocal,
    'workerGpuSwapAvailable': llm.workerGpuSwapAvailable,
    'workerDualLocalMessage': llm.workerRefusedDualLocal
        ? kWorkerDualLocalMessage
        : '',
    'workerUnreadyMessage': llm.workerUnreadyMessage ?? '',
  };
}

Future<void> updateWorkerSettings({
  required StorageService storage,
  required Map<String, dynamic> body,
}) async {
  if (body.containsKey('workerBackend')) {
    await storage.setWorkerBackendType(body['workerBackend']?.toString() ?? '');
  }
  if (body.containsKey('workerRemoteApiUrl')) {
    await storage.setWorkerRemoteApiUrl(
      body['workerRemoteApiUrl']?.toString() ?? '',
    );
  }
  if (body.containsKey('workerRemoteModelName')) {
    await storage.setWorkerRemoteModelName(
      body['workerRemoteModelName']?.toString() ?? '',
    );
  }
  if (body.containsKey('workerKoboldModelPath')) {
    await storage.setWorkerKoboldModelPath(
      body['workerKoboldModelPath']?.toString(),
    );
  }
  if (body.containsKey('workerKoboldKcppsPath')) {
    await storage.setWorkerKoboldKcppsPath(
      body['workerKoboldKcppsPath']?.toString(),
    );
  }
  final workerKey = body['workerApiKey']?.toString();
  if (workerKey != null && workerKey.isNotEmpty) {
    await storage.setRemoteApiKeyFor(
      resolvedLaneApiUrl(storage.workerBackendType, storage.workerRemoteApiUrl),
      workerKey,
    );
  }
}

List<Map<String, String>> _localKcpps(StorageService storage) {
  try {
    final dir = storage.binDir;
    if (!dir.existsSync()) return const [];
    final files =
        dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.toLowerCase().endsWith('.kcpps'))
            .toList()
          ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
    return [
      for (final f in files) {'name': p.basename(f.path), 'path': f.path},
    ];
  } catch (_) {
    return const [];
  }
}
