// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/image/comfy_gguf_city96_gate.dart';

/// Asks before Front Porch changes ComfyUI-GGUF's `loader.py`. False when the
/// person says no or closes the dialog.
Future<bool> showCity96LoaderDialog(
  BuildContext context,
  City96Question question,
) async {
  final yes = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Update the ComfyUI-GGUF loader?'),
      content: SelectableText(
        'Qwen-Image 2.1 GGUF needs a small change to ComfyUI-GGUF before it '
        'can load. Front Porch will update this file for the ComfyUI at '
        '${question.comfyUrl}:\n\n${question.loaderPath}\n\n'
        'The original is kept as loader.py.bak. ComfyUI has to be restarted '
        'afterwards. Other models are not affected either way.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Update loader'),
        ),
      ],
    ),
  );
  return yes ?? false;
}
