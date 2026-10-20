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
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/storage.dart';
import 'package:front_porch_ai/ui/dialogs/tts_settings/elevenlabs_voice_sliders.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';

/// ElevenLabs-specific settings block for the TTS settings dialog: API key,
/// model dropdown, voice picker + Refresh ([onRefreshVoices]), the voice
/// sliders and the billing note.
class ElevenLabsTtsSettings extends StatelessWidget {
  const ElevenLabsTtsSettings({
    super.key,
    required this.settings,
    required this.voices,
    required this.obscureApiKey,
    required this.onToggleObscure,
    required this.onRefreshVoices,
  });

  final TtsSettings settings;
  final List<TtsVoiceInfo> voices;
  final bool obscureApiKey;
  final VoidCallback onToggleObscure;
  final VoidCallback onRefreshVoices;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
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
          controller: TextEditingController(text: settings.elevenlabsApiKey),
          obscureText: obscureApiKey,
          style: TextStyle(color: AppColors.textPrimary(context), fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Enter your ElevenLabs API key...',
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
                obscureApiKey ? Icons.visibility_off : Icons.visibility,
                color: AppColors.iconSecondary(context),
                size: 18,
              ),
              onPressed: onToggleObscure,
            ),
          ),
          onChanged: (val) => settings.setElevenlabsApiKey(val.trim()),
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
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: settings.elevenlabsModel,
          dropdownColor: AppColors.surfaceContainerOf(context),
          style: TextStyle(color: AppColors.textPrimary(context)),
          // isExpanded avoids a ~12px right-edge overflow on longer model
          // labels (matches the fix already on the main tree so this doesn't
          // reintroduce a merge conflict).
          isExpanded: true,
          decoration: InputDecoration(
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
          items: const [
            DropdownMenuItem(
              value: 'eleven_flash_v2_5',
              child: Text('Flash v2.5 — fastest (~75ms)'),
            ),
            DropdownMenuItem(
              value: 'eleven_multilingual_v2',
              child: Text('Multilingual v2 — 29 languages'),
            ),
            DropdownMenuItem(
              value: 'eleven_v3',
              child: Text('v3 — best quality, 70+ languages'),
            ),
          ],
          onChanged: (val) {
            if (val != null) settings.setElevenlabsModel(val);
          },
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
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: voices.any((v) => v.id == settings.ttsVoiceModel)
                    ? settings.ttsVoiceModel
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
                                color: v.gender == 'Female'
                                    ? LegendColors.voiceFemaleOf(context)
                                    : LegendColors.voiceMaleOf(context),
                                fontSize: 13,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                v.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (val) {
                  if (val != null) settings.setTtsVoiceModel(val);
                },
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: onRefreshVoices,
              icon: const Icon(Icons.refresh, size: 14),
              label: const Text('Refresh'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.formAccentOf(context),
                foregroundColor: AppColors.onAccentOf(context),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),

        // ── Voice Settings Sliders ──
        ElevenLabsVoiceSliders(settings: settings),

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
                  'Requires an ElevenLabs API key. Free tier: ~10 min/month.',
                  style: TextStyle(
                    color: AppColors.textTertiary(context),
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
