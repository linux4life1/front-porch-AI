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
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/voice_manager.dart';
import 'package:front_porch_ai/services/tts_service.dart';
import 'package:front_porch_ai/services/tts_voice_info.dart';
import 'package:front_porch_ai/services/elevenlabs_tts_engine.dart';
import 'package:front_porch_ai/ui/dialogs/voice_browser_dialog.dart';

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
    _apiKeyController.text = storage.openaiTtsApiKey;
    _baseUrlController.text = storage.openaiTtsBaseUrl;
    _modelController.text = storage.openaiTtsModel;
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _baseUrlController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  Future<void> _loadInstalledVoices() async {
    final vm = Provider.of<VoiceManager>(context, listen: false);
    final voices = await vm.listInstalledVoices();
    if (mounted) setState(() => _installedPiperVoices = voices);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<StorageService, TtsService>(
      builder: (context, storage, tts, _) {
        final engineId = storage.ttsEngine;
        final voices = tts.activeVoices;

        return Dialog(
          backgroundColor: const Color(0xFF1F2937),
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
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: Colors.white10)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.volume_up, color: Colors.blueAccent),
                      const SizedBox(width: 12),
                      const Text(
                        'Text-to-Speech Settings',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white54),
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
                          title: const Text(
                            'Enable Text-to-Speech',
                            style: TextStyle(color: Colors.white),
                          ),
                          subtitle: const Text(
                            'Add speaker buttons to character messages',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                          value: storage.ttsEnabled,
                          activeTrackColor: Colors.blueAccent,
                          contentPadding: EdgeInsets.zero,
                          onChanged: (val) => storage.setTtsEnabled(val),
                        ),

                        const SizedBox(height: 20),

                        // ──── Engine selector ────
                        const Text(
                          'TTS Engine',
                          style: TextStyle(
                            color: Colors.white54,
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

                        const SizedBox(height: 20),

                        // ──── Common settings ────
                        // Speech rate
                        Row(
                          children: [
                            const Text(
                              'Speech Rate',
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '${storage.ttsSpeechRate.toStringAsFixed(1)}x',
                              style: const TextStyle(
                                color: Colors.blueAccent,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: _dragTtsSpeechRate ?? storage.ttsSpeechRate,
                          min: 0.5,
                          max: 2.0,
                          divisions: 15,
                          activeColor: Colors.blueAccent,
                          inactiveColor: Colors.white12,
                          onChanged: (val) => setState(() => _dragTtsSpeechRate = val),
                          onChangeEnd: (val) {
                            _dragTtsSpeechRate = null;
                            storage.setTtsSpeechRate(val);
                          },
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Stack(
                            children: [
                              const Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  '0.5x',
                                  style: TextStyle(
                                    color: Colors.white24,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                              // 1.0 is at (1.0 - 0.5) / (2.0 - 0.5) = 0.333 of the range
                              // Convert to -1..1 alignment: 0.333 * 2 - 1 = -0.333
                              const Align(
                                alignment: Alignment(-0.333, 0),
                                child: Text(
                                  '1.0x',
                                  style: TextStyle(
                                    color: Colors.white24,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                              const Align(
                                alignment: Alignment.centerRight,
                                child: Text(
                                  '2.0x',
                                  style: TextStyle(
                                    color: Colors.white24,
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
                              const Text(
                                'TTS Workers',
                                style: TextStyle(
                                  color: Colors.white54,
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
                                  color: Colors.white24,
                                  size: 14,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '${(_dragTtsConcurrency ?? storage.ttsConcurrency.toDouble()).round()} workers',
                                style: const TextStyle(
                                  color: Colors.blueAccent,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          Slider(
                            value: _dragTtsConcurrency ?? storage.ttsConcurrency.toDouble(),
                            min: 1,
                            max: 8,
                            divisions: 7,
                            activeColor: Colors.blueAccent,
                            inactiveColor: Colors.white12,
                            onChanged: (val) => setState(() => _dragTtsConcurrency = val),
                            onChangeEnd: (val) {
                              _dragTtsConcurrency = null;
                              storage.setTtsConcurrency(val.round());
                            },
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  '1',
                                  style: TextStyle(
                                    color: Colors.white24,
                                    fontSize: 10,
                                  ),
                                ),
                                Text(
                                  '~${_ramForWorkers(storage.ttsConcurrency)} RAM',
                                  style: const TextStyle(
                                    color: Colors.white24,
                                    fontSize: 10,
                                  ),
                                ),
                                const Text(
                                  '8',
                                  style: TextStyle(
                                    color: Colors.white24,
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
                          title: const Text(
                            'Auto-Play',
                            style: TextStyle(color: Colors.white),
                          ),
                          subtitle: const Text(
                            'Automatically speak new character messages',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                          value: storage.ttsAutoPlay,
                          activeTrackColor: Colors.blueAccent,
                          contentPadding: EdgeInsets.zero,
                          onChanged: (val) => storage.setTtsAutoPlay(val),
                        ),

                        const SizedBox(height: 8),

                        // ──── Narration Filters ────
                        const Divider(color: Colors.white12),
                        const SizedBox(height: 4),
                        const Text(
                          'Narration Filters',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        SwitchListTile(
                          title: const Text(
                            'Only narrate "quotes"',
                            style: TextStyle(color: Colors.white, fontSize: 14),
                          ),
                          subtitle: const Text(
                            'TTS will only read text inside quotation marks',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                            ),
                          ),
                          value: storage.ttsNarrateQuotedOnly,
                          activeTrackColor: Colors.blueAccent,
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          onChanged: (val) =>
                              storage.setTtsNarrateQuotedOnly(val),
                        ),
                        SwitchListTile(
                          title: const Text(
                            'Ignore *text inside asterisks*',
                            style: TextStyle(color: Colors.white, fontSize: 14),
                          ),
                          subtitle: const Text(
                            'TTS will skip all narration in *asterisks*, even quotes',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                            ),
                          ),
                          value: storage.ttsIgnoreAsterisks,
                          activeTrackColor: Colors.blueAccent,
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          onChanged: (val) =>
                              storage.setTtsIgnoreAsterisks(val),
                        ),

                        const SizedBox(height: 16),

                        // Test button
                        if (storage.ttsVoiceModel.isNotEmpty)
                          Center(
                            child: ElevatedButton.icon(
                              onPressed: tts.isSpeaking
                                  ? () => tts.stop()
                                  : () {
                                      final testText =
                                          storage.ttsNarrateQuotedOnly
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
                                    ? Colors.redAccent
                                    : Colors.green,
                                foregroundColor: Colors.white,
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

  /// Engine selector — segmented control style.
  Widget _buildEngineSelector(StorageService storage) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black26,
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
    final selected = storage.ttsEngine == id;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          storage.setTtsEngine(id);
          // Clear voice model when switching engines
          storage.setTtsVoiceModel('');
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? Colors.blueAccent.withValues(alpha: 0.3)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: selected
                ? Border.all(color: Colors.blueAccent, width: 1)
                : null,
          ),
          child: Column(
            children: [
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.blueAccent : Colors.white54,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: selected ? Colors.white38 : Colors.white24,
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
          color: Colors.black26,
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
                          color: Colors.blueAccent,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Downloading Kokoro model (${(tts.modelDownloadProgress * 100).toInt()}%)...',
                        style: const TextStyle(
                          color: Colors.blueAccent,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: tts.modelDownloadProgress,
                    backgroundColor: Colors.white12,
                    color: Colors.blueAccent,
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
                        Icon(Icons.check_circle, color: Colors.green, size: 16),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Kokoro model ready ✓ — all voices included',
                            style: TextStyle(color: Colors.green, fontSize: 11),
                          ),
                        ),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      const Icon(
                        Icons.download_rounded,
                        color: Colors.blueAccent,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          '~300MB download required (includes all voices)',
                          style: TextStyle(color: Colors.white38, fontSize: 11),
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
                                    ? Colors.green
                                    : Colors.redAccent,
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.download, size: 14),
                        label: const Text('Download'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          foregroundColor: Colors.white,
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
      const Text(
        'Voice',
        style: TextStyle(
          color: Colors.white54,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        initialValue: voices.any((v) => v.id == storage.ttsVoiceModel)
            ? storage.ttsVoiceModel
            : null,
        dropdownColor: const Color(0xFF374151),
        style: const TextStyle(color: Colors.white),
        isExpanded: true,
        decoration: InputDecoration(
          hintText: 'Select a voice',
          hintStyle: const TextStyle(color: Colors.white30),
          filled: true,
          fillColor: Colors.black26,
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
                  color: Colors.blueAccent,
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
            storage.setTtsVoiceModel(val);
          }
        },
      ),
      const SizedBox(height: 6),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          'All voices are included in the base model — no additional downloads needed.',
          style: TextStyle(color: Colors.white24, fontSize: 10),
        ),
      ),
    ];
  }

  /// OpenAI TTS-specific settings.
  List<Widget> _buildOpenAiSettings(
    StorageService storage,
    TtsService tts,
    List<TtsVoiceInfo> voices,
  ) {
    return [
      // API Key
      const Text(
        'API Key',
        style: TextStyle(
          color: Colors.white54,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _apiKeyController,
        obscureText: _obscureApiKey,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: InputDecoration(
          hintText: 'sk-...',
          hintStyle: const TextStyle(color: Colors.white24),
          filled: true,
          fillColor: Colors.black26,
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
              color: Colors.white38,
              size: 18,
            ),
            onPressed: () => setState(() => _obscureApiKey = !_obscureApiKey),
          ),
        ),
        onChanged: (val) => storage.setOpenaiTtsApiKey(val.trim()),
      ),
      const SizedBox(height: 12),

      // Model
      const Text(
        'Model',
        style: TextStyle(
          color: Colors.white54,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 4),
      const Text(
        'OpenAI uses tts-1 or tts-1-hd. Other providers may differ.',
        style: TextStyle(color: Colors.white24, fontSize: 11),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _modelController,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: InputDecoration(
          hintText: 'tts-1',
          hintStyle: const TextStyle(color: Colors.white24),
          filled: true,
          fillColor: Colors.black26,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
        ),
        onChanged: (val) => storage.setOpenaiTtsModel(val.trim()),
      ),
      const SizedBox(height: 12),

      // Base URL
      const Text(
        'API Base URL',
        style: TextStyle(
          color: Colors.white54,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 4),
      const Text(
        'Change this to use an OpenAI-compatible TTS provider',
        style: TextStyle(color: Colors.white24, fontSize: 11),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _baseUrlController,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: InputDecoration(
          hintText: 'https://api.openai.com/v1',
          hintStyle: const TextStyle(color: Colors.white24),
          filled: true,
          fillColor: Colors.black26,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          suffixIcon: IconButton(
            icon: const Icon(Icons.restore, color: Colors.white38, size: 18),
            tooltip: 'Reset to OpenAI default',
            onPressed: () {
              _baseUrlController.text = 'https://api.openai.com/v1';
              storage.setOpenaiTtsBaseUrl('https://api.openai.com/v1');
            },
          ),
        ),
        onChanged: (val) => storage.setOpenaiTtsBaseUrl(val.trim()),
      ),
      const SizedBox(height: 12),

      // Voice
      const Text(
        'Voice',
        style: TextStyle(
          color: Colors.white54,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        initialValue: voices.any((v) => v.id == storage.ttsVoiceModel)
            ? storage.ttsVoiceModel
            : null,
        dropdownColor: const Color(0xFF374151),
        style: const TextStyle(color: Colors.white),
        isExpanded: true,
        decoration: InputDecoration(
          hintText: 'Select a voice',
          hintStyle: const TextStyle(color: Colors.white30),
          filled: true,
          fillColor: Colors.black26,
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
                            ? Colors.pinkAccent
                            : Colors.cyanAccent,
                        fontSize: 13,
                      ),
                    ),
                    Text(v.name),
                    const SizedBox(width: 6),
                    Text(
                      '(${v.gender})',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
        onChanged: (val) {
          if (val != null) storage.setTtsVoiceModel(val);
        },
      ),

      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.black26,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          children: [
            Icon(Icons.cloud_outlined, color: Colors.amber, size: 16),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Requires an OpenAI API key. Usage is billed per character.',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  /// Piper legacy settings.
  List<Widget> _buildPiperSettings(StorageService storage, TtsService tts) {
    return [
      const Text(
        'Default Voice',
        style: TextStyle(
          color: Colors.white54,
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
                  _installedPiperVoices.contains(storage.ttsVoiceModel)
                  ? storage.ttsVoiceModel
                  : null,
              dropdownColor: const Color(0xFF374151),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: _installedPiperVoices.isEmpty
                    ? 'No voices installed'
                    : 'Select a voice',
                hintStyle: const TextStyle(color: Colors.white30),
                filled: true,
                fillColor: Colors.black26,
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
                if (val != null) storage.setTtsVoiceModel(val);
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
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.black26,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              tts.isPiperAvailable ? Icons.check_circle : Icons.warning_amber,
              color: tts.isPiperAvailable ? Colors.greenAccent : Colors.amber,
              size: 16,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                tts.isPiperAvailable
                    ? 'Piper TTS engine is ready'
                    : 'Piper TTS engine not found. Requires bundled Piper binary.',
                style: TextStyle(
                  color: tts.isPiperAvailable
                      ? Colors.greenAccent
                      : Colors.amber,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  /// ElevenLabs-specific settings.
  List<Widget> _buildElevenLabsSettings(
    StorageService storage,
    TtsService tts,
    List<TtsVoiceInfo> voices,
  ) {
    return [
      // API Key
      const Text(
        'API Key',
        style: TextStyle(
          color: Colors.white54,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: TextEditingController(text: storage.elevenlabsApiKey),
        obscureText: _obscureApiKey,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Enter your ElevenLabs API key...',
          hintStyle: const TextStyle(color: Colors.white24),
          filled: true,
          fillColor: Colors.black26,
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
              color: Colors.white38,
              size: 18,
            ),
            onPressed: () => setState(() => _obscureApiKey = !_obscureApiKey),
          ),
        ),
        onChanged: (val) => storage.setElevenlabsApiKey(val.trim()),
      ),
      const SizedBox(height: 12),

      // Model
      const Text(
        'Model',
        style: TextStyle(
          color: Colors.white54,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        initialValue: storage.elevenlabsModel,
        dropdownColor: const Color(0xFF374151),
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          filled: true,
          fillColor: Colors.black26,
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
          if (val != null) storage.setElevenlabsModel(val);
        },
      ),
      const SizedBox(height: 12),

      // Voice
      const Text(
        'Voice',
        style: TextStyle(
          color: Colors.white54,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: voices.any((v) => v.id == storage.ttsVoiceModel)
                  ? storage.ttsVoiceModel
                  : null,
              dropdownColor: const Color(0xFF374151),
              style: const TextStyle(color: Colors.white),
              isExpanded: true,
              decoration: InputDecoration(
                hintText: 'Select a voice',
                hintStyle: const TextStyle(color: Colors.white30),
                filled: true,
                fillColor: Colors.black26,
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
                if (val != null) storage.setTtsVoiceModel(val);
              },
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () async {
              final engine = tts.activeEngine;
              if (engine is ElevenLabsTtsEngine) {
                final fetched = await engine.fetchVoices();
                if (mounted) setState(() {});
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Found ${fetched.length} voices'),
                      backgroundColor: Colors.green,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              }
            },
            icon: const Icon(Icons.refresh, size: 14),
            label: const Text('Refresh'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            ),
          ),
        ],
      ),

      const SizedBox(height: 20),

      // ── Voice Settings Sliders ──
      const Divider(color: Colors.white12),
      const SizedBox(height: 8),
      const Text(
        'Voice Settings',
        style: TextStyle(
          color: Colors.white54,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 12),

      // Stability
      Row(
        children: [
          const Text(
            'Stability',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const Spacer(),
          Text(
            (_dragElevenlabsStability ?? storage.elevenlabsStability).toStringAsFixed(2),
            style: const TextStyle(
              color: Colors.blueAccent,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      Slider(
        value: _dragElevenlabsStability ?? storage.elevenlabsStability,
        min: 0.0,
        max: 1.0,
        divisions: 20,
        activeColor: Colors.blueAccent,
        inactiveColor: Colors.white12,
        onChanged: (val) => setState(() => _dragElevenlabsStability = val),
          onChangeEnd: (val) {
            _dragElevenlabsStability = null;
            storage.setElevenlabsStability(val);
          },
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Expressive',
              style: TextStyle(color: Colors.white24, fontSize: 9),
            ),
            Text(
              'Consistent',
              style: TextStyle(color: Colors.white24, fontSize: 9),
            ),
          ],
        ),
      ),

      const SizedBox(height: 8),

      // Similarity Boost
      Row(
        children: [
          const Text(
            'Similarity',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const Spacer(),
          Text(
            (_dragElevenlabsSimilarity ?? storage.elevenlabsSimilarity).toStringAsFixed(2),
            style: const TextStyle(
              color: Colors.blueAccent,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      Slider(
        value: _dragElevenlabsSimilarity ?? storage.elevenlabsSimilarity,
        min: 0.0,
        max: 1.0,
        divisions: 20,
        activeColor: Colors.blueAccent,
        inactiveColor: Colors.white12,
        onChanged: (val) => setState(() => _dragElevenlabsSimilarity = val),
          onChangeEnd: (val) {
            _dragElevenlabsSimilarity = null;
            storage.setElevenlabsSimilarity(val);
          },
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Creative',
              style: TextStyle(color: Colors.white24, fontSize: 9),
            ),
            Text(
              'Faithful',
              style: TextStyle(color: Colors.white24, fontSize: 9),
            ),
          ],
        ),
      ),

      const SizedBox(height: 8),

      // Style
      Row(
        children: [
          const Text(
            'Style',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const Spacer(),
          Text(
            (_dragElevenlabsStyle ?? storage.elevenlabsStyle).toStringAsFixed(2),
            style: const TextStyle(
              color: Colors.blueAccent,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      Slider(
        value: _dragElevenlabsStyle ?? storage.elevenlabsStyle,
        min: 0.0,
        max: 1.0,
        divisions: 20,
        activeColor: Colors.blueAccent,
        inactiveColor: Colors.white12,
        onChanged: (val) => setState(() => _dragElevenlabsStyle = val),
          onChangeEnd: (val) {
            _dragElevenlabsStyle = null;
            storage.setElevenlabsStyle(val);
          },
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Subtle',
              style: TextStyle(color: Colors.white24, fontSize: 9),
            ),
            Text(
              'Expressive',
              style: TextStyle(color: Colors.white24, fontSize: 9),
            ),
          ],
        ),
      ),

      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.black26,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          children: [
            Icon(Icons.cloud_outlined, color: Colors.amber, size: 16),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Requires an ElevenLabs API key. Free tier: ~10 min/month.',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ),
          ],
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
