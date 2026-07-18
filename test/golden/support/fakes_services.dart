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

// Additional service fakes for provider-backed page / dialog goldens.
//
// Each fake implements only the getters widgets read at build time; everything
// else delegates to noSuchMethod.

import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/models/download_task.dart';
import 'package:front_porch_ai/models/local_model_info.dart';
import 'package:front_porch_ai/services/download_manager.dart';
import 'package:front_porch_ai/services/hardware_service.dart';
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/model_manager.dart';
import 'package:front_porch_ai/services/voice_manager.dart';

/// [ModelManager] double. Exposes the getters [ModelManagerPage.build] reads
/// directly (localModels, modelsPath, downloadManager, customModelsPath).
/// [downloadManager] returns a real [DownloadManager] with an empty queue so
/// [DownloadQueuePanel] can read its list getters without IO.
class FakeModelManager extends ChangeNotifier implements ModelManager {
  FakeModelManager({
    List<LocalModelInfo>? localModels,
    this.modelsPath = '/models',
    this.statusMessage = '',
  }) : _localModels = localModels ?? const [];

  final List<LocalModelInfo> _localModels;

  @override
  final String modelsPath;
  @override
  final String statusMessage;

  @override
  List<LocalModelInfo> get localModels => _localModels;
  @override
  Map<String, DownloadTask> get downloadingFiles => const {};
  @override
  Set<String> get downloadedFilenames => const {};

  // A real DownloadManager with an empty queue supplies the DownloadQueuePanel
  // list getters without needing a separate fake hierarchy.
  final DownloadManager _downloadManager = DownloadManager(
    targetDir: Directory.systemTemp.path,
  );
  @override
  DownloadManager get downloadManager => _downloadManager;
  @override
  Future<void> refreshModels() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// [HardwareService] double. Seeds a deterministic [HardwareInfo] so
/// [ModelManagerPage] can display VRAM and GPU name without real detection.
class FakeHardwareService extends ChangeNotifier implements HardwareService {
  FakeHardwareService({HardwareInfo? hardwareInfo})
    : _hardwareInfo =
          hardwareInfo ??
          HardwareInfo(
            gpuName: 'NVIDIA GeForce RTX 4070',
            vramMb: 12288,
            ramMb: 32768,
            vendor: 'Nvidia',
            hasCuda: true,
          );

  final HardwareInfo _hardwareInfo;

  @override
  HardwareInfo? get hardwareInfo => _hardwareInfo;
  @override
  bool get isDetecting => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// [KoboldService] double for [KoboldLogDialog]. Exposes build-time reads:
/// [isRunning], [isStarting], [isReady], and [logs].
class FakeKoboldService extends ChangeNotifier implements KoboldService {
  @override
  bool get isRunning => false;
  @override
  bool get isStarting => false;
  @override
  bool get isReady => false;
  @override
  List<String> get logs => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// [VoiceManager] double for [VoiceBrowserDialog] and [TtsSettingsDialog].
/// [catalog] returns empty so the list shows an "empty" state.
/// [fetchCatalog] and [listInstalledVoices] are no-ops / return empty lists so
/// [_loadData] in [VoiceBrowserDialog] and [_loadInstalledVoices] in
/// [TtsSettingsDialog] complete without IO.
class FakeVoiceManager extends ChangeNotifier implements VoiceManager {
  @override
  List<PiperVoice> get catalog => const [];

  @override
  bool get isLoadingCatalog => false;

  @override
  Future<void> fetchCatalog() async {}

  @override
  Future<List<String>> listInstalledVoices() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// [ImageGenService] double for [ImageGenSettingsDialog] (via
/// [GenerationOptionsTab]). [fetchImageModels] returns an empty list so
/// [_fetchModels] completes without network access.
class FakeImageGenService extends ChangeNotifier implements ImageGenService {
  @override
  Future<List<ImageModelInfo>> fetchImageModels() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
