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

import 'package:flutter/foundation.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/gpu_backend_resolver.dart';
import 'package:front_porch_ai/services/kobold/kobold.dart';
import 'package:front_porch_ai/services/kobold_admin_swap.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/utils/utils.dart';
import 'package:path/path.dart' as p;

/// One way to launch KoboldCpp: from a config file the app writes.
///
/// The config is the user's preset or the app's own settings, made ready to
/// run (the model's full path, the chat template on, the vision file, the
/// listen address) and written into the admin folder. KoboldCpp decides
/// memory placement itself unless the user chose a layer count. The command
/// line carries only what KoboldCpp will not take from a config: the port
/// and the admin folder.
///
/// [gpuLayers] is used only when Settings has "set layers myself" on.
Future<List<String>> buildKoboldLaunchArgs({
  required StorageService storage,
  required String executablePath,
  required String modelPath,
  required String? kcppsPath,
  required String? mmprojPath,
  required int port,
  required int gpuLayers,
  required int contextSize,
  required bool useVulkan,
  required bool useCublas,
  required bool useMetal,
  required bool useRocm,
  HardwareInfo? hardware,
  Future<HardwareInfo?> Function()? awaitHardware,
  FreeMemoryMb? free,
  void Function(String note)? onNote,
  void Function(KoboldStagedRole staged)? onStaged,
}) async {
  final staged = await stageKoboldRole(
    storage: storage,
    executablePath: executablePath,
    name: kStagedChatConfig,
    modelPath: modelPath,
    kcppsPath: kcppsPath,
    mmprojPath: mmprojPath,
    gpuLayers: gpuLayers,
    contextSize: contextSize,
    useVulkan: useVulkan,
    useCublas: useCublas,
    useMetal: useMetal,
    useRocm: useRocm,
    hardware: hardware,
    awaitHardware: awaitHardware,
    free: free,
    onNote: onNote,
  );
  onStaged?.call(staged);
  final adminDir = koboldAdminDirFor(storage);
  return [
    '--config',
    staged.path,
    '--port',
    port.toString(),
    // In-process model swaps need --admin and an existing --admindir.
    if (adminDir.isNotEmpty) ...['--admin', '--admindir', adminDir],
  ];
}

/// Writes the config a role will run into the admin folder as [name]: the
/// chat model at launch, and each role (chat, the helper model, a story
/// job) before a swap. The same function for all of them, so a swap loads
/// exactly what a launch would. Every one names [kKoboldHost] as its
/// address and [kKoboldAdminUnloadTimeout] as its idle unload, over whatever
/// a preset said.
Future<KoboldStagedRole> stageKoboldRole({
  required StorageService storage,
  required String executablePath,
  required String name,
  required String modelPath,
  required String? kcppsPath,
  required String? mmprojPath,
  required int gpuLayers,
  required int contextSize,
  required bool useVulkan,
  required bool useCublas,
  required bool useMetal,
  required bool useRocm,
  HardwareInfo? hardware,
  Future<HardwareInfo?> Function()? awaitHardware,
  FreeMemoryMb? free,
  void Function(String note)? onNote,
}) async {
  final version = await KoboldBinaryVersion.versionFor(executablePath);
  final config = await koboldLaunchMap(
    storage: storage,
    modelPath: modelPath,
    kcppsPath: kcppsPath,
    mmprojPath: mmprojPath,
    gpuLayers: gpuLayers,
    contextSize: contextSize,
    useVulkan: useVulkan,
    useCublas: useCublas,
    useMetal: useMetal,
    useRocm: useRocm,
    hardware: hardware,
    awaitHardware: awaitHardware,
    free: free,
    engineVersion: version,
    onNote: onNote,
  );
  config['host'] = kKoboldHost;
  config['adminunloadtimeout'] = kKoboldAdminUnloadTimeout;
  final adminDir = koboldAdminDirFor(storage);
  final json = encodeKcpps(config);
  // Chat's prompts are held to the context its config names from the moment
  // it is staged. A config that names none runs the engine's own default,
  // which only the engine can say, so nothing is recorded then: the engine
  // is asked when a launch or a reload is confirmed, and staging, which is
  // not a load (a swap back to chat stages this config before every reply),
  // must not forget what it said.
  final context = koboldExpectedContext(config);
  if (name == kStagedChatConfig && context != null) {
    storage.backendSettings.setEngineContextSize(context);
  }
  final file = await stageKoboldConfig(
    adminDir.isNotEmpty ? adminDir : Directory.systemTemp.path,
    name,
    json,
  );
  return KoboldStagedRole(
    filename: name,
    path: file.path,
    // The content, not the name: a helper model set to the chat model's
    // own pair stages the same content and needs no reload.
    key: json,
    modelPath: kcppsModelOf(config),
    kcppsPath: kcppsPath ?? '',
    expectedModel: koboldExpectedModelName(config),
    contextSize: koboldExpectedContext(config),
  );
}

/// The config a launch will run: the user's preset as it was written (see
/// [kcppsPresetLaunchMap]), or the app's own settings.
Future<Map<String, dynamic>> koboldLaunchMap({
  required StorageService storage,
  required String modelPath,
  required String? kcppsPath,
  required String? mmprojPath,
  required int gpuLayers,
  required int contextSize,
  required bool useVulkan,
  required bool useCublas,
  required bool useMetal,
  required bool useRocm,
  HardwareInfo? hardware,
  Future<HardwareInfo?> Function()? awaitHardware,
  FreeMemoryMb? free,
  String? engineVersion,
  void Function(String note)? onNote,
}) async {
  // A missing vision file must never stop a launch.
  final mmproj =
      mmprojPath != null &&
          mmprojPath.isNotEmpty &&
          File(mmprojPath).existsSync()
      ? mmprojPath
      : '';

  if (kcppsPath != null) {
    // The engine runs the user's file, not the MMQ setting auto mode is
    // timing: its replies are not to be counted for it.
    storage.backendSettings.pauseMmqLearning();
    final read = await readKoboldPreset(kcppsPath);
    // Sliding window left to KoboldCpp's default is run as written. When
    // the model has it, the log says what that default does.
    if (onNote != null && kcppsSwaLeftToKobold(read.raw)) {
      final loading = modelPath.isNotEmpty
          ? modelPath
          : kcppsModelOf(read.raw, engineDir: storage.binDir.path);
      if ((await koboldModelHeader(loading))?.hasSlidingWindow ?? false) {
        onNote(kSwaLeftToKoboldNote);
      }
    }
    // The file as written, not the typed summary of it. What the launch
    // changes or notices (a pairing made safe, a forced fit that overrides
    // the preset's own layer count) goes to the log.
    return kcppsPresetLaunchMap(
      read.raw,
      modelPath: modelPath,
      mmprojPath: mmproj,
      onNote: onNote,
      flashAttentionOff:
          useRocm && storage.backendSettings.rocmFlashAttentionFailed,
    );
  }

  final b = storage.backendSettings;
  // The machine is what the backend was worked out from, which may be a card
  // the launch had to wait for: MMQ and the tuning below are for that one.
  final (:gpu, :machine) = await _backendFor(
    useVulkan: useVulkan,
    useCublas: useCublas,
    useMetal: useMetal,
    useRocm: useRocm,
    storage: storage,
    hardware: hardware,
    awaitHardware: awaitHardware,
  );
  // MMQ only does anything with CUDA and the ROCm build. A launch without it
  // ends the trial an earlier one began, so its replies are not counted.
  final bool? mmq;
  if (machine == null || gpu.backend != KoboldGpuBackend.cuda) {
    b.pauseMmqLearning();
    mmq = null;
  } else {
    mmq = b.mmqForLaunch(machine.gpuName, engineVersion);
  }
  final info = await koboldModelHeader(modelPath);
  final note = koboldFlashAttentionNote(
    backend: gpu.backend,
    rocm: gpu.rocm,
    architecture: info?.architecture,
    rocmFailedBefore: b.rocmFlashAttentionFailed,
  );
  if (note != null) onNote?.call(note);
  final config = koboldAppConfig(
    modelPath: modelPath,
    mmprojPath: mmproj,
    settings: KoboldAppSettings(
      contextSize: contextSize,
      batchSize: b.blasBatchSize,
      layersManual: b.gpuLayersManual,
      manualLayers: gpuLayers,
      backend: gpu.backend,
      gpuId: gpu.gpuId,
      rocm: gpu.rocm,
      flashAttention: b.flashAttentionEnabled,
      kvQuant: b.kvQuant,
      mlock: b.mlockEnabled,
      rocmFlashAttentionFailed: b.rocmFlashAttentionFailed,
    ),
    model: KoboldModelFacts(
      isMoe: info?.isMoe ?? false,
      expertsShareGpuMemory: gpu.unified,
      architecture: info?.architecture,
    ),
  );
  final tuned = await _tunedForMachine(
    config,
    info: info,
    gpu: gpu,
    hardware: machine,
    free: free,
    batchAutomatic: b.batchAutomatic,
    mmq: mmq,
    // The slot keeper looks after the chats unless it failed for this
    // model with this engine before.
    keeper: !b.keeperFailedFor(engineVersion, p.basename(modelPath)),
    onNote: onNote,
  );
  // An engine from 1.122 takes a logical batch apart from the physical one
  // chosen above; an older one reads the one field as the physical batch.
  return kcppsMap(
    KoboldBinaryVersion.splitsBatch(engineVersion)
        ? tuned.copyWith(logicalBatchSize: kKoboldLogicalBatch)
        : tuned,
  );
}

/// Auto mode's own choices for this machine, made without asking: the
/// batch (unless one was chosen in Settings), the chat cache, and MMQ as
/// timed on this card. For an ordinary model the app keeps the chats itself
/// (the slot keeper), so no smart cache is written and context shift stays
/// on; a model with recurrent layers, and one the keeper failed for, gets
/// smart cache slots that fit in the free system memory with context shift
/// to match. Without the model's header or the machine's figures the config
/// is left as it was.
Future<KoboldLaunchConfig> _tunedForMachine(
  KoboldLaunchConfig config, {
  required GGUFModelInfo? info,
  required KoboldBackendChoice gpu,
  required HardwareInfo? hardware,
  required FreeMemoryMb? free,
  required bool batchAutomatic,
  required bool? mmq,
  required bool keeper,
  void Function(String note)? onNote,
}) async {
  final withMmq = mmq == null ? config : config.copyWith(mmq: mmq);
  if (info == null || hardware == null) return withMmq;
  final int fileSize;
  try {
    fileSize = await File(config.modelPath).length();
  } on FileSystemException {
    return withMmq;
  }
  final tuning = koboldAutoTuning(
    KoboldFit(
      info: info,
      fileSizeBytes: fileSize,
      contextSize: config.contextSize,
      batchSize: config.batchSize,
      backend: gpu.memory,
      kvQuant: config.kvQuant,
      flashAttention: config.flashAttention,
    ),
    gpu.machineFor(hardware, free),
    batchSize: gpu.fixedBatch(
      automatic: batchAutomatic,
      chosen: config.batchSize,
    ),
  );
  if (!keeper && !tuning.recurrent) onNote?.call(kKeeperFailedNote);
  final cache = tuning.cacheSetting(keeper: keeper);
  return withMmq.copyWith(
    batchSize: tuning.batchSize,
    smartCacheSlots: cache.asked,
    contextShift: cache.contextShift,
  );
}

/// The backend this launch runs, by the rule every caller shares
/// ([koboldBackendFor]), and the machine it was worked out from: [hardware],
/// or the detection the launch waited for when only the automatic choice
/// needs it. A switch the caller passes as on counts as chosen; one passed
/// as off is as Settings has it, which is what tells "never chosen" from
/// "chosen off" (the callers collapse both to false).
Future<({KoboldBackendChoice gpu, HardwareInfo? machine})> _backendFor({
  required bool useVulkan,
  required bool useCublas,
  required bool useMetal,
  required bool useRocm,
  required StorageService storage,
  required HardwareInfo? hardware,
  required Future<HardwareInfo?> Function()? awaitHardware,
}) async {
  final b = storage.backendSettings;
  final cublas = useCublas ? true : b.useCublas;
  final vulkan = useVulkan ? true : b.useVulkan;
  final rocm = useRocm ? true : b.useRocm;
  final metal = useMetal ? true : b.useMetal;
  // Only the automatic choice needs to know the card. On a first run
  // detection may still be going; without the wait this launch would be CPU
  // only.
  final automatic = GpuBackendResolver.isAutomatic(
    userCublas: cublas,
    userVulkan: vulkan,
    userRocm: rocm,
    userMetal: metal,
  );
  final machine = hardware ?? (automatic ? await awaitHardware?.call() : null);
  final gpu = koboldBackendFor(
    hardware: machine,
    cublas: cublas,
    vulkan: vulkan,
    rocm: rocm,
    metal: metal,
    gpuId: b.gpuId,
  );
  return (gpu: gpu, machine: machine);
}

/// Model headers read for staging, with the size and time of the file each
/// came from. A swap stages its config before every call, and the header
/// (up to 16 MB, read and parsed) only changes when the file does.
final Map<String, ({int size, DateTime modified, GGUFModelInfo? info})>
_headersRead = {};

/// The header of the model at [modelPath], read once for each version of the
/// file. Null when it cannot be read, which callers treat as an ordinary
/// model.
Future<GGUFModelInfo?> koboldModelHeader(String modelPath) async {
  if (modelPath.isEmpty) return null;
  try {
    final stat = await File(modelPath).stat();
    final known = _headersRead[modelPath];
    if (known != null &&
        known.size == stat.size &&
        known.modified == stat.modified) {
      return known.info;
    }
    final info = await GGUFParser.getModelArchitectureInfo(modelPath);
    _headersRead[modelPath] = (
      size: stat.size,
      modified: stat.modified,
      info: info,
    );
    return info;
  } catch (e) {
    // An unreadable header is reported by the model file check; here it
    // only means "treat as an ordinary model".
    debugPrint('[Kobold] the model header could not be read: $e');
    return null;
  }
}
