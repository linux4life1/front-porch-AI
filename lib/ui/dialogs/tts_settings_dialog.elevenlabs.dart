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

/// ElevenLabs-specific settings block — API key, model dropdown, voice
/// picker + Refresh (via [ElevenLabsTtsEngine]), and the stability/
/// similarity/style sliders — for [TtsSettingsDialog]. Extracted verbatim
/// during the god-file split; direct state access via the extension
/// preserves behavior.
extension _TtsElevenLabsSection on _TtsSettingsDialogState {
  /// ElevenLabs-specific settings.
  List<Widget> _buildElevenLabsSettings(
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
        controller: TextEditingController(
          text: storage.ttsSettings.elevenlabsApiKey,
        ),
        obscureText: _obscureApiKey,
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
              _obscureApiKey ? Icons.visibility_off : Icons.visibility,
              color: AppColors.iconSecondary(context),
              size: 18,
            ),
            onPressed: () =>
                rebuildState(() => _obscureApiKey = !_obscureApiKey),
          ),
        ),
        onChanged: (val) => storage.ttsSettings.setElevenlabsApiKey(val.trim()),
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
        initialValue: storage.ttsSettings.elevenlabsModel,
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
          if (val != null) storage.ttsSettings.setElevenlabsModel(val);
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
                if (val != null) storage.ttsSettings.setTtsVoiceModel(val);
              },
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () async {
              final engine = tts.activeEngine;
              if (engine is ElevenLabsTtsEngine) {
                final fetched = await engine.fetchVoices();
                if (mounted) rebuildState(() {});
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Found ${fetched.length} voices'),
                      backgroundColor:
                          Colors.green, // theme-keep: fetch-result status
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              }
            },
            icon: const Icon(Icons.refresh, size: 14),
            label: const Text('Refresh'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.formMasterAccent,
              foregroundColor: AppColors.onChaosAccent,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            ),
          ),
        ],
      ),

      const SizedBox(height: 20),

      // ── Voice Settings Sliders ──
      Divider(color: AppColors.borderOf(context)),
      const SizedBox(height: 8),
      Text(
        'Voice Settings',
        style: TextStyle(
          color: AppColors.textSecondary(context),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 12),

      // Stability
      Row(
        children: [
          Text(
            'Stability',
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 12,
            ),
          ),
          const Spacer(),
          Text(
            (_dragElevenlabsStability ??
                    storage.ttsSettings.elevenlabsStability)
                .toStringAsFixed(2),
            style: const TextStyle(
              color: AppColors.formMasterAccent,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      Slider(
        value:
            _dragElevenlabsStability ?? storage.ttsSettings.elevenlabsStability,
        min: 0.0,
        max: 1.0,
        divisions: 20,
        activeColor: AppColors.formMasterAccent,
        inactiveColor: AppColors.borderOf(context),
        onChanged: (val) => rebuildState(() => _dragElevenlabsStability = val),
        onChangeEnd: (val) {
          _dragElevenlabsStability = null;
          storage.ttsSettings.setElevenlabsStability(val);
        },
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Expressive',
              style: TextStyle(
                color: AppColors.textTertiary(context),
                fontSize: 9,
              ),
            ),
            Text(
              'Consistent',
              style: TextStyle(
                color: AppColors.textTertiary(context),
                fontSize: 9,
              ),
            ),
          ],
        ),
      ),

      const SizedBox(height: 8),

      // Similarity Boost
      Row(
        children: [
          Text(
            'Similarity',
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 12,
            ),
          ),
          const Spacer(),
          Text(
            (_dragElevenlabsSimilarity ??
                    storage.ttsSettings.elevenlabsSimilarity)
                .toStringAsFixed(2),
            style: const TextStyle(
              color: AppColors.formMasterAccent,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      Slider(
        value:
            _dragElevenlabsSimilarity ??
            storage.ttsSettings.elevenlabsSimilarity,
        min: 0.0,
        max: 1.0,
        divisions: 20,
        activeColor: AppColors.formMasterAccent,
        inactiveColor: AppColors.borderOf(context),
        onChanged: (val) => rebuildState(() => _dragElevenlabsSimilarity = val),
        onChangeEnd: (val) {
          _dragElevenlabsSimilarity = null;
          storage.ttsSettings.setElevenlabsSimilarity(val);
        },
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Creative',
              style: TextStyle(
                color: AppColors.textTertiary(context),
                fontSize: 9,
              ),
            ),
            Text(
              'Faithful',
              style: TextStyle(
                color: AppColors.textTertiary(context),
                fontSize: 9,
              ),
            ),
          ],
        ),
      ),

      const SizedBox(height: 8),

      // Style
      Row(
        children: [
          Text(
            'Style',
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 12,
            ),
          ),
          const Spacer(),
          Text(
            (_dragElevenlabsStyle ?? storage.ttsSettings.elevenlabsStyle)
                .toStringAsFixed(2),
            style: const TextStyle(
              color: AppColors.formMasterAccent,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      Slider(
        value: _dragElevenlabsStyle ?? storage.ttsSettings.elevenlabsStyle,
        min: 0.0,
        max: 1.0,
        divisions: 20,
        activeColor: AppColors.formMasterAccent,
        inactiveColor: AppColors.borderOf(context),
        onChanged: (val) => rebuildState(() => _dragElevenlabsStyle = val),
        onChangeEnd: (val) {
          _dragElevenlabsStyle = null;
          storage.ttsSettings.setElevenlabsStyle(val);
        },
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Subtle',
              style: TextStyle(
                color: AppColors.textTertiary(context),
                fontSize: 9,
              ),
            ),
            Text(
              'Expressive',
              style: TextStyle(
                color: AppColors.textTertiary(context),
                fontSize: 9,
              ),
            ),
          ],
        ),
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
    ];
  }
}
