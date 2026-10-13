// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'comfy_edit_workflow.dart';
import 'comfy_gguf_city96_gate.dart';
import 'model_family.dart';
import 'studio_readiness.dart';

const String kStudioGraphUnreadable =
    'this graph could not be read. Choose it again, or choose another graph.';

/// The name the desk shows for an image backend.
String studioBackendName(String backend) {
  switch (backend) {
    case 'comfyui':
      return 'ComfyUI';
    case 'a1111':
      return 'Automatic1111';
    case 'drawthings':
      return 'Draw Things';
    default:
      return 'Remote';
  }
}

/// Why a non-Comfy desk has no model to run.
String studioNoModelWords(String backend) {
  switch (backend) {
    case 'remote':
      return 'no image model is chosen. Choose one with Change model.';
    case 'a1111':
      return 'no model is chosen. Choose one Automatic1111 has.';
    case 'drawthings':
      return 'no model is chosen. Choose one Draw Things has.';
    default:
      return 'no model is chosen.';
  }
}

/// What a Comfy graph still lacks, from the placeholders a run would leave
/// unfilled. Model slots are named by their label on the desk.
String studioUnfilledWords({
  required Set<String>? unfilled,
  required List<ComfyModelSlot> slots,
  String primaryFile = '',
}) {
  if (unfilled == null) return kStudioGraphUnreadable;
  if (isQwenImage21(primaryFile) && unfilled.contains('%MODEL_CLIP%')) {
    return 'this model needs the Qwen3-VL 8B text encoder. Choose it for '
        'Text encoder.';
  }
  final labels = {for (final slot in slots) slot.token: slot.label};
  final files = <String>[];
  final other = <String>[];
  var prompt = false;
  for (final token in unfilled) {
    if (token == ComfyEditTokens.prompt) {
      prompt = true;
    } else if (labels[token] != null) {
      files.add(labels[token]!);
    } else if (token.startsWith('%MODEL_')) {
      files.add('a model file ($token)');
    } else {
      other.add(token);
    }
  }
  final parts = <String>[
    if (files.isNotEmpty) 'choose a file for ${_listed(files)}',
    if (prompt) 'this graph has no prompt box the studio can fill',
    if (other.isNotEmpty)
      'this graph has inputs the studio can’t fill (${other.join(', ')})',
  ];
  if (parts.isEmpty) return 'choose the model files this graph loads.';
  return '${parts.join('; ')}.';
}

/// The line beside Generate: Ready, or what is missing and how to fix it.
/// [loaderNoteShown] is true where the GGUF loader's own note already sits
/// on screen, so the line does not repeat it.
String studioNotReadyLine({
  required StudioReadiness readiness,
  required String backendName,
  String primaryFile = '',
  bool loaderNoteShown = false,
}) {
  final message = readiness.message?.trim() ?? '';
  switch (readiness.kind) {
    case StudioReady.ready:
      return 'Ready to generate.';
    case StudioReady.unreachable:
      return 'Not ready — $backendName can’t be reached. Start it, or check '
          'its address.';
    case StudioReady.missingNodeClass:
      return 'Not ready — ComfyUI is missing the '
          '${readiness.missingClass ?? 'a required'} node. Install the custom '
          'node that provides it, then restart ComfyUI.';
    case StudioReady.needsUnetGraph:
      return 'Not ready — this model needs a graph that loads a diffusion '
          'model. Choose one of those graphs.';
    case StudioReady.loraMismatch:
      return 'Not ready — LoRA architecture does not match $primaryFile.';
    case StudioReady.needsLoaderUpdate:
      if (loaderNoteShown) {
        return 'Not ready — the GGUF loader needs an update first.';
      }
      return 'Not ready — ${message.isEmpty ? kCity96NeedsUpdate : message}';
    case StudioReady.needsComfyRestart:
      if (loaderNoteShown) {
        return 'Not ready — restart ComfyUI so it loads the updated GGUF '
            'loader.';
      }
      return 'Not ready — ${message.isEmpty ? kCity96NeedsUpdate : message}';
    case StudioReady.missingFile:
      final why = message.isEmpty
          ? 'choose the model files this graph loads.'
          : message;
      return 'Not ready — $why';
  }
}

String _listed(List<String> names) {
  if (names.length == 1) return names.first;
  final head = names.sublist(0, names.length - 1).join(', ');
  return '$head and ${names.last}';
}
