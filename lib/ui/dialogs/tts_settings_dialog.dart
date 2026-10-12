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
import 'package:front_porch_ai/services/elevenlabs_tts_engine.dart';
import 'package:front_porch_ai/ui/dialogs/tts_settings/tts_settings.dart';
import 'package:front_porch_ai/ui/dialogs/voice_browser_dialog.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Dialog for configuring TTS settings with multi-engine support.
class TtsSettingsDialog extends StatefulWidget {
  const TtsSettingsDialog({super.key});

  @override
  State<TtsSettingsDialog> createState() => _TtsSettingsDialogState();
}

class _TtsSettingsDialogState extends State<TtsSettingsDialog> {
  List<String> _installedPiperVoices = [];
  List<PiperVoice> _piperCatalog = const [];
  final _apiKeyController = TextEditingController();
  final _baseUrlController = TextEditingController();
  final _modelController = TextEditingController();
  bool _obscureApiKey = true;

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

  Future<void> _loadInstalledVoices() async {
    final vm = Provider.of<VoiceManager>(context, listen: false);
    final voices = await vm.listInstalledVoices();
    // Names for the Default Voice list, read only when there is one to name.
    final catalog = voices.isEmpty
        ? const <PiperVoice>[]
        : await vm.catalogForLabels();
    if (!mounted) return;
    setState(() {
      _installedPiperVoices = voices;
      _piperCatalog = catalog;
    });
  }

  void _toggleObscureApiKey() =>
      setState(() => _obscureApiKey = !_obscureApiKey);

  Future<void> _browsePiperVoices() async {
    await showDialog(
      context: context,
      builder: (_) => const VoiceBrowserDialog(),
    );
    await _loadInstalledVoices();

    // Also refresh TtsService's engine-aware voice cache
    // (especially important when user added custom Piper voices)
    final tts = Provider.of<TtsService>(context, listen: false);
    await tts.refreshAvailableVoices();
  }

  Future<void> _refreshElevenLabsVoices(TtsService tts) async {
    final engine = tts.activeEngine;
    if (engine is ElevenLabsTtsEngine) {
      final fetched = await engine.fetchVoices();
      if (mounted) setState(() {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Found ${fetched.length} voices'),
            backgroundColor: Colors.green, // theme-keep: fetch-result status
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
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
                        TtsEngineSelector(
                          selectedEngine: engineId,
                          onSelected: (id) {
                            storage.ttsSettings.setTtsEngine(id);
                            // The old voice id belongs to the old engine and
                            // cannot carry over, so it is cleared. speak()
                            // then reports "no voice configured" through
                            // lastError (chat_page surfaces it) instead of
                            // returning in silence — which is what made a
                            // post-switch TTS look simply dead.
                            storage.ttsSettings.setTtsVoiceModel('');
                          },
                        ),

                        const SizedBox(height: 20),

                        // ──── Engine-specific settings ────
                        if (engineId == 'kokoro')
                          KokoroTtsSettings(
                            settings: storage.ttsSettings,
                            tts: tts,
                            voices: voices,
                          ),
                        if (engineId == 'openai')
                          OpenAiTtsSettings(
                            settings: storage.ttsSettings,
                            voices: voices,
                            apiKeyController: _apiKeyController,
                            modelController: _modelController,
                            baseUrlController: _baseUrlController,
                            obscureApiKey: _obscureApiKey,
                            onToggleObscure: _toggleObscureApiKey,
                          ),
                        if (engineId == 'elevenlabs')
                          ElevenLabsTtsSettings(
                            settings: storage.ttsSettings,
                            voices: voices,
                            obscureApiKey: _obscureApiKey,
                            onToggleObscure: _toggleObscureApiKey,
                            onRefreshVoices: () =>
                                _refreshElevenLabsVoices(tts),
                          ),
                        if (engineId == 'piper')
                          PiperTtsSettings(
                            settings: storage.ttsSettings,
                            installedVoices: _installedPiperVoices,
                            catalog: _piperCatalog,
                            onBrowse: _browsePiperVoices,
                          ),

                        // The open character's own voice beats everything
                        // picked above — say so HERE, where the user is
                        // choosing, instead of leaving them to wonder why
                        // nothing changed (Discord, 2026-07-31).
                        CharacterVoiceOverrideNotice(voices: voices),

                        const SizedBox(height: 20),
                        TtsCommonSettings(
                          settings: storage.ttsSettings,
                          tts: tts,
                          engineId: engineId,
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
}
