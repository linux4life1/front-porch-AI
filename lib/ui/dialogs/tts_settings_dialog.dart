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
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/elevenlabs_tts_engine.dart';
import 'package:front_porch_ai/ui/dialogs/voice_browser_dialog.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

// The per-engine settings blocks live in these `part of` files (extensions
// on _TtsSettingsDialogState) to keep every file under the 500-LOC cap —
// same pattern chat_service.dart / settings_page.dart use.
part 'tts_settings_dialog.engine.dart';
part 'tts_settings_dialog.kokoro.dart';
part 'tts_settings_dialog.openai.dart';
part 'tts_settings_dialog.piper.dart';
part 'tts_settings_dialog.elevenlabs.dart';

/// Dialog for configuring TTS settings with multi-engine support.
class TtsSettingsDialog extends StatefulWidget {
  const TtsSettingsDialog({super.key});

  @override
  State<TtsSettingsDialog> createState() => _TtsSettingsDialogState();
}

class _TtsSettingsDialogState extends State<TtsSettingsDialog> {
  List<String> _installedPiperVoices = [];
  final _apiKeyController = TextEditingController();
  final _baseUrlController = TextEditingController();
  final _modelController = TextEditingController();
  bool _obscureApiKey = true;

  // Slider drag tracking
  double? _dragTtsSpeechRate;
  double? _dragTtsConcurrency;
  double? _dragElevenlabsStability;
  double? _dragElevenlabsSimilarity;
  double? _dragElevenlabsStyle;

  @override
  void initState() {
    super.initState();
    _loadInstalledVoices();
    final storage = Provider.of<StorageService>(context, listen: false);
    _apiKeyController.text = storage.ttsSettings.openaiTtsApiKey;
    _baseUrlController.text = storage.ttsSettings.openaiTtsBaseUrl;
    _modelController.text = storage.ttsSettings.openaiTtsModel;
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _baseUrlController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  /// Re-exposes the protected [setState] for the `part of` extensions
  /// (tts_settings_dialog.*.dart) — same bridge settings_page.dart uses.
  void rebuildState(VoidCallback fn) => setState(fn);

  Future<void> _loadInstalledVoices() async {
    final vm = Provider.of<VoiceManager>(context, listen: false);
    final voices = await vm.listInstalledVoices();
    if (mounted) setState(() => _installedPiperVoices = voices);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<StorageService, TtsService>(
      builder: (context, storage, tts, _) {
        final engineId = storage.ttsSettings.ttsEngine;
        final voices = tts.activeVoices;

        return Dialog(
          backgroundColor: AppColors.surfaceOf(context),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            width: 540,
            constraints: const BoxConstraints(maxHeight: 650),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: AppColors.borderOf(context)),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.volume_up,
                        color: AppColors.formMasterAccent,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Text-to-Speech Settings',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary(context),
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: Icon(
                          Icons.close,
                          color: AppColors.iconSecondary(context),
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),

                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Enable TTS
                        SwitchListTile(
                          title: Text(
                            'Enable Text-to-Speech',
                            style: TextStyle(
                              color: AppColors.textPrimary(context),
                            ),
                          ),
                          subtitle: Text(
                            'Add speaker buttons to character messages',
                            style: TextStyle(
                              color: AppColors.textSecondary(context),
                              fontSize: 12,
                            ),
                          ),
                          value: storage.ttsSettings.ttsEnabled,
                          activeTrackColor: AppColors.formMasterAccent,
                          contentPadding: EdgeInsets.zero,
                          onChanged: (val) async {
                            await storage.ttsSettings.setTtsEnabled(val);
                            if (!val && context.mounted) {
                              context.read<TtsService>().releaseLocalEngine();
                            }
                          },
                        ),

                        const SizedBox(height: 20),

                        // ──── Engine selector ────
                        Text(
                          'TTS Engine',
                          style: TextStyle(
                            color: AppColors.textSecondary(context),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildEngineSelector(storage),

                        const SizedBox(height: 20),

                        // ──── Engine-specific settings ────
                        if (engineId == 'kokoro')
                          ..._buildKokoroSettings(storage, tts, voices),
                        if (engineId == 'openai')
                          ..._buildOpenAiSettings(storage, tts, voices),
                        if (engineId == 'elevenlabs')
                          ..._buildElevenLabsSettings(storage, tts, voices),
                        if (engineId == 'piper')
                          ..._buildPiperSettings(storage, tts),

                        // The open character's own voice beats everything
                        // picked above — say so HERE, where the user is
                        // choosing, instead of leaving them to wonder why
                        // nothing changed (Discord, 2026-07-31).
                        _buildCharacterOverrideNotice(context, voices),

                        const SizedBox(height: 20),

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
                          value:
                              _dragTtsSpeechRate ??
                              storage.ttsSettings.ttsSpeechRate,
                          min: 0.5,
                          max: 2.0,
                          divisions: 15,
                          activeColor: AppColors.formMasterAccent,
                          inactiveColor: AppColors.borderOf(context),
                          onChanged: (val) =>
                              setState(() => _dragTtsSpeechRate = val),
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
                                message:
                                    'Resident Kokoro workers (1-8).\nEach keeps the full model in RAM.\n2–4 is usually best for long narration.\nHigher values help when you have many short lines at once (power users only).',
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
                            onChanged: (val) =>
                                setState(() => _dragTtsConcurrency = val),
                            onChangeEnd: (val) {
                              _dragTtsConcurrency = null;
                              storage.ttsSettings.setTtsConcurrency(
                                val.round(),
                              );
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
                            style: TextStyle(
                              color: AppColors.textPrimary(context),
                            ),
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
                          onChanged: (val) =>
                              storage.ttsSettings.setTtsAutoPlay(val),
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
                            style: TextStyle(
                              color: AppColors.textPrimary(context),
                              fontSize: 14,
                            ),
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
                          onChanged: (val) =>
                              storage.ttsSettings.setTtsNarrateQuotedOnly(val),
                        ),
                        SwitchListTile(
                          title: Text(
                            'Ignore *text inside asterisks*',
                            style: TextStyle(
                              color: AppColors.textPrimary(context),
                              fontSize: 14,
                            ),
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
                          onChanged: (val) =>
                              storage.ttsSettings.setTtsIgnoreAsterisks(val),
                        ),
                        SwitchListTile(
                          title: Text(
                            'Replace curly quotation marks',
                            style: TextStyle(
                              color: AppColors.textPrimary(context),
                              fontSize: 14,
                            ),
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
                          onChanged: (val) =>
                              storage.ttsSettings.setTtsReplaceCurlyQuotes(val),
                        ),

                        const SizedBox(height: 16),

                        // Test button
                        if (storage.ttsSettings.ttsVoiceModel.isNotEmpty)
                          Center(
                            child: ElevatedButton.icon(
                              onPressed: tts.isSpeaking
                                  ? () => tts.stop()
                                  : () {
                                      final testText =
                                          storage
                                              .ttsSettings
                                              .ttsNarrateQuotedOnly
                                          ? '“Hello! This is a test of the text to speech system.” The quick brown fox jumps over the lazy dog.'
                                          : 'Hello! This is a test of the text to speech system. The quick brown fox jumps over the lazy dog.';
                                      tts.speak(testText);
                                    },
                              icon: Icon(
                                tts.isSpeaking ? Icons.stop : Icons.play_arrow,
                              ),
                              label: Text(
                                tts.isSpeaking ? 'Stop' : 'Test Voice',
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: tts.isSpeaking
                                    ? Colors
                                          .redAccent // theme-keep: playback status (stop), not chrome
                                    : Colors
                                          .green, // theme-keep: playback status (start)
                                foregroundColor: Colors
                                    .white, // theme-keep: contrast on status button
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
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
