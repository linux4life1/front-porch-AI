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

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/remote_provider.dart';

/// Apply a provider-bar tap: backend + named URL, restore that host's
/// key, and blank the live model so a leftover id cannot ride the new
/// host. oMLX does not write [remoteApiUrl] so OpenRouter/Nano stay
/// parked. Custom clears a named URL so the bar does not keep
/// highlighting OpenRouter.
Future<void> applyRemoteProvider({
  required RemoteProviderKind kind,
  required StorageService storage,
  required LLMProvider llm,
  TextEditingController? urlController,
  TextEditingController? keyController,
  TextEditingController? modelController,
}) async {
  final current = resolveRemoteProviderKind(
    backendType: storage.backendSettings.backendType,
    url: storage.backendSettings.remoteApiUrl,
  );
  if (current == kind) return;

  final backend = switch (kind) {
    RemoteProviderKind.kobold => BackendType.kobold,
    RemoteProviderKind.omlx => BackendType.omlx,
    _ => BackendType.openRouter,
  };
  await llm.setActiveBackend(backend);

  if (kind == RemoteProviderKind.custom) {
    await storage.backendSettings.setRemoteApiUrl('');
  } else if (kind != RemoteProviderKind.kobold &&
      kind != RemoteProviderKind.omlx) {
    final url = urlForRemoteProvider(kind);
    if (url != null && storage.backendSettings.remoteApiUrl != url) {
      await storage.backendSettings.setRemoteApiUrl(url);
    }
  }

  urlController?.text = storage.backendSettings.remoteApiUrl;
  keyController?.text = storage.backendSettings.remoteApiKey;
  modelController?.text = storage.backendSettings.remoteModelName;
}
