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

import 'dart:async';

import 'package:front_porch_ai/services/capability/capability.dart';
import 'package:front_porch_ai/services/reasoning_effort.dart';
import 'package:front_porch_ai/services/storage/settings/backend_settings.dart';

/// The available backend types. The former `pseudoRemote` (a local KoboldCpp
/// launched from a .kcpps preset) was folded into [kobold]: the local backend
/// launches a preset via `--config` when one is active, so it was a redundant
/// second path. Presets are now just a launch option of the Kobold backend.
enum BackendType { kobold, openRouter, omlx }

/// The mouth's stored backend name as a type. 'pseudoRemote' (legacy) falls
/// through to kobold — the preset now runs under the local Kobold backend.
/// The stored value is rewritten to 'kobold' by the migration in
/// BackendSettings.load().
BackendType backendTypeFromStored(String stored) => switch (stored) {
  'openRouter' => BackendType.openRouter,
  'omlx' => BackendType.omlx,
  _ => BackendType.kobold,
};

/// The worker picker's stored name as a type, or null when the worker is
/// off.
BackendType? workerBackendTypeFrom(String stored) => switch (stored) {
  'openRouter' => BackendType.openRouter,
  'omlx' => BackendType.omlx,
  'kobold' => BackendType.kobold,
  _ => null,
};

/// Whether [type] talks to an OpenAI-compatible API rather than the app's
/// own KoboldCpp.
bool isRemoteBackendType(BackendType type) =>
    type == BackendType.openRouter || type == BackendType.omlx;

/// Read the local chat template (oMLX jinja / LMS GGUF / Kobold GGUF) so
/// heretic `{% set enable_thinking = true %}` is known *before* the first
/// eval, not only after Settings opens the thinking chips. [openAiUrl] is
/// the address the mouth's OpenAI-compatible client is pointed at.
void kickLocalThinkingResolve(
  BackendType type, {
  required BackendSettings settings,
  required String openAiUrl,
}) {
  switch (type) {
    case BackendType.omlx:
      final model = settings.remoteModelName;
      if (model.isEmpty) return;
      if (ReasoningSupportResolver.instance.isResolved(model)) return;
      unawaited(
        ReasoningSupportResolver.instance.resolveOmlx(
          apiUrl: 'http://localhost:8000/v1',
          modelName: model,
          apiKey: settings.remoteApiKey,
        ),
      );
      return;
    case BackendType.openRouter:
      final model = settings.remoteModelName;
      if (model.isEmpty || !isLocalRemoteUrl(openAiUrl)) return;
      if (ReasoningSupportResolver.instance.isResolved(model)) return;
      unawaited(
        ReasoningSupportResolver.instance.resolveLmStudio(
          apiUrl: openAiUrl,
          modelName: model,
          apiKey: settings.remoteApiKey,
        ),
      );
      return;
    case BackendType.kobold:
      final path = settings.lastUsedModelPath;
      if (path == null || path.isEmpty) return;
      if (ReasoningSupportResolver.instance.isResolved(path)) return;
      unawaited(ReasoningSupportResolver.instance.resolveLocalGguf(path));
  }
}
