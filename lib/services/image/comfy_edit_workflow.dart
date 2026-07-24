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

// The ComfyUI *edit* engine: a token-substitution layer over a ComfyUI API-format
// graph, shared by BOTH the bundled presets and a user's uploaded workflow —
// they are the same thing (a graph with `%TOKEN%` placeholders the app fills in),
// so there is exactly ONE code path and no per-model graph hardcoding.
//
// This is deliberately NOT the programmatic ComfyWorkflow builder (that stays
// for Create/txt2img/img2img, whose graph the app fully owns). An edit graph is
// the *user's or model's* shape — arbitrary — so we treat it as opaque data and
// only splice in the reference image, instruction, and knobs at the marked spots.
//
// Pure and deterministic (no I/O). Unit-tested.

import 'package:front_porch_ai/services/capability/image_reference_role.dart';

/// The standard placeholders the app fills into any edit workflow (preset or BYO).
/// A workflow author writes these as the value where the app should inject data,
/// e.g. `"text": "%PROMPT%"` or `"seed": "%SEED%"`. Model-file slots use their own
/// `%MODEL_*%` tokens declared per-preset (see [ComfyModelSlot]).
class ComfyEditTokens {
  ComfyEditTokens._();

  static const String image = '%IMAGE%';
  static const String prompt = '%PROMPT%';
  static const String negative = '%NEGATIVE%';
  static const String seed = '%SEED%';
  static const String steps = '%STEPS%';
  static const String cfg = '%CFG%';
  static const String denoise = '%DENOISE%';
  static const String sampler = '%SAMPLER%';
  static const String scheduler = '%SCHEDULER%';

  /// Model-family shift (Qwen maps it to `ModelSamplingAuraFlow.shift`; graphs
  /// without a shift node simply never reference this token).
  static const String shift = '%SHIFT%';

  /// The two an edit graph genuinely CANNOT work without — the reference image
  /// and the instruction. A BYO workflow missing either is rejected.
  static const List<String> required = [image, prompt];

  /// Every standard (non-model) token the app can fill, for BYO detection + docs.
  static const List<String> all = [
    image,
    prompt,
    negative,
    seed,
    steps,
    cfg,
    denoise,
    sampler,
    scheduler,
    shift,
  ];
}

/// A model-file slot in a preset: a `%MODEL_*%` token whose value the user picks
/// from the files their ComfyUI actually has. The UI populates a dropdown from
/// `/object_info` for [loaderClass].[inputName]; the chosen filename is substituted
/// for [token]. A preset can't know the user's filenames, so this is how a bundled
/// graph adapts to any install.
class ComfyModelSlot {
  /// The placeholder in the template, e.g. `%MODEL_DIFFUSION%`.
  final String token;

  /// The ComfyUI loader node whose file list this slot picks from, e.g. `UNETLoader`.
  final String loaderClass;

  /// The loader input holding the filename, e.g. `unet_name`.
  final String inputName;

  /// Human label for the dropdown, e.g. `Diffusion model`.
  final String label;

  const ComfyModelSlot({
    required this.token,
    required this.loaderClass,
    required this.inputName,
    required this.label,
  });
}

/// A bundled ComfyUI edit preset — a token-placeholdered API-format graph plus what
/// it needs to run: the node `class_type`s that must exist on the user's ComfyUI
/// ([requiredNodes], checked against `/object_info`) and the model-file slots the
/// user fills ([modelSlots]).
class ComfyEditPreset {
  /// Stable id (also used to persist the user's per-preset model-slot choices).
  final String id;
  final String label;
  final EditModelKind kind;

  /// Node `class_type`s that must be present in `/object_info` for this to run.
  final List<String> requiredNodes;

  /// Model-file slots the user must fill (empty for single-checkpoint presets that
  /// reuse the main model picker — none do today; Kontext still uses its own slot).
  final List<ComfyModelSlot> modelSlots;

  /// The API-format graph (node-id → {class_type, inputs}) with `%TOKEN%` values.
  final Map<String, dynamic> template;

  const ComfyEditPreset({
    required this.id,
    required this.label,
    required this.kind,
    required this.requiredNodes,
    required this.modelSlots,
    required this.template,
  });
}

/// Substitute [values] (token → typed value) into a token-placeholdered [template],
/// returning a fresh graph. An EXACT-match string value becomes the typed value —
/// so `"seed": "%SEED%"` becomes `"seed": 12345` (int), not the string "12345" —
/// while a token embedded in a larger string is string-replaced in place. Deep and
/// pure; the input is never mutated.
Map<String, dynamic> substituteComfyWorkflow(
  Map<String, dynamic> template,
  Map<String, Object?> values,
) {
  final out = _sub(template, values);
  return (out as Map).cast<String, dynamic>();
}

Object? _sub(Object? node, Map<String, Object?> values) {
  if (node is String) {
    // Exact token → inject the typed value (preserves int/double for numeric
    // inputs like seed/steps/cfg/denoise).
    if (values.containsKey(node)) return values[node];
    // Token embedded in a longer string → textual replacement.
    var s = node;
    for (final e in values.entries) {
      if (s.contains(e.key)) s = s.replaceAll(e.key, '${e.value}');
    }
    return s;
  }
  if (node is Map) {
    return node.map((k, v) => MapEntry(k, _sub(v, values)));
  }
  if (node is List) {
    return node.map((v) => _sub(v, values)).toList();
  }
  return node;
}

/// Which of [ComfyEditTokens.all] appear anywhere in [template]. Used to describe
/// an uploaded (BYO) workflow to the user ("found %IMAGE%, %PROMPT%…") and to warn
/// when a graph is missing the ones an edit needs (%IMAGE% + %PROMPT%).
Set<String> detectComfyTokens(Map<String, dynamic> template) {
  final found = <String>{};
  final hay = _flattenStrings(template);
  for (final tok in ComfyEditTokens.all) {
    if (hay.any((s) => s.contains(tok))) found.add(tok);
  }
  return found;
}

final RegExp _tokenRe = RegExp(r'%[A-Z0-9_]+%');

/// Any `%...%` placeholders still present after substitution — a non-empty result
/// means the graph would be submitted with an unfilled token (a bug/misconfig).
Set<String> unresolvedComfyTokens(Object? node) {
  final left = <String>{};
  for (final s in _flattenStrings(node)) {
    for (final m in _tokenRe.allMatches(s)) {
      left.add(m.group(0)!);
    }
  }
  return left;
}

List<String> _flattenStrings(Object? node) {
  final out = <String>[];
  void walk(Object? n) {
    if (n is String) {
      out.add(n);
    } else if (n is Map) {
      n.values.forEach(walk);
    } else if (n is List) {
      n.forEach(walk);
    }
  }

  walk(node);
  return out;
}
