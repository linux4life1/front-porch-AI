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

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import 'package:front_porch_ai/services/kobold_admin_swap.dart';
import 'package:front_porch_ai/services/storage_service.dart';

/// Translate the user's settings and the caller's hardware choices into a
/// KoboldCpp argv.
///
/// Lifted out of `KoboldService.startKobold`, which was two thirds
/// argument-building and one third process management. Two reasons beyond the
/// line count: every rule here is a decision with a bug behind it (the
/// iGPU-defaulting `--usecublas`, the flash-attention prerequisite, the
/// launcher's 4096 batch cap) and those rules were unreachable by a test while
/// they lived inside a method that spawns a process. As a pure function of its
/// inputs they are covered by `test/services/kobold_launch_args_test.dart`.
///
/// The ONE side effect is deliberate and documented at its site: an oversized
/// BLAS batch is written to a one-key `.kcpps` next to the executable, because
/// KoboldCpp's CLI refuses the value but its config loader accepts it.
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
}) async {
  final List<String> args;

  if (kcppsPath != null) {
    // ── Preset mode (.kcpps) ────────────────────────────────────────────────
    // Let KoboldCpp load GPU, context, and all other settings from the file.
    // We only force the port so the app's _baseUrl doesn't break.
    //
    // If the .kcpps file has NO model key (StorageService.kcppsHasModel is
    // false), the user selected one via the Flutter model picker and we pass
    // it via --model.  Without this KoboldCPP would open its own native file
    // picker — which is the bug we're fixing.
    //
    // If the .kcpps file DOES have a model, modelPath is empty here and we
    // let the preset handle it entirely.
    args = [
      '--config',
      kcppsPath,
      '--port',
      port.toString(),
      if (modelPath.isNotEmpty) ...['--model', modelPath],
    ];
  } else {
    // ── Standard UI-driven mode ─────────────────────────────────────────────
    args = [
      '--model',
      modelPath,
      '--port',
      port.toString(),
      '--contextsize',
      contextSize.toString(),
      '--gpulayers',
      gpuLayers.toString(),
    ];

    // ── GPU backend flags ───────────────────────────────────────────────────

    if (useVulkan) args.add('--usevulkan');

    if (useCublas) {
      // Always pass an explicit GPU ID with --usecublas to prevent KoboldCPP
      // from defaulting to GPU 0 which may be an iGPU on multi-GPU systems.
      // Bug fix: on a system with both an iGPU (GPU 0) and a discrete RTX
      // (GPU 1) the old code silently ran everything on the iGPU at ~0.5 t/s.
      args.addAll(['--usecublas', storage.backendSettings.gpuId.toString()]);
    }

    if (useRocm) {
      // Explicit device index — same iGPU-defaulting hazard as CUDA on
      // APU + dGPU systems.
      args.addAll(['--usehipblas', storage.backendSettings.gpuId.toString()]);
      // Flash attention kernel crashes on many AMD GPUs — always disable for
      // ROCm.
      args.add('--noflashattention');
    }
    // Note: Metal is used automatically on macOS Apple Silicon, no flag needed.

    // ── FlashAttention ──────────────────────────────────────────────────────
    // Bug fix: previously only added when KV quantization was also enabled,
    // meaning CUDA/Metal users without KV quant never got the ~30% speed
    // boost. Now enabled independently for CUDA and Metal. ROCm is excluded
    // above.
    final wantsFlashAttn = storage.backendSettings.flashAttentionEnabled;
    final canUseFlashAttn = (useCublas || useMetal) && !useRocm;
    if (wantsFlashAttn && canUseFlashAttn) {
      args.add('--flashattention');
    }

    // ── KV Cache Quantization ───────────────────────────────────────────────
    // Flash attention is a prerequisite for V-cache quantization. Since we
    // may have already added it above, only add the flag if it wasn't added.
    if (storage.backendSettings.kvQuantizationLevel > 0) {
      args.add('--quantkv');
      args.add(storage.backendSettings.kvQuantizationLevel.toString());
      // Ensure flash attention is present for quantised V-cache even if the
      // user disabled it in Advanced settings (quantkv requires it).
      if (!args.contains('--flashattention') && !useRocm) {
        args.add('--flashattention');
      }
    }

    // ── mlock ───────────────────────────────────────────────────────────────
    // Prevents the OS from paging model weights to disk under memory pressure.
    // Without this, a system at the edge of RAM capacity can drop from 20 t/s
    // to 0.5 t/s mid-session. Default ON for Win/Mac, OFF for Linux (requires
    // root or ulimit -l unlimited which most users haven't set).
    if (storage.backendSettings.mlockEnabled) {
      args.add('--usemlock');
    }

    // ── BLAS batch size ─────────────────────────────────────────────────────
    // Controls how many tokens are processed in parallel during prefill
    // (prompt evaluation). Higher = faster context loading, more VRAM.
    // Default 512. Large-VRAM users (24 GB+) benefit from 1024–2048.
    if (storage.backendSettings.blasBatchSize != 512) {
      final batch = storage.backendSettings.blasBatchSize;
      if (batch > 4096) {
        // KoboldCpp's CLI rejects anything above 4096 — but that cap is
        // launcher-only (an argparse `choices` list); the engine itself has
        // no upper clamp for GGUF models and sets n_ubatch = n_batch from
        // whatever arrives. Values loaded from a --config file are applied
        // with setattr AFTER argument parsing — no choices validation — and
        // Kobold's loader is explicitly designed so CLI flags override
        // config keys, so this one-key config carries ONLY the batch size
        // while every other flag stays authoritative on the CLI. If a
        // future build hardens config validation, the worst case is the
        // key failing to apply (Kobold runs at its default batch instead
        // of refusing to start, which is what the raw CLI flag did).
        final overrides = File(
          path.join(path.dirname(executablePath), 'fpai_batch_override.kcpps'),
        );
        await overrides.writeAsString(jsonEncode({'batchsize': batch}));
        args.addAll(['--config', overrides.path]);
      } else {
        // Only pass the flag when non-default so KoboldCPP's built-in
        // default applies for users who haven't changed this setting.
        args.addAll(['--blasbatchsize', batch.toString()]);
      }
    }
  }

  // ── Jinja chat templates ──────────────────────────────────────────────────
  // Run each model's OWN embedded chat template server-side instead of
  // KoboldCpp's built-in AutoGuess string adapter. This is what lets a model's
  // `chat_template_kwargs` (notably enable_thinking) actually take effect —
  // without --jinja, Kobold discards that field, so reasoning/thinking models
  // whose template defaults to suppressed (Gemma-4-class channel reasoners)
  // never think, and the "Request Reasoning" toggle is a no-op locally.
  // Applied to BOTH launch paths (preset .kcpps and standard) since both drive
  // the shared /v1/chat/completions transport. Safe as a global default: if a
  // model's embedded template is missing or malformed, KoboldCpp automatically
  // falls back to its heuristic adapter (verified — the server still starts and
  // answers), so this never blocks a model from loading. Plain --jinja keeps
  // tool calls on the non-jinja path (unchanged); --jinja_tools is
  // intentionally NOT used.
  //
  // It is also what makes the system-role workaround necessary at all: running
  // the GGUF's own template is exactly how a template with no system branch
  // gets to throw the character card away. See system_role_probe.dart.
  args.add('--jinja');

  // ── Vision projector (mmproj) ─────────────────────────────────────────────
  // A multimodal model whose projector is NOT baked into the GGUF (it ships in
  // a separate mmproj file) can actually see images only when KoboldCpp is
  // handed that file. Added for BOTH preset and standard modes, and only when
  // a non-empty path is configured AND the file exists on disk — a stale or
  // missing mmproj must never abort the launch.
  if (mmprojPath != null &&
      mmprojPath.isNotEmpty &&
      File(mmprojPath).existsSync()) {
    args.addAll(['--mmproj', mmprojPath]);
  }

  // In-process GGUF/.kcpps swap (GpuSwap) needs --admin + an existing
  // --admindir. Without both, reload_config returns HTTP 200
  // {"success":false} and we used to treat that as a miss → process restart.
  final adminDir = koboldAdminDirFor(storage);
  if (adminDir.isNotEmpty) {
    Directory(adminDir).createSync(recursive: true);
    args.addAll(['--admin', '--admindir', adminDir]);
  }

  return args;
}
