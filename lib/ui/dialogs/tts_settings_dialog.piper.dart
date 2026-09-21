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

/// Piper (legacy/lightweight) settings block — installed-voice picker,
/// the Browse action (opens [VoiceBrowserDialog] then refreshes caches),
/// and the built-in info card — for [TtsSettingsDialog]. Extracted verbatim
/// during the god-file split; direct state access via the extension
/// preserves behavior.
extension _TtsPiperSection on _TtsSettingsDialogState {
  /// Piper legacy settings.
  List<Widget> _buildPiperSettings(StorageService storage, TtsService tts) {
    return [
      Text(
        'Default Voice',
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
                  _installedPiperVoices.contains(
                    storage.ttsSettings.ttsVoiceModel,
                  )
                  ? storage.ttsSettings.ttsVoiceModel
                  : null,
              dropdownColor: AppColors.surfaceContainerOf(context),
              style: TextStyle(color: AppColors.textPrimary(context)),
              // isExpanded avoids a ~12px right-edge overflow on long
              // installed-voice filenames (matches the fix already on
              // the main tree so this doesn't reintroduce a merge conflict).
              isExpanded: true,
              decoration: InputDecoration(
                hintText: _installedPiperVoices.isEmpty
                    ? 'No voices installed'
                    : 'Select a voice',
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
              items: _installedPiperVoices
                  .map(
                    (v) => DropdownMenuItem(
                      value: v,
                      child: Text(v, overflow: TextOverflow.ellipsis),
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
              await showDialog(
                context: context,
                builder: (_) => const VoiceBrowserDialog(),
              );
              await _loadInstalledVoices();

              // Also refresh TtsService's engine-aware voice cache
              // (especially important when user added custom Piper voices)
              final tts = Provider.of<TtsService>(context, listen: false);
              await tts.refreshAvailableVoices();
            },
            icon: const Icon(Icons.download, size: 16),
            label: const Text('Browse'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.formMasterAccent,
              foregroundColor: AppColors.onChaosAccent,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            ),
          ),
        ],
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
            Icon(
              Icons.check_circle,
              color: AppColors.resolve(
                context,
                AppColors.logReady,
                AppColors.bondHighLight,
              ),
              size: 16,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Piper TTS is built in — voices download on install and '
                'play with the in-app engine.',
                style: TextStyle(
                  color: AppColors.resolve(
                    context,
                    AppColors.logReady,
                    AppColors.bondHighLight,
                  ),
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
