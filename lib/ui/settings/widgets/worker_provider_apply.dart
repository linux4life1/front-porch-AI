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
import 'package:front_porch_ai/services/storage/settings/remote_api_key_vault.dart';
import 'package:front_porch_ai/services/storage/settings/remote_provider.dart';

/// Write worker host fields only. Never calls [LLMProvider.setActiveBackend].
Future<void> applyWorkerProvider({
  required RemoteProviderKind? kind,
  required StorageService storage,
  TextEditingController? urlController,
  TextEditingController? modelController,
}) async {
  if (kind == null) {
    await storage.setWorkerBackendType('');
    return;
  }

  final backend = switch (kind) {
    RemoteProviderKind.kobold => 'kobold',
    RemoteProviderKind.omlx => 'omlx',
    _ => 'openRouter',
  };
  await storage.setWorkerBackendType(backend);

  if (kind == RemoteProviderKind.omlx) {
    await storage.setWorkerRemoteApiUrl(kOmlxApiV1);
  } else if (kind == RemoteProviderKind.custom) {
    if (storage.workerRemoteApiUrl.isNotEmpty &&
        resolveRemoteProviderKind(
              backendType: 'openRouter',
              url: storage.workerRemoteApiUrl,
            ) !=
            RemoteProviderKind.custom) {
      await storage.setWorkerRemoteApiUrl('');
    }
  } else if (kind != RemoteProviderKind.kobold) {
    final url = urlForRemoteProvider(kind);
    if (url != null && storage.workerRemoteApiUrl != url) {
      await storage.setWorkerRemoteApiUrl(url);
    }
  }

  urlController?.text = storage.workerRemoteApiUrl;
  modelController?.text = storage.workerRemoteModelName;
}
