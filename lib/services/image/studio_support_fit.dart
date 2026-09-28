// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'model_family.dart';

/// A text encoder or VAE may sit next to this model.
///
/// An unlabeled file is kept. A name that belongs to another architecture,
/// or a CLIP-L / T5 encoder on a Qwen or Z-Image model, is not.
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
  if (named != ModelFamily.unknown && !_shares(model, named)) return false;
  final encoder =
      role.toLowerCase().contains('text') ||
      role.toLowerCase().contains('clip');
  final vae = role.toLowerCase().contains('vae');
  final clipL = name.contains('clip_l') || name.contains('clip-l');
  final t5 = name.contains('t5');
  final qwen = name.contains('qwen');
  final ae = name == 'ae.safetensors' || name.endsWith('/ae.safetensors');
  if (encoder) {
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
