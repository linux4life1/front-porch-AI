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

import 'package:path/path.dart' as path;

import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/worker_backend.dart';

/// "Main model · Qwen3 32B" / "Worker model · Gemma" — what each story lane
/// would run on right now, for the Engine step on desktop and web. The
/// worker label is null when no worker is set up.
({String main, String? worker}) storyLaneLabelsFor(
  StorageService storage,
  LLMProvider llm,
) {
  String name(String remote, String? local) {
    if (remote.isNotEmpty) return remote;
    if (local != null && local.isNotEmpty) {
      return path.basenameWithoutExtension(local);
    }
    return 'no model picked';
  }

  final settings = storage.backendSettings;
  final main = settings.backendType == 'kobold'
      ? name('', settings.lastUsedModelPath)
      : name(settings.remoteModelName, null);
  final worker = !llm.workerConfigured
      ? null
      : storage.workerBackendType == 'kobold'
      ? name('', storage.workerKoboldModelPath ?? settings.lastUsedModelPath)
      : name(storage.workerRemoteModelName, null);
  return (
    main: 'Main model · $main',
    worker: worker == null ? null : 'Worker model · $worker',
  );
}
