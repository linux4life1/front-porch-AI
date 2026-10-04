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

/// How KoboldCpp stores its attention cache. Smaller types save graphics
/// memory at some cost in quality.
enum KvQuant {
  f16('f16', '0', 1.0, 'None (f16): highest quality'),
  bf16('bf16', '3', 1.0, 'bf16: same size as f16, no saving'),
  q8_0('q8_0', '1', 0.53125, '8-bit (q8_0): about 50% smaller'),
  q5_1('q5_1', null, 0.375, '5-bit (q5_1): about 60% smaller'),
  q4_0('q4_0', '2', 0.28125, '4-bit (q4_0): about 75% smaller');

  const KvQuant(this.wire, this.legacyIndex, this.sizeFactor, this.label);

  /// The value KoboldCpp 1.112 and newer accept.
  final String wire;

  /// The index older builds used ("0".."3"). `q5_1` has none.
  final String? legacyIndex;

  /// Cache size relative to f16, exactly: these types store 32 values in
  /// 34, 24 and 18 bytes where f16 takes 64. Measured on a real engine:
  /// a 10,280 MiB f16 cache came out at 5461.25 as q8_0 and 2891.25 as
  /// q4_0.
  final double sizeFactor;
  final String label;

  /// Reads either form: "q8_0", "1", or the number 1.
  static KvQuant parse(Object? raw) {
    final s = raw?.toString().trim().toLowerCase() ?? '';
    for (final q in values) {
      if (q.wire == s || q.legacyIndex == s) return q;
    }
    return f16;
  }
}

/// The two safe ways to handle a chat longer than the context. Sliding
/// window with fast forward is deliberately not one of them: together they
/// degrade the model's output.
enum ContextManagementMode {
  /// Sliding window on, fast forward and context shift off. Less graphics
  /// memory; every reply reads the whole chat again.
  slidingWindowAttention,

  /// Sliding window off, fast forward and context shift on.
  fastForwardSmartCache,
}

enum KoboldGpuBackend { none, cuda, vulkan }

/// One KoboldCpp launch configuration: what a `.kcpps` file says, in the
/// terms this app manages. Keys the app does not manage ride along in
/// [extras] so a preset made in KoboldCpp's own launcher survives a round
/// trip untouched.
class KoboldLaunchConfig {
  const KoboldLaunchConfig({
    this.modelPath = '',
    this.contextSize = 16384,
    this.batchSize = 512,
    this.threads,
    this.gpuLayers = autoLayers,
    this.autofitPaddingMb,
    this.useMmap = true,
    this.useMlock = false,
    this.kvQuant = KvQuant.f16,
    this.flashAttention = true,
    this.backend = KoboldGpuBackend.none,
    this.gpuId,
    this.contextMode = ContextManagementMode.fastForwardSmartCache,
    this.smartCacheSlots = 0,
    this.jinja = true,
    this.mmprojPath = '',
    this.mmprojOnCpu = false,
    this.moeExpertsOnCpu = false,
    this.extras = const {},
  });

  /// KoboldCpp fits the model to the card itself.
  static const int autoLayers = -1;

  final String modelPath;
  final int contextSize;
  final int batchSize;

  /// Null leaves the thread count to KoboldCpp.
  final int? threads;

  /// [autoLayers], or a count the user chose.
  final int gpuLayers;

  /// Spare graphics memory automatic fitting keeps free. Null = its default.
  final int? autofitPaddingMb;
  final bool useMmap;
  final bool useMlock;
  final KvQuant kvQuant;
  final bool flashAttention;
  final KoboldGpuBackend backend;

  /// Which card. Null lets KoboldCpp choose.
  final int? gpuId;
  final ContextManagementMode contextMode;

  /// Chat snapshots kept in system memory. Only used with fast forward;
  /// 0 writes no setting.
  final int smartCacheSlots;
  final bool jinja;
  final String mmprojPath;
  final bool mmprojOnCpu;

  /// Keep a MoE model's expert weights in system memory. Only written with
  /// a manual layer count: automatic fitting and this setting cannot be
  /// combined in KoboldCpp.
  final bool moeExpertsOnCpu;
  final Map<String, dynamic> extras;

  bool get layersAreAutomatic => gpuLayers < 0;

  KoboldLaunchConfig copyWith({
    String? modelPath,
    int? contextSize,
    int? batchSize,
    int? gpuLayers,
    bool? useMlock,
    KvQuant? kvQuant,
    bool? flashAttention,
    KoboldGpuBackend? backend,
    int? gpuId,
    ContextManagementMode? contextMode,
    int? smartCacheSlots,
    bool? jinja,
    String? mmprojPath,
    bool? moeExpertsOnCpu,
  }) => KoboldLaunchConfig(
    modelPath: modelPath ?? this.modelPath,
    contextSize: contextSize ?? this.contextSize,
    batchSize: batchSize ?? this.batchSize,
    threads: threads,
    gpuLayers: gpuLayers ?? this.gpuLayers,
    autofitPaddingMb: autofitPaddingMb,
    useMmap: useMmap,
    useMlock: useMlock ?? this.useMlock,
    kvQuant: kvQuant ?? this.kvQuant,
    flashAttention: flashAttention ?? this.flashAttention,
    backend: backend ?? this.backend,
    gpuId: gpuId ?? this.gpuId,
    contextMode: contextMode ?? this.contextMode,
    smartCacheSlots: smartCacheSlots ?? this.smartCacheSlots,
    jinja: jinja ?? this.jinja,
    mmprojPath: mmprojPath ?? this.mmprojPath,
    mmprojOnCpu: mmprojOnCpu,
    moeExpertsOnCpu: moeExpertsOnCpu ?? this.moeExpertsOnCpu,
    extras: extras,
  );
}
