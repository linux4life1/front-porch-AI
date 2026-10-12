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

import 'package:front_porch_ai/services/services.dart';

/// Fixed oMLX localhost endpoint, shared by the "Test Connection" probe and
/// the model picker's fetch — both force this URL when the oMLX backend is
/// active instead of whatever is in the API URL field.
const kModelSettingsOmlxUrl = 'http://localhost:8000/v1';

/// The URL a probe or model list asks: the fixed oMLX endpoint when oMLX is
/// [activeBackend], else the typed [apiUrl].
String remoteProbeUrl(BackendType activeBackend, String apiUrl) =>
    activeBackend == BackendType.omlx ? kModelSettingsOmlxUrl : apiUrl.trim();

/// Key for a probe of [apiUrl]: what is typed in the box, else what the
/// app itself would send there. The box stays blank on a SuperGrok
/// sign-in, so the typed text alone probes api.x.ai with no credentials.
String remoteProbeKey(
  StorageService storage, {
  required String typedKey,
  required String apiUrl,
}) {
  final typed = typedKey.trim();
  if (typed.isNotEmpty) return typed;
  return storage.backendSettings.remoteApiKeyFor(apiUrl);
}

/// Saves the remote API boxes. The URL is left alone while oMLX is
/// [activeBackend] (it uses a fixed localhost URL), and a blank key box
/// keeps the saved key.
void saveRemoteApiSettings(
  StorageService storage, {
  required BackendType activeBackend,
  required String apiUrl,
  required String apiKey,
  required String modelName,
}) {
  // Never overwrite the user's remote API URL when oMLX is active (it uses a fixed localhost URL)
  if (activeBackend != BackendType.omlx) {
    storage.backendSettings.setRemoteApiUrl(apiUrl.trim());
  }
  if (apiKey.trim().isNotEmpty) {
    storage.backendSettings.setRemoteApiKey(apiKey.trim());
  }
  storage.backendSettings.setRemoteModelName(modelName.trim());
}
