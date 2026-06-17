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

import 'dart:io';
import 'settings_base.dart';

/// TTS engine, voice, speed, API keys, concurrency and related settings.
///
/// Lifted mechanically (Stage 7). All persistence + notify via base.
class TtsSettings with SettingsBase {
  bool _ttsEnabled = false;
  String _ttsEngine = 'kokoro'; // 'kokoro', 'openai', 'elevenlabs', 'piper'
  String _ttsVoiceModel =
      ''; // voice key, e.g. 'af_heart' or 'en_US-lessac-medium'
  double _ttsSpeechRate = 1.0;
  bool _ttsAutoPlay = false;
  String _openaiTtsApiKey = '';
  String _openaiTtsModel = 'tts-1'; // 'tts-1' or 'tts-1-hd'
  String _openaiTtsBaseUrl = 'https://api.openai.com/v1';
  String _elevenlabsApiKey = '';
  String _elevenlabsModel = 'eleven_flash_v2_5';
  double _elevenlabsStability = 0.5;
  double _elevenlabsSimilarity = 0.75;
  double _elevenlabsStyle = 0.0;
  bool _ttsNarrateQuotedOnly = false;
  bool _ttsIgnoreAsterisks = false;
  bool _ttsReplaceCurlyQuotes = false;
  int _ttsConcurrency = Platform.numberOfProcessors.clamp(1, 8);
  int _ttsAudioLookahead = 6;
  double _directorDelay = 15.0;

  bool get ttsEnabled => _ttsEnabled;
  String get ttsEngine => _ttsEngine;
  String get ttsVoiceModel => _ttsVoiceModel;
  double get ttsSpeechRate => _ttsSpeechRate;
  bool get ttsAutoPlay => _ttsAutoPlay;
  String get openaiTtsApiKey => _openaiTtsApiKey;
  String get openaiTtsModel => _openaiTtsModel;
  String get openaiTtsBaseUrl => _openaiTtsBaseUrl;
  String get elevenlabsApiKey => _elevenlabsApiKey;
  String get elevenlabsModel => _elevenlabsModel;
  double get elevenlabsStability => _elevenlabsStability;
  double get elevenlabsSimilarity => _elevenlabsSimilarity;
  double get elevenlabsStyle => _elevenlabsStyle;
  bool get ttsNarrateQuotedOnly => _ttsNarrateQuotedOnly;
  bool get ttsIgnoreAsterisks => _ttsIgnoreAsterisks;
  bool get ttsReplaceCurlyQuotes => _ttsReplaceCurlyQuotes;
  int get ttsConcurrency => _ttsConcurrency.clamp(1, 8);
  int get ttsAudioLookahead => _ttsAudioLookahead;
  double get directorDelay => _directorDelay;

  void load() {
    _ttsEnabled = prefs?.getBool(k('tts_enabled')) ?? false;
    _ttsEngine = prefs?.getString(k('tts_engine')) ?? 'kokoro';
    _ttsVoiceModel = prefs?.getString(k('tts_voice_model')) ?? '';
    _ttsSpeechRate = prefs?.getDouble(k('tts_speech_rate')) ?? 1.0;
    _ttsAutoPlay = prefs?.getBool(k('tts_auto_play')) ?? false;
    _openaiTtsApiKey = prefs?.getString(k('openai_tts_api_key')) ?? '';
    _ttsConcurrency =
        (prefs?.getInt(k('tts_concurrency')) ?? Platform.numberOfProcessors)
            .clamp(1, 8);
    _ttsAudioLookahead = prefs?.getInt(k('tts_audio_lookahead')) ?? 6;
    _openaiTtsModel = prefs?.getString(k('openai_tts_model')) ?? 'tts-1';
    _openaiTtsBaseUrl =
        prefs?.getString(k('openai_tts_base_url')) ??
        'https://api.openai.com/v1';
    _elevenlabsApiKey = prefs?.getString(k('elevenlabs_api_key')) ?? '';
    _elevenlabsModel =
        prefs?.getString(k('elevenlabs_model')) ?? 'eleven_flash_v2_5';
    _elevenlabsStability = prefs?.getDouble(k('elevenlabs_stability')) ?? 0.5;
    _elevenlabsSimilarity =
        prefs?.getDouble(k('elevenlabs_similarity')) ?? 0.75;
    _elevenlabsStyle = prefs?.getDouble(k('elevenlabs_style')) ?? 0.0;
    _ttsNarrateQuotedOnly =
        prefs?.getBool(k('tts_narrate_quoted_only')) ?? false;
    _ttsIgnoreAsterisks = prefs?.getBool(k('tts_ignore_asterisks')) ?? false;
    _ttsReplaceCurlyQuotes = prefs?.getBool(k('tts_replace_curly_quotes')) ?? false;
    _directorDelay = prefs?.getDouble(k('director_delay')) ?? 15.0;
  }

  Future<void> setTtsEnabled(bool value) async {
    _ttsEnabled = value;
    await prefs?.setBool(k('tts_enabled'), value);
    notify();
  }

  Future<void> setTtsEngine(String value) async {
    _ttsEngine = value;
    await prefs?.setString(k('tts_engine'), value);
    notify();
  }

  Future<void> setTtsVoiceModel(String value) async {
    _ttsVoiceModel = value;
    await prefs?.setString(k('tts_voice_model'), value);
    notify();
  }

  Future<void> setTtsSpeechRate(double value) async {
    _ttsSpeechRate = value;
    await prefs?.setDouble(k('tts_speech_rate'), value);
    notify();
  }

  Future<void> setTtsAutoPlay(bool value) async {
    _ttsAutoPlay = value;
    await prefs?.setBool(k('tts_auto_play'), value);
    notify();
  }

  Future<void> setOpenaiTtsApiKey(String value) async {
    _openaiTtsApiKey = value;
    await prefs?.setString(k('openai_tts_api_key'), value);
    notify();
  }

  Future<void> setOpenaiTtsModel(String value) async {
    _openaiTtsModel = value;
    await prefs?.setString(k('openai_tts_model'), value);
    notify();
  }

  Future<void> setOpenaiTtsBaseUrl(String value) async {
    _openaiTtsBaseUrl = value;
    await prefs?.setString(k('openai_tts_base_url'), value);
    notify();
  }

  Future<void> setElevenlabsApiKey(String value) async {
    _elevenlabsApiKey = value;
    await prefs?.setString(k('elevenlabs_api_key'), value);
    notify();
  }

  Future<void> setElevenlabsModel(String value) async {
    _elevenlabsModel = value;
    await prefs?.setString(k('elevenlabs_model'), value);
    notify();
  }

  Future<void> setElevenlabsStability(double value) async {
    _elevenlabsStability = value.clamp(0.0, 1.0);
    await prefs?.setDouble(k('elevenlabs_stability'), _elevenlabsStability);
    notify();
  }

  Future<void> setElevenlabsSimilarity(double value) async {
    _elevenlabsSimilarity = value.clamp(0.0, 1.0);
    await prefs?.setDouble(k('elevenlabs_similarity'), _elevenlabsSimilarity);
    notify();
  }

  Future<void> setElevenlabsStyle(double value) async {
    _elevenlabsStyle = value.clamp(0.0, 1.0);
    await prefs?.setDouble(k('elevenlabs_style'), _elevenlabsStyle);
    notify();
  }

  Future<void> setTtsNarrateQuotedOnly(bool value) async {
    _ttsNarrateQuotedOnly = value;
    await prefs?.setBool(k('tts_narrate_quoted_only'), value);
    notify();
  }

  Future<void> setTtsIgnoreAsterisks(bool value) async {
    _ttsIgnoreAsterisks = value;
    await prefs?.setBool(k('tts_ignore_asterisks'), value);
    notify();
  }

  Future<void> setTtsReplaceCurlyQuotes(bool value) async {
    _ttsReplaceCurlyQuotes = value;
    await prefs?.setBool(k('tts_replace_curly_quotes'), value);
    notify();
  }

  Future<void> setTtsConcurrency(int value) async {
    _ttsConcurrency = value.clamp(1, 8);
    await prefs?.setInt(k('tts_concurrency'), _ttsConcurrency);
    notify();
  }

  Future<void> setTtsAudioLookahead(int value) async {
    _ttsAudioLookahead = value.clamp(1, 32);
    await prefs?.setInt(k('tts_audio_lookahead'), _ttsAudioLookahead);
    notify();
  }

  Future<void> setDirectorDelay(double value) async {
    _directorDelay = value.clamp(0.5, 60.0);
    await prefs?.setDouble(k('director_delay'), _directorDelay);
    notify();
  }
}
