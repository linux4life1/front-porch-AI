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

/// Kokoro-specific settings block (model download status card + the
/// language-grouped voice picker) for [TtsSettingsDialog]. Extracted
/// verbatim during the god-file split; direct state access via the
/// extension preserves behavior.
extension _TtsKokoroSection on _TtsSettingsDialogState {
  /// Kokoro-specific settings.
  List<Widget> _buildKokoroSettings(
    StorageService storage,
    TtsService tts,
    List<TtsVoiceInfo> voices,
  ) {
    // Group voices by language
    final languages = <String, List<TtsVoiceInfo>>{};
    for (final v in voices) {
      languages.putIfAbsent(v.language, () => []).add(v);
    }

    return [
      // ── Model status (shown first so user knows state before picking voice) ──
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerOf(context),
          borderRadius: BorderRadius.circular(8),
        ),
        child: tts.isDownloadingModel
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.formMasterAccent,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Downloading Kokoro model (${(tts.modelDownloadProgress * 100).toInt()}%)...',
                        style: const TextStyle(
                          color: AppColors.formMasterAccent,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: tts.modelDownloadProgress,
                    backgroundColor: AppColors.borderOf(context),
                    color: AppColors.formMasterAccent,
                    minHeight: 4,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ],
              )
            : FutureBuilder<bool>(
                future: tts.isModelDownloaded(),
                builder: (context, snapshot) {
                  final isDownloaded = snapshot.data == true;
                  if (isDownloaded) {
                    return const Row(
                      children: [
                        Icon(
                          Icons.check_circle,
                          color: Colors
                              .green, // theme-keep: engine-ready status, not chrome
                          size: 16,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Kokoro model ready ✓ — all voices included',
                            style: TextStyle(
                              color: Colors
                                  .green, // theme-keep: engine-ready status
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      const Icon(
                        Icons.download_rounded,
                        color: AppColors.formMasterAccent,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '~300MB download required (includes all voices)',
                          style: TextStyle(
                            color: AppColors.textTertiary(context),
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () async {
                          final success = await tts.downloadModel();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  success
                                      ? 'Kokoro model ready!'
                                      : 'Download failed — check connection',
                                ),
                                backgroundColor: success
                                    ? Colors
                                          .green // theme-keep: download outcome status
                                    : Colors
                                          .redAccent, // theme-keep: download outcome status
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.download, size: 14),
                        label: const Text('Download'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.formMasterAccent,
                          foregroundColor: AppColors.onChaosAccent,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          textStyle: const TextStyle(fontSize: 12),
                          minimumSize: const Size(0, 30),
                        ),
                      ),
                    ],
                  );
                },
              ),
      ),

      const SizedBox(height: 16),

      // ── Voice selector ──
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
        items: languages.entries.expand((entry) {
          return [
            DropdownMenuItem<String>(
              enabled: false,
              value: '__header_${entry.key}',
              child: Text(
                entry.key,
                style: const TextStyle(
                  color: AppColors.formMasterAccent,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ...entry.value.map(
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
                    Text(v.name, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ),
          ];
        }).toList(),
        onChanged: (val) {
          if (val != null && !val.startsWith('__header_')) {
            storage.ttsSettings.setTtsVoiceModel(val);
          }
        },
      ),
      const SizedBox(height: 6),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          'All voices are included in the base model — no additional downloads '
          'needed. This is the default voice; a character with its own voice '
          'assigned keeps using that one.',
          style: TextStyle(
            color: AppColors.textTertiary(context),
            fontSize: 10,
          ),
        ),
      ),
    ];
  }
}
