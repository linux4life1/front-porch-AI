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

extension _TtsCommonSettings on _TtsSettingsDialogState {
  List<Widget> _buildCommonSettings(
    StorageService storage,
    TtsService tts,
    String engineId,
  ) {
    return [
      // ──── Common settings ────
      // Speech rate
      Row(
        children: [
          Text(
            'Speech Rate',
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Text(
            '${storage.ttsSettings.ttsSpeechRate.toStringAsFixed(1)}x',
            style: const TextStyle(
              color: AppColors.formMasterAccent,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      Slider(
        value: _dragTtsSpeechRate ?? storage.ttsSettings.ttsSpeechRate,
        min: 0.5,
        max: 2.0,
        divisions: 15,
        activeColor: AppColors.formMasterAccent,
        inactiveColor: AppColors.borderOf(context),
        onChanged: (val) => rebuildState(() => _dragTtsSpeechRate = val),
        onChangeEnd: (val) {
          _dragTtsSpeechRate = null;
          storage.ttsSettings.setTtsSpeechRate(val);
        },
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Stack(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '0.5x',
                style: TextStyle(
                  color: AppColors.textTertiary(context),
                  fontSize: 10,
                ),
              ),
            ),
            // 1.0 is at (1.0 - 0.5) / (2.0 - 0.5) = 0.333 of the range
            // Convert to -1..1 alignment: 0.333 * 2 - 1 = -0.333
            Align(
              alignment: const Alignment(-0.333, 0),
              child: Text(
                '1.0x',
                style: TextStyle(
                  color: AppColors.textTertiary(context),
                  fontSize: 10,
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '2.0x',
                style: TextStyle(
                  color: AppColors.textTertiary(context),
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ),
      ),

      const SizedBox(height: 16),

      // Concurrency (only for Kokoro/OpenAI)
      if (engineId != 'piper') ...[
        Row(
          children: [
            Text(
              'TTS Workers',
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 6),
            Tooltip(
              message: 'Resident Kokoro workers (1-8).\nEach keeps the full model in RAM.\n2–4 is usually best for long narration.\nHigher values help when you have many short lines at once (power users only).',
              child: Icon(
                Icons.info_outline,
                color: AppColors.iconSecondary(context),
                size: 14,
              ),
            ),
            const Spacer(),
            Text(
              '${(_dragTtsConcurrency ?? storage.ttsSettings.ttsConcurrency.toDouble()).round()} workers',
              style: const TextStyle(
                color: AppColors.formMasterAccent,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        Slider(
          value:
              _dragTtsConcurrency ??
              storage.ttsSettings.ttsConcurrency.toDouble(),
          min: 1,
          max: 8,
          divisions: 7,
          activeColor: AppColors.formMasterAccent,
          inactiveColor: AppColors.borderOf(context),
          onChanged: (val) => rebuildState(() => _dragTtsConcurrency = val),
          onChangeEnd: (val) {
            _dragTtsConcurrency = null;
            storage.ttsSettings.setTtsConcurrency(val.round());
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '1',
                style: TextStyle(
                  color: AppColors.textTertiary(context),
                  fontSize: 10,
                ),
              ),
              Text(
                '~${_ramForWorkers(storage.ttsSettings.ttsConcurrency)} RAM',
                style: TextStyle(
                  color: AppColors.textTertiary(context),
                  fontSize: 10,
                ),
              ),
              Text(
                '8',
                style: TextStyle(
                  color: AppColors.textTertiary(context),
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ],

      const SizedBox(height: 16),

      // Auto-play
      SwitchListTile(
        title: Text(
          'Auto-Play',
          style: TextStyle(color: AppColors.textPrimary(context)),
        ),
        subtitle: Text(
          'Automatically speak new character messages',
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 12,
          ),
        ),
        value: storage.ttsSettings.ttsAutoPlay,
        activeTrackColor: AppColors.formMasterAccent,
        contentPadding: EdgeInsets.zero,
        onChanged: (val) => storage.ttsSettings.setTtsAutoPlay(val),
      ),

      const SizedBox(height: 8),

      // ──── Narration Filters ────
      Divider(color: AppColors.borderOf(context)),
      const SizedBox(height: 4),
      Text(
        'Narration Filters',
        style: TextStyle(
          color: AppColors.textSecondary(context),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 4),
      SwitchListTile(
        title: Text(
          'Only narrate "quotes"',
          style: TextStyle(color: AppColors.textPrimary(context), fontSize: 14),
        ),
        subtitle: Text(
          'TTS will only read text inside quotation marks',
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 11,
          ),
        ),
        value: storage.ttsSettings.ttsNarrateQuotedOnly,
        activeTrackColor: AppColors.formMasterAccent,
        contentPadding: EdgeInsets.zero,
        dense: true,
        onChanged: (val) => storage.ttsSettings.setTtsNarrateQuotedOnly(val),
      ),
      SwitchListTile(
        title: Text(
          'Ignore *text inside asterisks*',
          style: TextStyle(color: AppColors.textPrimary(context), fontSize: 14),
        ),
        subtitle: Text(
          'TTS will skip all narration in *asterisks*, even quotes',
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 11,
          ),
        ),
        value: storage.ttsSettings.ttsIgnoreAsterisks,
        activeTrackColor: AppColors.formMasterAccent,
        contentPadding: EdgeInsets.zero,
        dense: true,
        onChanged: (val) => storage.ttsSettings.setTtsIgnoreAsterisks(val),
      ),
      SwitchListTile(
        title: Text(
          'Replace curly quotation marks',
          style: TextStyle(color: AppColors.textPrimary(context), fontSize: 14),
        ),
        subtitle: Text(
          'Converts “curly quotes” to "straight quotes" before sending to TTS',
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 11,
          ),
        ),
        value: storage.ttsSettings.ttsReplaceCurlyQuotes,
        activeTrackColor: AppColors.formMasterAccent,
        contentPadding: EdgeInsets.zero,
        dense: true,
        onChanged: (val) => storage.ttsSettings.setTtsReplaceCurlyQuotes(val),
      ),

      const SizedBox(height: 16),

      // Test button
      if (storage.ttsSettings.ttsVoiceModel.isNotEmpty)
        Center(
          child: ElevatedButton.icon(
            onPressed: tts.isSpeaking
                ? () => tts.stop()
                : () {
                    final testText = storage.ttsSettings.ttsNarrateQuotedOnly
                        ? '“Hello! This is a test of the text to speech system.” The quick brown fox jumps over the lazy dog.'
                        : 'Hello! This is a test of the text to speech system. The quick brown fox jumps over the lazy dog.';
                    tts.speak(testText);
                  },
            icon: Icon(tts.isSpeaking ? Icons.stop : Icons.play_arrow),
            label: Text(tts.isSpeaking ? 'Stop' : 'Test Voice'),
            style: ElevatedButton.styleFrom(
              backgroundColor: tts.isSpeaking
                  ? Colors
                        .redAccent // theme-keep: playback status (stop), not chrome
                  : Colors.green, // theme-keep: playback status (start)
              foregroundColor:
                  Colors.white, // theme-keep: contrast on status button
            ),
          ),
        ),
    ];
  }

  String _ramForWorkers(int workers) {
    // Rough estimate: ~350 MB per resident Kokoro worker (model + overhead)
    final ramMB = workers * 350;
    if (ramMB >= 1000) {
      return '${(ramMB / 1000).toStringAsFixed(1)} GB';
    }
    return '$ramMB MB';
  }
}
