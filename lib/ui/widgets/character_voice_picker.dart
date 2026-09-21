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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// The ONE per-character TTS voice control (2026-08-14).
///
/// A character's own voice silently and permanently overrides the global
/// Settings voice — the residual cause behind the Discord "I picked Adam
/// and it still speaks as a woman" report. A voice can arrive without the
/// user ever choosing it: `tts_voice` is read straight off an imported
/// character card, and legacy migrations carry one over. Before this
/// widget the only per-character picker in the app lived inside the
/// group-creation cast step, so for a 1:1 character the override was
/// invisible AND unclearable, and the only clue was a debug print.
///
/// So: empty/null means "use the global voice" and says so with the
/// global's real name, and an assigned voice from a DIFFERENT engine is
/// still shown (labelled) rather than silently rendering blank — a voice
/// you cannot see is a voice you cannot fix.
class CharacterVoicePicker extends StatelessWidget {
  const CharacterVoicePicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.dense = false,
  });

  /// The character's assigned voice id. Null or empty = follow the global.
  final String? value;

  /// Emits '' for "use the global voice", else the chosen voice id.
  final ValueChanged<String> onChanged;

  /// Compact form for list rows (the group cast step); the editor uses the
  /// full-width labelled form.
  final bool dense;

  /// The label for [voiceId] within [voices], falling back to a readable
  /// form of the raw id when the current engine does not offer it (a voice
  /// assigned under another engine, or one retired from the model).
  static String labelFor(String voiceId, List<TtsVoiceInfo> voices) {
    for (final v in voices) {
      if (v.id == voiceId) return v.name;
    }
    // Kokoro-style ids are `<language><gender>_<name>`; show the readable
    // half rather than an opaque token.
    final underscore = voiceId.indexOf('_');
    if (underscore > 0 && underscore < voiceId.length - 1) {
      final tail = voiceId.substring(underscore + 1);
      return '${tail[0].toUpperCase()}${tail.substring(1)} ($voiceId)';
    }
    return voiceId;
  }

  @override
  Widget build(BuildContext context) {
    // TTS is optional in the tree: the editor opens from several routes and
    // must never fail to render just because voice services are not wired
    // (a whole page crashing over a dropdown is a bad trade). Degrades to a
    // muted line, matching what the web editor shows without TTS.
    TtsService? tts;
    StorageService? storage;
    try {
      tts = context.watch<TtsService>();
      storage = context.watch<StorageService>();
    } on ProviderNotFoundException {
      tts = null;
    }
    if (tts == null || storage == null) {
      return Text(
        'Text-to-speech is not available here, so no voice can be assigned.',
        style: TextStyle(color: AppColors.textTertiary(context), fontSize: 11),
      );
    }
    final voices = tts.activeVoices;
    final assigned = value ?? '';
    final knownHere = voices.any((v) => v.id == assigned);

    final globalId = storage.ttsSettings.ttsVoiceModel;
    final globalLabel = globalId.isEmpty
        ? 'Use the global voice (none picked yet)'
        : 'Use the global voice (${labelFor(globalId, voices)})';

    return DropdownButtonFormField<String>(
      initialValue: assigned,
      isExpanded: true,
      isDense: dense,
      dropdownColor: AppColors.surfaceContainerOf(context),
      style: TextStyle(color: AppColors.textPrimary(context)),
      decoration: InputDecoration(
        filled: true,
        fillColor: AppColors.surfaceContainerOf(context),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: 12,
          vertical: dense ? 6 : 10,
        ),
      ),
      items: [
        DropdownMenuItem(
          value: '',
          child: Text(
            globalLabel,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AppColors.textSecondary(context)),
          ),
        ),
        // A voice this engine doesn't list still gets an entry, so it is
        // visible and replaceable instead of showing an empty box.
        if (assigned.isNotEmpty && !knownHere)
          DropdownMenuItem(
            value: assigned,
            child: Text(
              '${labelFor(assigned, voices)} — not available on this engine',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.porchHoneyOf(context)),
            ),
          ),
        ...voices.map(
          (v) => DropdownMenuItem(
            value: v.id,
            child: Text(
              '${v.gender == 'Male'
                  ? '♂ '
                  : v.gender == 'Female'
                  ? '♀ '
                  : '⚬ '}'
              '${v.name}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
      onChanged: (v) => onChanged(v ?? ''),
    );
  }
}
