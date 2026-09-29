// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'model_family.dart';

/// A text encoder or VAE may sit next to this model.
///
/// An unlabeled file is kept, except on Qwen-Image 2.1: that model only
/// accepts a Qwen3-VL 8B text encoder. A 4B or 2.5 VL file is the wrong
/// width and is dropped. A vision projector or prompt enhancer is not an
/// encoder. CLIP-L / T5 on a Qwen or Z-Image model is not either.
bool supportFileFits({
  required String primary,
  required String file,
  required String role,
}) {
  final name = file.trim().toLowerCase();
  if (name.isEmpty) return true;
  final model = ImageModelFamily.detectFromName(primary);
  if (model == ModelFamily.unknown) return true;
  final named = ImageModelFamily.detectFromName(file);
  // t5xxl matches the SDXL "xl" marker. It is still a text encoder.
  final encoderAlias =
      name.contains('t5') || name.contains('clip_l') || name.contains('clip-l');
  if (!encoderAlias && named != ModelFamily.unknown && !_shares(model, named)) {
    return false;
  }
  final encoder =
      role.toLowerCase().contains('text') ||
      role.toLowerCase().contains('clip');
  final vae = role.toLowerCase().contains('vae');
  final clipL = name.contains('clip_l') || name.contains('clip-l');
  final t5 = name.contains('t5');
  final qwen = name.contains('qwen');
  final ae = name == 'ae.safetensors' || name.endsWith('/ae.safetensors');
  if (encoder) {
    if (_visionProjector(name) || _promptEnhancer(name)) return false;
    if (model == ModelFamily.qwen &&
        isQwenImage21(primary) &&
        !_qwen3Vl8b(name)) {
      return false;
    }
    if (model == ModelFamily.zImage || model == ModelFamily.qwen) {
      if (clipL || t5) return false;
    }
    if (model == ModelFamily.flux || model == ModelFamily.kontext) {
      if (qwen) return false;
    }
    if (_checkpoint(model) && (qwen || t5)) return false;
  }
  if (vae) {
    if (model == ModelFamily.qwen && ae && !qwen) return false;
    if ((model == ModelFamily.flux || model == ModelFamily.kontext) && qwen) {
      return false;
    }
    if (_checkpoint(model) && (ae || qwen)) return false;
  }
  return true;
}

/// Drop a stored support file that does not belong with [primary].
String supportChoiceOrBlank({
  required String token,
  required String file,
  required String primary,
}) {
  if (file.isEmpty) return file;
  if (!token.contains('CLIP') && !token.contains('VAE')) return file;
  final role = token.contains('VAE') ? 'VAE' : 'Text encoder';
  return supportFileFits(primary: primary, file: file, role: role) ? file : '';
}

/// Best installed file for one text-encoder or VAE slot. Empty when none fits.
String pickSupportFile({
  required String primary,
  required String token,
  required List<String> files,
}) {
  String best = '';
  var bestScore = -1;
  for (final file in files) {
    final score = supportFileScore(primary: primary, token: token, file: file);
    if (score > bestScore) {
      bestScore = score;
      best = file;
    }
  }
  return bestScore < 0 ? '' : best;
}

/// How well [file] fills [token] for [primary]. Negative means do not use it.
int supportFileScore({
  required String primary,
  required String token,
  required String file,
}) {
  final base = file.trim().toLowerCase().split('/').last;
  if (base.isEmpty) return -1;
  final role = token.contains('VAE') ? 'VAE' : 'Text encoder';
  if (!supportFileFits(primary: primary, file: file, role: role)) return -1;
  final model = ImageModelFamily.detectFromName(primary);
  var score = 10;
  if (token.contains('CLIP1')) {
    if (base.contains('clip_l') || base.contains('clip-l')) score = 100;
    if (base.contains('t5')) score = 30;
  } else if (token.contains('CLIP2')) {
    if (base.contains('t5')) score = 100;
    if (base.contains('clip_l') || base.contains('clip-l')) score = 30;
  } else if (token.contains('CLIP')) {
    if (model == ModelFamily.zImage) {
      if (base.contains('qwen_3_4b') || base.contains('qwen3_4b')) {
        score = 100;
      } else if (base.contains('qwen')) {
        score = 80;
      }
    } else if (model == ModelFamily.qwen) {
      if (isQwenImage21(primary)) {
        if (_qwen3Vl8b(base)) score = 100;
      } else if (base.contains('qwen_2.5_vl') || base.contains('qwen2.5_vl')) {
        score = 100;
      } else if (base.contains('qwen_3_4b') || base.contains('qwen3_4b')) {
        score = 90;
      } else if (base.contains('qwen')) {
        score = 80;
      }
    }
  } else if (token.contains('VAE')) {
    final ae = base == 'ae.safetensors';
    if (model == ModelFamily.qwen) {
      final v21 = isQwenImage21(primary);
      if (v21 && (base.contains('2.1') || base.contains('2_1'))) {
        score = 100;
      } else if (base.contains('qwen') && base.contains('vae')) {
        score = v21 ? 40 : 100;
      }
      if (base.contains('qwen') && !base.contains('vae')) score = 80;
    } else if (model == ModelFamily.zImage ||
        model == ModelFamily.flux ||
        model == ModelFamily.kontext) {
      if (ae) score = 100;
    }
  }
  return score;
}

/// Support slots that are empty or unfit, filled from the installed files.
/// A choice that already fits is left out of the result.
Map<String, String> supportAutofill({
  required String workflowId,
  required String primary,
  required Map<String, String> choices,
  required List<String> clips,
  required List<String> vaes,
  required List<String> tokens,
}) {
  final out = <String, String>{};
  for (final token in tokens) {
    final current = (choices['$workflowId/$token'] ?? '').trim();
    if (supportChoiceOrBlank(
      token: token,
      file: current,
      primary: primary,
    ).isNotEmpty) {
      continue;
    }
    final pool = token.contains('VAE') ? vaes : clips;
    final pick = pickSupportFile(primary: primary, token: token, files: pool);
    if (pick.isNotEmpty) {
      out[token] = pick;
    } else if (current.isNotEmpty) {
      out[token] = '';
    }
  }
  return out;
}

String supportPrimary(
  String workflowId,
  Map<String, String> choices,
  String fallback,
) {
  for (final token in ['%MODEL_DIFFUSION%', '%MODEL_CHECKPOINT%']) {
    final file = (choices['$workflowId/$token'] ?? '').trim();
    if (file.isNotEmpty) return file;
  }
  return fallback;
}

/// Qwen-Image 2.1 conditions on Qwen3-VL 8B (width 4096). A 4B file is 2560.
bool _qwen3Vl8b(String file) {
  final base = file.trim().toLowerCase().split('/').last;
  if (_visionProjector(base) || _promptEnhancer(base)) return false;
  final vl =
      base.contains('qwen3vl') ||
      base.contains('qwen3_vl') ||
      base.contains('qwen_3vl') ||
      base.contains('qwen_3_vl') ||
      base.contains('qwen3-vl') ||
      base.contains('qwen-3-vl');
  if (!vl) return false;
  return RegExp(r'(^|[^a-z0-9])8b($|[^a-z0-9])').hasMatch(base);
}

bool _visionProjector(String file) =>
    file.trim().toLowerCase().split('/').last.contains('mmproj');

bool _promptEnhancer(String file) {
  final base = file.trim().toLowerCase().split('/').last;
  return base.contains('pe_t2i') ||
      base.contains('pe_i2i') ||
      base.contains('prompt_enhance');
}

bool _checkpoint(ModelFamily family) {
  return family == ModelFamily.sd15 ||
      family == ModelFamily.sdxl ||
      family == ModelFamily.pony ||
      family == ModelFamily.sd3;
}

bool _shares(ModelFamily model, ModelFamily file) {
  if (model == file) return true;
  const sdxl = {ModelFamily.pony, ModelFamily.sdxl};
  if (sdxl.contains(model) && sdxl.contains(file)) return true;
  const qwen = {ModelFamily.qwen, ModelFamily.zImage};
  return qwen.contains(model) && qwen.contains(file);
}
