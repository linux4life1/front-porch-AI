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

/// Base-model family detection for image checkpoints and LoRAs.
///
/// A LoRA only works on a checkpoint from the same base-model family — an SD1.5
/// LoRA on an SDXL checkpoint (or a Flux LoRA on anything else) produces noise
/// or a hard tensor-shape error. Nothing in the local image backends reliably
/// reports this over the wire the same way:
///   • Automatic1111 — `/sdapi/v1/loras` returns a `metadata` block that usually
///     carries `ss_base_model_version` / `modelspec.architecture`.
///   • ComfyUI — `/view_metadata/loras?filename=…` returns the same safetensors
///     header metadata.
///   • Draw Things — the gRPC surface lists only file names; its compatibility
///     database is not exposed, but its file names are canonical.
///
/// So detection is metadata-first (a fact) and file-name-second (a well-founded
/// guess). [LoraOption.familyFromMetadata] records which we had, and
/// [ImageModelFamily.compatibility] downgrades a name-only mismatch from
/// "certain" to "likely" so the UI can hide the sure ones and merely warn on the
/// guesses. Pure, deterministic, no I/O — trivially testable.
library;

/// A base-model architecture family. Members of the same family are
/// cross-compatible; members of different families are not (Pony is the one
/// soft case — see [ImageModelFamily.compatibility]).
enum ModelFamily {
  sd15,
  sdxl,
  pony,
  sd3,
  flux,
  unknown;

  /// Short human label for badges ("SDXL", "SD1.5", …). Unknown reads as "?".
  String get label {
    switch (this) {
      case ModelFamily.sd15:
        return 'SD1.5';
      case ModelFamily.sdxl:
        return 'SDXL';
      case ModelFamily.pony:
        return 'Pony';
      case ModelFamily.sd3:
        return 'SD3';
      case ModelFamily.flux:
        return 'Flux';
      case ModelFamily.unknown:
        return '?';
    }
  }
}

/// The compatibility verdict between a LoRA and the active checkpoint.
enum LoraCompat {
  /// Same family — safe to use.
  match,

  /// Wrong family, but only a name-based guess (or a Pony↔SDXL soft mismatch
  /// that loads but usually looks off). Shown, badged, never hidden.
  likely,

  /// Wrong family confirmed by embedded metadata — it will break. Hidden by
  /// default behind the "show incompatible" drawer.
  certain,

  /// Not enough signal on one side to judge. Always shown, never assumed bad.
  unknown,
}

/// One selectable LoRA plus the base-model family we detected for it and whether
/// that detection came from embedded metadata (authoritative) or the file name
/// (a guess).
class LoraOption {
  final String name;
  final ModelFamily family;
  final bool familyFromMetadata;

  const LoraOption(
    this.name,
    this.family, {
    this.familyFromMetadata = false,
  });
}

/// Pure detection + compatibility statics. No state, no I/O.
class ImageModelFamily {
  ImageModelFamily._();

  // ── File-name detection (the floor; used for checkpoints and as the LoRA
  //    fallback when no metadata is available). Order matters: more specific
  //    families are tested before the ones they are architecturally built on
  //    (Pony/Illustrious before SDXL; SDXL before SD1.5). ────────────────────
  static final RegExp _flux = RegExp(r'flux');
  static final RegExp _sd3 = RegExp(r'(^|[^a-z0-9])sd[ _-]?3($|[^0-9])|stable[ _-]?diffusion[ _-]?3');
  static final RegExp _pony = RegExp(r'pony');
  // "xl" as an SDXL marker: matched when it is NOT followed by another letter,
  // so the common attached suffix ("dreamshaperXL", "juggernautXL_v9") hits while
  // mid-word "xl" ("voxel", "flexlora") does not.
  static final RegExp _sdxl = RegExp(
    r'sd[ _-]?xl|xl(?![a-z])|illustrious|noobai|noob[ _-]?ai|animagine',
  );
  static final RegExp _sd15 = RegExp(
    r'sd[ _-]?1\.?5|(^|[^0-9])1\.5($|[^0-9])|(^|[^a-z0-9])v?1[.\-_]?5($|[^0-9])|sd[ _-]?v?1(?![0-9])',
  );

  /// Best-effort family from a checkpoint or LoRA file name. Returns
  /// [ModelFamily.unknown] when nothing recognizable is present.
  static ModelFamily detectFromName(String name) {
    final s = name.toLowerCase();
    if (_flux.hasMatch(s)) return ModelFamily.flux;
    if (_sd3.hasMatch(s)) return ModelFamily.sd3;
    if (_pony.hasMatch(s)) return ModelFamily.pony;
    if (_sdxl.hasMatch(s)) return ModelFamily.sdxl;
    if (_sd15.hasMatch(s)) return ModelFamily.sd15;
    return ModelFamily.unknown;
  }

  /// Family from a safetensors metadata block (A1111 `/sdapi/v1/loras` entry
  /// `metadata`, or ComfyUI `/view_metadata`). Reads `ss_base_model_version`
  /// and `modelspec.architecture`. Returns [ModelFamily.unknown] when neither is
  /// present or recognizable (SD2 is deliberately unknown, not force-classified,
  /// so it is never falsely hidden).
  static ModelFamily detectFromMetadata(Map<String, dynamic> metadata) {
    final ver = (metadata['ss_base_model_version'] ?? '').toString().toLowerCase();
    final arch = (metadata['modelspec.architecture'] ?? '').toString().toLowerCase();
    final s = '$ver $arch';
    if (s.trim().isEmpty) return ModelFamily.unknown;
    if (s.contains('flux')) return ModelFamily.flux;
    if (s.contains('sd3') || s.contains('stable-diffusion-3') || s.contains('stable_diffusion_3')) {
      return ModelFamily.sd3;
    }
    if (s.contains('xl')) return ModelFamily.sdxl;
    if (s.contains('sd_v1') ||
        s.contains('sd-v1') ||
        s.contains('sd1') ||
        s.contains('stable-diffusion-v1') ||
        s.contains('v1-5') ||
        s.contains('v1.5')) {
      return ModelFamily.sd15;
    }
    return ModelFamily.unknown;
  }

  /// Compose a [LoraOption] from a name and optional metadata. Metadata wins
  /// (it is authoritative) EXCEPT that a file name saying "pony" overrides a
  /// metadata reading of SDXL — Pony trains on SDXL so its metadata reports SDXL,
  /// yet a Pony LoRA on a vanilla SDXL checkpoint usually looks wrong, and we
  /// want to surface that as a soft warning.
  static LoraOption classifyLora(String name, {Map<String, dynamic>? metadata}) {
    final nameFam = detectFromName(name);
    final metaFam = metadata != null ? detectFromMetadata(metadata) : ModelFamily.unknown;
    if (nameFam == ModelFamily.pony) {
      return LoraOption(name, ModelFamily.pony, familyFromMetadata: false);
    }
    if (metaFam != ModelFamily.unknown) {
      return LoraOption(name, metaFam, familyFromMetadata: true);
    }
    return LoraOption(name, nameFam, familyFromMetadata: false);
  }

  /// Verdict for a LoRA against the active checkpoint. [metadataBacked] is
  /// [LoraOption.familyFromMetadata] — a hard mismatch we only guessed from the
  /// file name is downgraded to [LoraCompat.likely] instead of
  /// [LoraCompat.certain], so the UI warns rather than hides.
  static LoraCompat compatibility(
    ModelFamily lora,
    ModelFamily checkpoint, {
    required bool metadataBacked,
  }) {
    if (lora == ModelFamily.unknown || checkpoint == ModelFamily.unknown) {
      return LoraCompat.unknown;
    }
    if (lora == checkpoint) return LoraCompat.match;
    // Pony ↔ SDXL: same architecture, loads fine, but usually off-model. Never
    // a hard hide — always a soft "likely" nudge.
    final ponyPair = (lora == ModelFamily.pony && checkpoint == ModelFamily.sdxl) ||
        (lora == ModelFamily.sdxl && checkpoint == ModelFamily.pony);
    if (ponyPair) return LoraCompat.likely;
    // Genuinely different architecture.
    return metadataBacked ? LoraCompat.certain : LoraCompat.likely;
  }
}
