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

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:front_porch_ai/services/tts_engine.dart';
import 'package:front_porch_ai/services/tts_voice_info.dart';

/// Exception thrown when ElevenLabs API returns a recoverable error
/// that the UI should display to the user.
class ElevenLabsApiException implements Exception {
  final String message;
  final int statusCode;
  final bool isQuotaExceeded;
  const ElevenLabsApiException(this.message, {this.statusCode = 0, this.isQuotaExceeded = false});
  @override
  String toString() => 'ElevenLabsApiException: $message (status=$statusCode)';
}

/// ElevenLabs TTS engine — premium cloud-based TTS with expressive voices.
///
/// Uses the ElevenLabs Text-to-Speech API.
/// Requires an API key from https://elevenlabs.io
class ElevenLabsTtsEngine implements TtsEngine {
  String apiKey;
  String model;
  double stability;
  double similarityBoost;
  double style;

  /// Runtime-fetched voices (populated after calling [fetchVoices]).
  List<TtsVoiceInfo> _fetchedVoices = [];

  ElevenLabsTtsEngine({
    this.apiKey = '',
    this.model = 'eleven_flash_v2_5',
    this.stability = 0.5,
    this.similarityBoost = 0.75,
    this.style = 0.0,
  });

  static int _fileCounter = 0;

  @override
  String get engineName => 'ElevenLabs';

  @override
  String get engineId => 'elevenlabs';

  @override
  Future<bool> get isAvailable async => apiKey.isNotEmpty;

  @override
  Future<bool> ensureModelReady({void Function(double)? onProgress}) async => true;

  @override
  Future<File?> generateAudio(
    String text,
    String voice,
    double speed, {
    void Function(double progress)? onProgress,
  }) async {
    if (apiKey.isEmpty) {
      print('ElevenLabs TTS: no API key configured');
      return null;
    }

    try {
      final response = await http.post(
        Uri.parse(
          'https://api.elevenlabs.io/v1/text-to-speech/$voice?output_format=mp3_44100_128',
        ),
        headers: {
          'xi-api-key': apiKey,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'text': text,
          'model_id': model,
          'voice_settings': {
            'stability': stability,
            'similarity_boost': similarityBoost,
            'style': style,
            'use_speaker_boost': true,
          },
        }),
      );

      if (response.statusCode != 200) {
        print('ElevenLabs TTS error: ${response.statusCode} ${response.body}');

        // Parse error detail for user-friendly message
        String userMessage;
        bool isQuota = false;
        try {
          final detail = jsonDecode(response.body)['detail'];
          final status = detail is Map ? detail['status']?.toString() ?? '' : '';
          if (response.statusCode == 401) {
            userMessage = 'ElevenLabs API key is invalid or expired.';
          } else if (response.statusCode == 422 || status.contains('quota')) {
            userMessage = 'ElevenLabs credits exhausted. Your quota will reset at the start of your next billing cycle.';
            isQuota = true;
          } else if (response.statusCode == 429) {
            userMessage = 'ElevenLabs rate limit reached. Please try again in a moment.';
          } else {
            userMessage = 'ElevenLabs error: ${detail is Map ? detail['message'] ?? response.statusCode : response.statusCode}';
          }
        } catch (_) {
          userMessage = 'ElevenLabs error (${response.statusCode})';
        }

        throw ElevenLabsApiException(userMessage,
            statusCode: response.statusCode, isQuotaExceeded: isQuota);
      }

      // ElevenLabs returns MP3 audio directly — no conversion needed.
      final tempDir = Directory.systemTemp;
      _fileCounter++;
      final outputFile = File(p.join(tempDir.path,
          'elevenlabs_tts_${DateTime.now().millisecondsSinceEpoch}_$_fileCounter.mp3'));
      await outputFile.writeAsBytes(response.bodyBytes);

      return outputFile;
    } on ElevenLabsApiException {
      rethrow; // Let TTS service handle these
    } catch (e) {
      print('ElevenLabs TTS error: $e');
      return null;
    }
  }

  /// Fetch available voices from ElevenLabs API.
  /// Returns the list and caches it in [_fetchedVoices].
  Future<List<TtsVoiceInfo>> fetchVoices() async {
    if (apiKey.isEmpty) return _defaultVoices;

    try {
      final response = await http.get(
        Uri.parse('https://api.elevenlabs.io/v1/voices'),
        headers: {'xi-api-key': apiKey},
      );

      if (response.statusCode != 200) {
        print('ElevenLabs voices error: ${response.statusCode}');
        return _defaultVoices;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final voices = (data['voices'] as List?) ?? [];

      _fetchedVoices = voices.map((v) {
        final labels = v['labels'] as Map<String, dynamic>? ?? {};
        final gender = labels['gender']?.toString() ?? '';
        final accent = labels['accent']?.toString() ?? '';
        final description = labels['description']?.toString() ?? '';
        final name = v['name']?.toString() ?? 'Unknown';
        final subtitle = [
          if (gender.isNotEmpty) gender,
          if (accent.isNotEmpty) accent,
          if (description.isNotEmpty) description,
        ].join(', ');

        return TtsVoiceInfo(
          id: v['voice_id']?.toString() ?? '',
          name: '$name${subtitle.isNotEmpty ? ' ($subtitle)' : ''}',
          gender: gender.toLowerCase().contains('female') ? 'Female'
              : gender.toLowerCase().contains('male') ? 'Male'
              : 'Neutral',
          language: 'Multilingual',
          engine: 'elevenlabs',
        );
      }).where((v) => v.id.isNotEmpty).toList();

      return _fetchedVoices;
    } catch (e) {
      print('ElevenLabs fetchVoices error: $e');
      return _defaultVoices;
    }
  }

  @override
  List<TtsVoiceInfo> get availableVoices =>
      _fetchedVoices.isNotEmpty ? _fetchedVoices : _defaultVoices;

  /// Default premade voices available on all ElevenLabs accounts.
  static const _defaultVoices = [
    TtsVoiceInfo(id: 'EXAVITQu4vr4xnSDxMaL', name: 'Sarah', gender: 'Female', language: 'Multilingual', engine: 'elevenlabs'),
    TtsVoiceInfo(id: 'FGY2WhTYpPnrIDTdsKH5', name: 'Laura', gender: 'Female', language: 'Multilingual', engine: 'elevenlabs'),
    TtsVoiceInfo(id: 'IKne3meq5aSn9XLyUdCD', name: 'Charlie', gender: 'Male', language: 'Multilingual', engine: 'elevenlabs'),
    TtsVoiceInfo(id: 'JBFqnCBsd6RMkjVDRZzb', name: 'George', gender: 'Male', language: 'Multilingual', engine: 'elevenlabs'),
    TtsVoiceInfo(id: 'N2lVS1w4EtoT3dr4eOWO', name: 'Callum', gender: 'Male', language: 'Multilingual', engine: 'elevenlabs'),
    TtsVoiceInfo(id: 'TX3LPaxmHKxFdv7VOQHJ', name: 'Liam', gender: 'Male', language: 'Multilingual', engine: 'elevenlabs'),
    TtsVoiceInfo(id: 'XB0fDUnXU5powFXDhCwa', name: 'Charlotte', gender: 'Female', language: 'Multilingual', engine: 'elevenlabs'),
    TtsVoiceInfo(id: 'Xb7hH8MSUJpSbSDYk0k2', name: 'Alice', gender: 'Female', language: 'Multilingual', engine: 'elevenlabs'),
    TtsVoiceInfo(id: 'bIHbv24MWmeRgasZH58o', name: 'Will', gender: 'Male', language: 'Multilingual', engine: 'elevenlabs'),
    TtsVoiceInfo(id: 'cgSgspJ2msm6clMCkdW9', name: 'Jessica', gender: 'Female', language: 'Multilingual', engine: 'elevenlabs'),
    TtsVoiceInfo(id: 'cjVigY5qzO86Huf0OWal', name: 'Eric', gender: 'Male', language: 'Multilingual', engine: 'elevenlabs'),
    TtsVoiceInfo(id: 'iP95p4xoKVk53GoZ742B', name: 'Chris', gender: 'Male', language: 'Multilingual', engine: 'elevenlabs'),
    TtsVoiceInfo(id: 'nPczCjzI2devNBz1zQrb', name: 'Brian', gender: 'Male', language: 'Multilingual', engine: 'elevenlabs'),
    TtsVoiceInfo(id: 'onwK4e9ZLuTAKqWW03F9', name: 'Daniel', gender: 'Male', language: 'Multilingual', engine: 'elevenlabs'),
    TtsVoiceInfo(id: 'pFZP5JQG7iQjIQuC4Bku', name: 'Lily', gender: 'Female', language: 'Multilingual', engine: 'elevenlabs'),
    TtsVoiceInfo(id: 'pqHfZKP75CvOlQylNhV4', name: 'Bill', gender: 'Male', language: 'Multilingual', engine: 'elevenlabs'),
  ];
}
