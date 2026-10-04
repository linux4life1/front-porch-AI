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

import 'package:path/path.dart' as path;

import 'package:front_porch_ai/models/hardware_info.dart';
import 'package:front_porch_ai/services/gpu_backend_resolver.dart';
import 'package:front_porch_ai/services/kobold/kobold.dart';
import 'package:front_porch_ai/services/kobold_admin_swap.dart';
import 'package:front_porch_ai/services/kobold_binary_version.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/utils/gguf_parser.dart';
import 'package:front_porch_ai/utils/kobold_memory_rules.dart';

/// One way to launch KoboldCpp: from a config file the app writes.
///
/// The config is the user's preset or the app's own settings, made ready to
/// run (the model's full path, the chat template on, the vision file) and
/// written into the admin folder. KoboldCpp decides memory placement itself
/// unless the user chose a layer count. The command line carries only what
/// KoboldCpp will not take from a config: the port and the admin folder.
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
/// exactly what a launch would.
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
  final version = await KoboldBinaryVersion.read(path.dirname(executablePath));
  final config = await koboldLaunchMap(
    storage: storage,
    caps: KoboldCapabilities.forVersion(version.version),
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
    engineVersion: version.version,
    onNote: onNote,
  );
  final adminDir = koboldAdminDirFor(storage);
  final json = encodeKcpps(config);
  if (name == kStagedChatConfig) {
    final context = config['contextsize'];
    storage.backendSettings.setEngineContextSize(
      context is num ? context.toInt() : null,
    );
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
  );
}

/// The config a launch will run: the user's preset as it was written (see
/// [kcppsPresetLaunchMap]), or the app's own settings in the forms [caps]
/// says the installed KoboldCpp accepts.
Future<Map<String, dynamic>> koboldLaunchMap({
  required StorageService storage,
  KoboldCapabilities caps = KoboldCapabilities.current,
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
    final read = await readKoboldPreset(kcppsPath);
    // Sliding window left to KoboldCpp's default is run as written. When
    // the model has it, the log says what that default does.
    if (onNote != null &&
        kcppsLeavesSwaToKobold(read.raw) &&
        read.raw['nofastforward'] != true) {
      final loading = modelPath.isNotEmpty
          ? modelPath
          : kcppsModelOf(read.raw, engineDir: storage.binDir.path);
      if ((await _modelInfo(loading))?.hasSlidingWindow ?? false) {
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
  final gpu = await _backendFor(
    useVulkan: useVulkan,
    useCublas: useCublas,
    useMetal: useMetal,
    useRocm: useRocm,
    storage: storage,
    hardware: hardware,
    awaitHardware: awaitHardware,
  );
  final info = await _modelInfo(modelPath);
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
      contextMode: b.koboldContextMode,
      rocmFlashAttentionFailed: b.rocmFlashAttentionFailed,
    ),
    model: KoboldModelFacts(
      isMoe: info?.isMoe ?? false,
      hasSlidingWindow: info?.hasSlidingWindow ?? false,
      expertsShareGpuMemory: Platform.isMacOS,
      architecture: info?.architecture,
    ),
  );
  return kcppsMap(
    await _tunedForMachine(
      config,
      info: info,
      gpu: gpu,
      hardware: hardware,
      free: free,
      batchAutomatic: b.batchAutomatic,
      // MMQ only does anything with CUDA and the ROCm build.
      mmq: hardware == null || gpu.backend != KoboldGpuBackend.cuda
          ? null
          : b.mmqForLaunch(hardware.gpuName, engineVersion),
    ),
    caps: caps,
  );
}

/// Auto mode's own choices for this machine, made without asking: the
/// batch (unless one was chosen in Settings), smart cache slots that fit in
/// the free system memory with context shift to match, and MMQ as timed on
/// this card. Without the model's header or the machine's figures the
/// config is left as it was.
Future<KoboldLaunchConfig> _tunedForMachine(
  KoboldLaunchConfig config, {
  required GGUFModelInfo? info,
  required ({KoboldGpuBackend backend, int? gpuId, bool rocm}) gpu,
  required HardwareInfo? hardware,
  required FreeMemoryMb? free,
  required bool batchAutomatic,
  required bool? mmq,
}) async {
  final withMmq = mmq == null ? config : config.copyWith(mmq: mmq);
  if (info == null || hardware == null) return withMmq;
  final int fileSize;
  try {
    fileSize = await File(config.modelPath).length();
  } on FileSystemException {
    return withMmq;
  }
  // Apple hardware: one memory pool, every layer on the graphics side.
  final backend = hardware.hasMetal
      ? KoboldMemoryBackend.metal
      : gpu.backend == KoboldGpuBackend.vulkan
      ? KoboldMemoryBackend.vulkan
      : gpu.rocm
      ? KoboldMemoryBackend.rocm
      : KoboldMemoryBackend.cuda;
  final onCard = gpu.backend != KoboldGpuBackend.none || hardware.hasMetal;
  final tuning = koboldAutoTuning(
    KoboldFit(
      info: info,
      fileSizeBytes: fileSize,
      contextSize: config.contextSize,
      batchSize: config.batchSize,
      backend: backend,
      kvQuant: config.kvQuant,
      slidingWindowOn:
          config.contextMode == ContextManagementMode.slidingWindowAttention,
      flashAttention: config.flashAttention,
    ),
    KoboldMachine(
      backend: backend,
      totalGraphicsMb: onCard ? hardware.vramMb : 0,
      totalSystemMb: hardware.ramMb,
      freeGraphicsMb: onCard ? free?.graphics : 0,
      freeSystemMb: free?.system,
    ),
    // Nothing goes on a card without one: KoboldCpp's own batch.
    batchSize: !onCard
        ? kKoboldAutoBatches.first
        : batchAutomatic
        ? null
        : config.batchSize,
  );
  return withMmq.copyWith(
    batchSize: tuning.batchSize,
    smartCacheSlots: tuning.smartCache.asked,
    contextShift: tuning.smartCache.contextShift,
  );
}

/// The caller's backend switches, or the detected card when none was ever
/// chosen. Launch sites that read stored preferences pass all-false for a
/// user who never opened Settings; that used to mean CPU only.
Future<({KoboldGpuBackend backend, int? gpuId, bool rocm})> _backendFor({
  required bool useVulkan,
  required bool useCublas,
  required bool useMetal,
  required bool useRocm,
  required StorageService storage,
  required HardwareInfo? hardware,
  required Future<HardwareInfo?> Function()? awaitHardware,
}) async {
  final b = storage.backendSettings;
  var choice = useRocm
      ? GpuBackend.rocm
      : useCublas
      ? GpuBackend.cuda
      : useVulkan
      ? GpuBackend.vulkan
      : useMetal
      ? GpuBackend.metal
      : GpuBackend.cpu;
  if (choice == GpuBackend.cpu &&
      GpuBackendResolver.isAutomatic(
        userCublas: b.useCublas,
        userVulkan: b.useVulkan,
        userRocm: b.useRocm,
        userMetal: b.useMetal,
      )) {
    // Only this case needs to know the card. On a first run detection may
    // still be going; without the wait this launch would be CPU only.
    final hw = hardware ?? await awaitHardware?.call();
    choice = GpuBackendResolver.resolve(
      userCublas: null,
      userVulkan: null,
      userRocm: null,
      userMetal: null,
      hasCuda: hw?.hasCuda ?? false,
      vendor: hw?.vendor ?? 'Unknown',
    );
  }
  return switch (choice) {
    // An explicit card id: card 0 can be the integrated chip on a laptop.
    GpuBackend.cuda => (
      backend: KoboldGpuBackend.cuda,
      gpuId: b.gpuId,
      rocm: false,
    ),
    GpuBackend.rocm => (
      backend: KoboldGpuBackend.cuda,
      gpuId: b.gpuId,
      rocm: true,
    ),
    GpuBackend.vulkan => (
      backend: KoboldGpuBackend.vulkan,
      gpuId: null,
      rocm: false,
    ),
    // Metal is automatic on Apple hardware; CPU needs no setting either.
    GpuBackend.metal || GpuBackend.cpu => (
      backend: KoboldGpuBackend.none,
      gpuId: null,
      rocm: false,
    ),
  };
}

Future<GGUFModelInfo?> _modelInfo(String modelPath) async {
  if (modelPath.isEmpty) return null;
  try {
    return await GGUFParser.getModelArchitectureInfo(modelPath);
  } catch (_) {
    // An unreadable header is reported by the model file check; here it
    // only means "treat as an ordinary model".
    return null;
  }
}
