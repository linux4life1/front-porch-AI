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

import 'remote_api_key_vault.dart';

/// First-class generation host in Model Settings / Backend.
enum RemoteProviderKind { kobold, openRouter, nanoGpt, lmStudio, omlx, custom }

/// Canonical URL for a named host. Null for KoboldCpp (not a URL) and Custom
/// (user types one). oMLX has a URL for the model vault slot but switching
/// to oMLX must not overwrite the saved OpenRouter/Nano URL.
String? urlForRemoteProvider(RemoteProviderKind kind) => switch (kind) {
  RemoteProviderKind.openRouter => kOpenRouterApiV1,
  RemoteProviderKind.nanoGpt => kNanoGptApiV1,
  RemoteProviderKind.lmStudio => kLmStudioApiV1,
  RemoteProviderKind.omlx => kOmlxApiV1,
  RemoteProviderKind.kobold || RemoteProviderKind.custom => null,
};

RemoteProviderKind resolveRemoteProviderKind({
  required String backendType,
  required String url,
}) {
  if (backendType == 'kobold') return RemoteProviderKind.kobold;
  if (backendType == 'omlx') return RemoteProviderKind.omlx;
  if (remoteApiUrlIsOpenRouter(url)) return RemoteProviderKind.openRouter;
  if (remoteApiUrlIsNanoGpt(url)) return RemoteProviderKind.nanoGpt;
  if (remoteApiUrlIsLmStudio(url)) return RemoteProviderKind.lmStudio;
  return RemoteProviderKind.custom;
}

bool remoteProviderNeedsApiKey(RemoteProviderKind kind) => switch (kind) {
  RemoteProviderKind.openRouter ||
  RemoteProviderKind.nanoGpt ||
  RemoteProviderKind.custom => true,
  RemoteProviderKind.kobold ||
  RemoteProviderKind.lmStudio ||
  RemoteProviderKind.omlx => false,
};

bool remoteProviderShowsUrlField(RemoteProviderKind kind) =>
    kind == RemoteProviderKind.custom;
