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

/// OpenAI TTS-specific settings block (API key, model, base URL, voice
/// picker, billing note) for [TtsSettingsDialog]. Extracted verbatim during
/// the god-file split; direct state access via the extension preserves
/// behavior.
extension _TtsOpenAiSection on _TtsSettingsDialogState {
  /// OpenAI TTS-specific settings.
  List<Widget> _buildOpenAiSettings(
    StorageService storage,
    TtsService tts,
    List<TtsVoiceInfo> voices,
  ) {
    return [
      // API Key
      Text(
        'API Key',
        style: TextStyle(
          color: AppColors.textSecondary(context),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _apiKeyController,
        obscureText: _obscureApiKey,
        style: TextStyle(color: AppColors.textPrimary(context), fontSize: 13),
        decoration: InputDecoration(
          hintText: 'sk-...',
          hintStyle: TextStyle(color: AppColors.textTertiary(context)),
          filled: true,
          fillColor: AppColors.surfaceContainerOf(context),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          suffixIcon: IconButton(
            icon: Icon(
              _obscureApiKey ? Icons.visibility_off : Icons.visibility,
              color: AppColors.iconSecondary(context),
              size: 18,
            ),
            onPressed: () =>
                rebuildState(() => _obscureApiKey = !_obscureApiKey),
          ),
        ),
        onChanged: (val) => storage.ttsSettings.setOpenaiTtsApiKey(val.trim()),
      ),
      const SizedBox(height: 12),

      // Model
      Text(
        'Model',
        style: TextStyle(
          color: AppColors.textSecondary(context),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        'OpenAI uses tts-1 or tts-1-hd. Other providers may differ.',
        style: TextStyle(color: AppColors.textTertiary(context), fontSize: 11),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _modelController,
        style: TextStyle(color: AppColors.textPrimary(context), fontSize: 13),
        decoration: InputDecoration(
          hintText: 'tts-1',
          hintStyle: TextStyle(color: AppColors.textTertiary(context)),
          filled: true,
          fillColor: AppColors.surfaceContainerOf(context),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
        ),
        onChanged: (val) => storage.ttsSettings.setOpenaiTtsModel(val.trim()),
      ),
      const SizedBox(height: 12),

      // Base URL
      Text(
        'API Base URL',
        style: TextStyle(
          color: AppColors.textSecondary(context),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        'Change this to use an OpenAI-compatible TTS provider',
        style: TextStyle(color: AppColors.textTertiary(context), fontSize: 11),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _baseUrlController,
        style: TextStyle(color: AppColors.textPrimary(context), fontSize: 13),
        decoration: InputDecoration(
          hintText: 'https://api.openai.com/v1',
          hintStyle: TextStyle(color: AppColors.textTertiary(context)),
          filled: true,
          fillColor: AppColors.surfaceContainerOf(context),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          suffixIcon: IconButton(
            icon: Icon(
              Icons.restore,
              color: AppColors.iconSecondary(context),
              size: 18,
            ),
            tooltip: 'Reset to OpenAI default',
            onPressed: () {
              _baseUrlController.text = 'https://api.openai.com/v1';
              storage.ttsSettings.setOpenaiTtsBaseUrl(
                'https://api.openai.com/v1',
              );
            },
          ),
        ),
        onChanged: (val) => storage.ttsSettings.setOpenaiTtsBaseUrl(val.trim()),
      ),
      const SizedBox(height: 12),

      // Voice
      Text(
        'Voice',
        style: TextStyle(
          color: AppColors.textSecondary(context),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        initialValue:
            voices.any((v) => v.id == storage.ttsSettings.ttsVoiceModel)
            ? storage.ttsSettings.ttsVoiceModel
            : null,
        dropdownColor: AppColors.surfaceContainerOf(context),
        style: TextStyle(color: AppColors.textPrimary(context)),
        isExpanded: true,
        decoration: InputDecoration(
          hintText: 'Select a voice',
          hintStyle: TextStyle(color: AppColors.textTertiary(context)),
          filled: true,
          fillColor: AppColors.surfaceContainerOf(context),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
        ),
        items: voices
            .map(
              (v) => DropdownMenuItem(
                value: v.id,
                child: Row(
                  children: [
                    Text(
                      v.gender == 'Female'
                          ? '♀ '
                          : v.gender == 'Male'
                          ? '♂ '
                          : '⚬ ',
                      style: TextStyle(
                        // theme-keep: voice-gender marker dot, a fixed
                        // pink/cyan pairing independent of the app theme
                        color: v.gender == 'Female'
                            ? Colors.pinkAccent
                            : Colors.cyanAccent,
                        fontSize: 13,
                      ),
                    ),
                    Text(v.name),
                    const SizedBox(width: 6),
                    Text(
                      '(${v.gender})',
                      style: TextStyle(
                        color: AppColors.textTertiary(context),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
        onChanged: (val) {
          if (val != null) storage.ttsSettings.setTtsVoiceModel(val);
        },
      ),

      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerOf(context),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.cloud_outlined,
              color: Colors.amber, // theme-keep: billing warning, not chrome
              size: 16,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Requires an OpenAI API key. Usage is billed per character.',
                style: TextStyle(
                  color: AppColors.textTertiary(context),
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    ];
  }
}
