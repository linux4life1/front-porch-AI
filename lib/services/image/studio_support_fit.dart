// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'model_family.dart';

/// A text encoder or VAE may sit next to this model.
///
/// This decides what may be offered or filled in for an empty slot. It never
/// decides that a file the person picked is wrong: a name is a guess, and a
/// choice already made is kept (see [supportAutofill]).
///
/// An unlabeled file is kept, with these facts:
/// * Qwen-Image 2.1 takes a Qwen3-VL 8B encoder, or the prompt-enhancer
///   encoder (`pe_t2i` / `pe_i2i`) its official graphs load into a second
///   slot. A 4B or 2.5 VL file is the wrong width.
/// * Flux.2 Klein takes a Qwen3 encoder (`qwen_3_4b` / `qwen_3_8b`). Flux.1
///   does not.
/// * A vision projector is never an encoder, and a prompt enhancer is one only
///   on Qwen-Image 2.1. CLIP-L / T5 on a Qwen, Z-Image or Klein model is not
///   an encoder either.
bool supportFileFits({
  required String primary,
  required String file,
  required String role,
}) {
  final name = file.trim().toLowerCase();
  if (name.isEmpty) return true;
  final model = ImageModelFamily.detectFromName(primary);
  if (model == ModelFamily.unknown) return true;
  final encoder =
      role.toLowerCase().contains('text') ||
      role.toLowerCase().contains('clip');
  final vae = role.toLowerCase().contains('vae');
  final named = ImageModelFamily.detectFromName(file);
  // t5xxl matches the SDXL "xl" marker. It is still a text encoder. A Qwen
  // encoder is named for its language model, not for the image model it feeds.
  final encoderAlias =
      name.contains('t5') ||
      name.contains('clip_l') ||
      name.contains('clip-l') ||
      (encoder && named == ModelFamily.qwen);
  if (!encoderAlias && named != ModelFamily.unknown && !_shares(model, named)) {
    return false;
  }
  final clipL = name.contains('clip_l') || name.contains('clip-l');
  final t5 = name.contains('t5');
  final qwen = name.contains('qwen');
  final ae = name == 'ae.safetensors' || name.endsWith('/ae.safetensors');
  final klein = _klein(primary);
  if (encoder) {
    if (_visionProjector(name)) return false;
    if (model == ModelFamily.qwen && isQwenImage21(primary)) {
      return _qwen3Vl8b(name) || _promptEnhancer(name);
    }
    if (_promptEnhancer(name)) return false;
    if (model == ModelFamily.zImage ||
        model == ModelFamily.qwen ||
        (model == ModelFamily.flux && klein)) {
      if (clipL || t5) return false;
    }
    if ((model == ModelFamily.flux && !klein) || model == ModelFamily.kontext) {
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
    } else if (model == ModelFamily.flux && _klein(primary)) {
      score = _kleinEncoderScore(primary, base);
    } else if (model == ModelFamily.qwen) {
      if (isQwenImage21(primary)) {
        score = _qwen21EncoderScore(token, base);
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
    } else if (model == ModelFamily.flux && _klein(primary)) {
      if (base.contains('flux2') || base.contains('flux-2')) score = 100;
    } else if (model == ModelFamily.zImage ||
        model == ModelFamily.flux ||
        model == ModelFamily.kontext) {
      if (ae) score = 100;
    }
  }
  return score;
}

/// Empty support slots, filled from the installed files.
///
/// A slot that already holds a file is never touched: the person picked it,
/// or an earlier run did, and a file name is too weak a reason to overwrite
/// or blank it. A slot nothing installed fits stays empty.
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
    if ((choices['$workflowId/$token'] ?? '').trim().isNotEmpty) continue;
    final pool = token.contains('VAE') ? vaes : clips;
    final pick = pickSupportFile(primary: primary, token: token, files: pool);
    if (pick.isNotEmpty) out[token] = pick;
  }
  return out;
}

/// Flux.2 Klein 4B pairs with `qwen_3_4b`, 9B with `qwen_3_8b`. Either Qwen3
/// file fits; the one that matches the model's size fills first.
int _kleinEncoderScore(String primary, String base) {
  if (!base.contains('qwen')) return 10;
  final size = RegExp(
    r'(^|[^a-z0-9])(4|8|9)b($|[^a-z0-9])',
  ).firstMatch(primary.toLowerCase());
  final want = size == null ? '' : (size.group(2) == '4' ? '4' : '8');
  final has = RegExp(r'qwen_?3_?(4|8)b').firstMatch(base)?.group(1);
  return want.isNotEmpty && want == has ? 100 : 80;
}

/// The first text-encoder slot of a Qwen-Image 2.1 graph holds the Qwen3-VL 8B
/// encoder. The official graphs load the prompt enhancer into a later slot.
int _qwen21EncoderScore(String token, String base) {
  final first = token == '%MODEL_CLIP%';
  if (_qwen3Vl8b(base)) return first ? 100 : 40;
  if (!_promptEnhancer(base)) return 10;
  if (first) return -1;
  return base.contains('pe_t2i') ? 100 : 90;
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

bool _klein(String primary) => primary.toLowerCase().contains('klein');

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
