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

part of 'tts_settings_dialog.dart';

/// TTS engine selector — the segmented control (Kokoro/OpenAI/ElevenLabs/
/// Piper) shown at the top of [TtsSettingsDialog]. Extracted verbatim from
/// the dialog's inline builders during the god-file split (was over the
/// 500-line cap); direct state access via the extension preserves behavior.
extension _TtsEngineSection on _TtsSettingsDialogState {
  /// Amber notice naming the open character when THEIR voice overrides the
  /// global one, with a jump to where it can be changed. Renders nothing
  /// when no character is open or the character follows the global voice —
  /// the common case must stay quiet.
  Widget _buildCharacterOverrideNotice(
    BuildContext context,
    List<TtsVoiceInfo> voices,
  ) {
    // Chat is optional in the tree — Settings can open without one, and then
    // there is no "open character" to warn about, so the notice is simply
    // absent rather than an exception that takes the dialog down with it.
    CharacterCard? character;
    try {
      character = Provider.of<ChatService>(
        context,
        listen: false,
      ).activeCharacter;
    } on ProviderNotFoundException {
      character = null;
    }
    final assigned = character?.ttsVoice ?? '';
    if (character == null || assigned.isEmpty) return const SizedBox.shrink();

    final amber = AppColors.porchAmberOf(context);
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: amber.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.record_voice_over, size: 16, color: amber),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${character.name} has their own voice '
              '(${CharacterVoicePicker.labelFor(assigned, voices)}), so the '
              'voice above will not be used for them. Change it in Edit '
              'Character → Details → Voice.',
              style: TextStyle(
                color: AppColors.textPrimary(context),
                fontSize: 11,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Engine selector — segmented control style.
  Widget _buildEngineSelector(StorageService storage) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerOf(context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          _engineTab(storage, 'kokoro', '🔊 Kokoro', 'Local'),
          _engineTab(storage, 'openai', '☁️ OpenAI', 'Cloud API'),
          _engineTab(storage, 'elevenlabs', '🎙 ElevenLabs', 'Premium'),
          _engineTab(storage, 'piper', '📦 Piper', 'Lightweight'),
        ],
      ),
    );
  }

  Widget _engineTab(
    StorageService storage,
    String id,
    String label,
    String subtitle,
  ) {
    final selected = storage.ttsSettings.ttsEngine == id;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          storage.ttsSettings.setTtsEngine(id);
          // The old voice id belongs to the old engine and cannot carry
          // over, so it is cleared. speak() then reports "no voice
          // configured" through lastError (chat_page surfaces it) instead
          // of returning in silence — which is what made a post-switch TTS
          // look simply dead.
          storage.ttsSettings.setTtsVoiceModel('');
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.formMasterAccent.withValues(alpha: 0.3)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: selected
                ? Border.all(color: AppColors.formMasterAccent, width: 1)
                : null,
          ),
          child: Column(
            children: [
              Text(
                label,
                style: TextStyle(
                  color: selected
                      ? AppColors.formMasterAccent
                      : AppColors.textSecondary(context),
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  // Slightly brighter when selected, matching the original
                  // white38-vs-white24 hierarchy but on the AppColors scale.
                  color: selected
                      ? AppColors.textSecondary(context)
                      : AppColors.textTertiary(context),
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
