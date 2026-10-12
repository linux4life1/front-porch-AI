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

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/image_studio/backend_catalog.dart';

/// Connection test (local backends) + model catalog for the engine strip
/// and the edit-model row. Mirrors the Studio settings tab's auto-test.
class AvatarEngineProbe {
  AvatarEngineProbe({
    required this.storage,
    required this.imageGen,
    required this.isDisposed,
    required this.notify,
  });

  final StorageService storage;
  final ImageGenService imageGen;
  final bool Function() isDisposed;
  final VoidCallback notify;

  List<({String value, String label})> modelOptions = [];
  bool? connectionOk;
  bool testingConnection = false;
  bool loadingModels = false;

  Future<void> refresh() async {
    connectionOk = null;
    modelOptions = [];
    final backend = ImageGenBackend.fromKey(
      storage.imageGenSettings.imageGenBackend,
    );
    if (backend != ImageGenBackend.remote) {
      final url = backendProbeUrl(storage);
      if (url.isEmpty) {
        notify();
        return;
      }
      testingConnection = true;
      notify();
      final ok = await imageGen.testLocalConnection(url);
      if (isDisposed()) return;
      testingConnection = false;
      connectionOk = ok;
      if (!ok) {
        notify();
        return;
      }
    }
    loadingModels = true;
    notify();
    final options = await fetchBackendModelOptions(imageGen, storage);
    if (isDisposed()) return;
    modelOptions = options;
    loadingModels = false;
    notify();
  }
}
