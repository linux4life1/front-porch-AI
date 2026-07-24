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

import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';

/// The ONE place that knows how to reach the active image backend and list
/// its models — shared by the Image Studio settings tab and the creators'
/// engine strip, so the "which URL, which fetch" dispatch can't fork.

/// The URL the active LOCAL backend is probed and listed at, straight from
/// the persisted settings. Empty when the backend has no address configured,
/// and for the remote backend (which is keyed by API URL + key, not probed).
String backendProbeUrl(StorageService st) {
  switch (ImageGenBackend.fromKey(st.imageGenBackend)) {
    case ImageGenBackend.drawThings:
      final host = st.drawThingsGrpcHost;
      return host.isEmpty ? '' : '$host:${st.drawThingsGrpcPort}';
    case ImageGenBackend.comfyUi:
      return st.comfyUiUrl;
    case ImageGenBackend.a1111:
      return st.localImageGenUrl;
    case ImageGenBackend.remote:
      return '';
  }
}

/// The active backend's model catalog as (value, label) dropdown options —
/// remote ids carry their display names, local checkpoints label themselves.
/// Returns [] when the backend isn't reachable/configured.
Future<List<({String value, String label})>> fetchBackendModelOptions(
  ImageGenService svc,
  StorageService st,
) async {
  final backend = ImageGenBackend.fromKey(st.imageGenBackend);
  if (backend == ImageGenBackend.remote) {
    final models = await svc.fetchImageModels();
    return [for (final m in models) (value: m.id, label: m.displayName)];
  }
  final url = backendProbeUrl(st);
  if (url.isEmpty) return const [];
  final names = switch (backend) {
    ImageGenBackend.drawThings => await svc.fetchDrawThingsModels(url),
    ImageGenBackend.comfyUi => await svc.fetchComfyModels(url),
    _ => await svc.fetchA1111Models(url),
  };
  return [for (final m in names) (value: m, label: m)];
}
