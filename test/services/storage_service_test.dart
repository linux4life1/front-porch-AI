// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:front_porch_ai/services/storage_service.dart';

/// Mock the path_provider plugin so StorageService._init() can resolve
/// getApplicationDocumentsDirectory() without a real platform channel.
void setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
    if (methodCall.method == 'getApplicationDocumentsDirectory') {
      // Use a temp directory that exists and is writable.
      final tmp = Directory.systemTemp.createTempSync('fpai_test_');
      return tmp.path;
    }
    return null;
  });
}

/// Helper: create a StorageService backed by an in-memory SharedPreferences
/// and wait for its async init to complete before returning.
Future<StorageService> createStorageService([
  Map<String, Object> initialValues = const {},
]) async {
  SharedPreferences.setMockInitialValues(initialValues);
  final service = StorageService();
  await service.initialized;
  return service;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupPathProviderMock();

  // ─── Core Sampler / Generation Settings ────────────────────────────

  group('Core settings persistence', () {
    test('setSystemPrompt persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setSystemPrompt('Custom prompt');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('system_prompt'), 'Custom prompt');
      expect(svc.systemPrompt, 'Custom prompt');
    });

    test('setMinP persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setMinP(0.42);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('min_p'), 0.42);
      expect(svc.minP, 0.42);
    });

    test('setTemperature persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setTemperature(1.5);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('temperature'), 1.5);
      expect(svc.temperature, 1.5);
    });

    test('setBubbleOpacity persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setBubbleOpacity(0.5);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('bubble_opacity'), 0.5);
      expect(svc.bubbleOpacity, 0.5);
    });

    test('setRepeatPenalty persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setRepeatPenalty(1.3);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('repeat_penalty'), 1.3);
      expect(svc.repeatPenalty, 1.3);
    });

    test('setRepeatPenaltyTokens persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setRepeatPenaltyTokens(128);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('repeat_penalty_tokens'), 128);
      expect(svc.repeatPenaltyTokens, 128);
    });

    test('setXtcThreshold persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setXtcThreshold(0.25);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('xtc_threshold'), 0.25);
    });

    test('setXtcProbability persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setXtcProbability(0.8);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('xtc_probability'), 0.8);
    });

    test('setDynamicTempEnabled persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setDynamicTempEnabled(true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('dynamic_temp_enabled'), true);
    });

    test('setDynamicTempRange persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setDynamicTempRange(1.2);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('dynamic_temp_range'), 1.2);
    });

    test('setMaxLength persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setMaxLength(2048);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('max_length'), 2048);
      expect(svc.maxLength, 2048);
    });

    test('setMinLength persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setMinLength(50);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('min_length'), 50);
    });

    test('setContextSize persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setContextSize(16384);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('context_size'), 16384);
      expect(svc.contextSize, 16384);
    });

    test('setGpuLayers persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setGpuLayers(33);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('gpu_layers'), 33);
      expect(svc.gpuLayers, 33);
    });

    test('setTextScale persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setTextScale(1.3);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('text_scale'), 1.3);
    });

    test('setChatBackground persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setChatBackground('forest.jpg');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('chat_background'), 'forest.jpg');
    });

    test('setKvQuantizationLevel persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setKvQuantizationLevel(2);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('kv_quantization_level'), 2);
    });
  });

  // ─── Model Selection (Bug 1 target) ───────────────────────────────

  group('Model selection persistence (Bug 1)', () {
    test('setLastUsedModelPath persists non-null value', () async {
      final svc = await createStorageService();
      await svc.setLastUsedModelPath('/models/llama-7b.gguf');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('last_used_model_path'), '/models/llama-7b.gguf');
      expect(svc.lastUsedModelPath, '/models/llama-7b.gguf');
    });

    test('setLastUsedModelPath removes key when set to null', () async {
      final svc = await createStorageService({
        'last_used_model_path': '/old/model.gguf',
      });
      await svc.setLastUsedModelPath(null);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('last_used_model_path'), isNull);
      expect(svc.lastUsedModelPath, isNull);
    });

    test('setLastUsedModelPath survives simulated restart', () async {
      // Write
      final svc = await createStorageService();
      await svc.setLastUsedModelPath('/models/mistral-7b.gguf');

      // Simulate restart by creating a new service with same prefs backend.
      // SharedPreferences mock instance is cached per-test so the new
      // StorageService reads the same data.
      final svc2 = StorageService();
      await svc2.initialized;
      expect(svc2.lastUsedModelPath, '/models/mistral-7b.gguf');
    });

    test('setAutostartBackend persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setAutostartBackend(false);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('autostart_backend'), false);
      expect(svc.autostartBackend, false);
    });
  });

  // ─── GPU Acceleration Settings ─────────────────────────────────────

  group('GPU acceleration persistence', () {
    test('setUseCublas persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setUseCublas(true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('use_cublas'), true);
    });

    test('setUseVulkan persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setUseVulkan(true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('use_vulkan'), true);
    });

    test('setUseMetal persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setUseMetal(true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('use_metal'), true);
    });

    test('setUseRocm persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setUseRocm(true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('use_rocm'), true);
    });
  });

  // ─── Stop Sequences ────────────────────────────────────────────────

  group('Stop sequences persistence', () {
    test('setStopSequences persists to SharedPreferences', () async {
      final svc = await createStorageService();
      final seqs = ['\\nUser:', '<END>'];
      await svc.setStopSequences(seqs);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('stop_sequences'), seqs);
    });

    test('addStopSequence persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.addStopSequence('CUSTOM_STOP');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('stop_sequences'), contains('CUSTOM_STOP'));
    });

    test('removeStopSequence persists to SharedPreferences', () async {
      final svc = await createStorageService({
        'stop_sequences': ['A', 'B', 'C'],
      });
      await svc.removeStopSequence('B');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('stop_sequences'), isNot(contains('B')));
    });
  });

  // ─── External API / Backend Settings ───────────────────────────────

  group('External API settings persistence', () {
    test('setBackendType persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setBackendType('openRouter');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('backend_type'), 'openRouter');
    });

    test('setRemoteApiKey persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setRemoteApiKey('sk-test-key');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('remote_api_key'), 'sk-test-key');
    });

    test('setRemoteApiUrl persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setRemoteApiUrl('https://custom.api/v1');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('remote_api_url'), 'https://custom.api/v1');
    });

    test('setRemoteModelName persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setRemoteModelName('anthropic/claude-3');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('remote_model_name'), 'anthropic/claude-3');
    });

    test('setReasoningEnabled persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setReasoningEnabled(true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('reasoning_enabled'), true);
    });

    test('setReasoningEffort persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setReasoningEffort('high');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('reasoning_effort'), 'high');
    });

    test('setKoboldThinkingModel persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setKoboldThinkingModel(true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('kobold_thinking_model'), true);
    });
  });

  // ─── Display Buffer Settings ───────────────────────────────────────

  group('Display buffer settings persistence', () {
    test('setDisplayBufferEnabled persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setDisplayBufferEnabled(false);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('display_buffer_enabled'), false);
    });

    test('setTargetDisplayTps persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setTargetDisplayTps(12.0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('target_display_tps'), 12.0);
    });

    test('setBufferDurationSeconds persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setBufferDurationSeconds(5.0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('buffer_duration_seconds'), 5.0);
    });
  });

  // ─── TTS Settings ─────────────────────────────────────────────────

  group('TTS settings persistence', () {
    test('setTtsEnabled persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setTtsEnabled(true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('tts_enabled'), true);
    });

    test('setTtsEngine persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setTtsEngine('openai');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('tts_engine'), 'openai');
    });

    test('setTtsVoiceModel persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setTtsVoiceModel('af_heart');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('tts_voice_model'), 'af_heart');
    });

    test('setTtsSpeechRate persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setTtsSpeechRate(1.5);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('tts_speech_rate'), 1.5);
    });

    test('setTtsAutoPlay persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setTtsAutoPlay(true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('tts_auto_play'), true);
    });

    test('setOpenaiTtsApiKey persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setOpenaiTtsApiKey('test-key');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('openai_tts_api_key'), 'test-key');
    });

    test('setOpenaiTtsModel persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setOpenaiTtsModel('tts-1-hd');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('openai_tts_model'), 'tts-1-hd');
    });

    test('setOpenaiTtsBaseUrl persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setOpenaiTtsBaseUrl('https://custom.tts/v1');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('openai_tts_base_url'), 'https://custom.tts/v1');
    });

    test('setElevenlabsApiKey persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setElevenlabsApiKey('el-key');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('elevenlabs_api_key'), 'el-key');
    });

    test('setElevenlabsModel persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setElevenlabsModel('eleven_turbo_v2');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('elevenlabs_model'), 'eleven_turbo_v2');
    });

    test('setElevenlabsStability clamps and persists', () async {
      final svc = await createStorageService();
      await svc.setElevenlabsStability(1.5); // should clamp to 1.0
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('elevenlabs_stability'), 1.0);
    });

    test('setElevenlabsSimilarity clamps and persists', () async {
      final svc = await createStorageService();
      await svc.setElevenlabsSimilarity(-0.3); // should clamp to 0.0
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('elevenlabs_similarity'), 0.0);
    });

    test('setElevenlabsStyle clamps and persists', () async {
      final svc = await createStorageService();
      await svc.setElevenlabsStyle(0.75);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('elevenlabs_style'), 0.75);
    });

    test('setTtsNarrateQuotedOnly persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setTtsNarrateQuotedOnly(true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('tts_narrate_quoted_only'), true);
    });

    test('setTtsIgnoreAsterisks persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setTtsIgnoreAsterisks(true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('tts_ignore_asterisks'), true);
    });

    test('setTtsConcurrency clamps and persists', () async {
      final svc = await createStorageService();
      await svc.setTtsConcurrency(999); // should clamp to 8
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('tts_concurrency'), 8);
    });

    test('setDirectorDelay clamps and persists', () async {
      final svc = await createStorageService();
      await svc.setDirectorDelay(100.0); // should clamp to 60.0
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('director_delay'), 60.0);
    });
  });

  // ─── STT Settings ─────────────────────────────────────────────────

  group('STT settings persistence', () {
    test('setSttEnabled persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setSttEnabled(true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('stt_enabled'), true);
    });

    test('setWhisperModel persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setWhisperModel('small.en');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('whisper_model'), 'small.en');
    });

    test('setAutoSendTranscription persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setAutoSendTranscription(true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('auto_send_transcription'), true);
    });

    test('setSelectedMicId persists non-null value', () async {
      final svc = await createStorageService();
      await svc.setSelectedMicId('mic-123');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('selected_mic_id'), 'mic-123');
    });

    test('setSelectedMicId removes key when null', () async {
      final svc = await createStorageService({'selected_mic_id': 'old'});
      await svc.setSelectedMicId(null);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('selected_mic_id'), isNull);
    });

    test('setCallModelName persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setCallModelName('voice-model');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('call_model_name'), 'voice-model');
    });

    test('setCallBufferSentences clamps and persists', () async {
      final svc = await createStorageService();
      await svc.setCallBufferSentences(15); // should clamp to 10
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('call_buffer_sentences'), 10);
    });

    test('setCallSystemPrompt persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setCallSystemPrompt('Be brief.');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('call_system_prompt'), 'Be brief.');
    });
  });

  // ─── Sort / Grid / UI Preferences ─────────────────────────────────

  group('UI preferences persistence', () {
    test('setSortMode persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setSortMode('recent');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('sort_mode'), 'recent');
    });

    test('setGridScale clamps and persists', () async {
      final svc = await createStorageService();
      await svc.setGridScale(600.0); // should clamp to 450
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('grid_scale'), 450.0);
    });
  });

  // ─── Cloud Sync Settings ──────────────────────────────────────────

  group('Cloud sync settings persistence', () {
    test('setCloudSyncEnabled persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setCloudSyncEnabled(true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('cloud_sync_enabled'), true);
    });

    test('setCloudSyncProvider persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setCloudSyncProvider('webdav');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('cloud_sync_provider'), 'webdav');
    });

    test('setCloudSyncUrl persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setCloudSyncUrl('https://dav.example.com');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('cloud_sync_url'), 'https://dav.example.com');
    });

    test('setCloudSyncUsername persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setCloudSyncUsername('user');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('cloud_sync_username'), 'user');
    });

    test('setCloudSyncPassword persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setCloudSyncPassword('pass');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('cloud_sync_password'), 'pass');
    });

    test('setCloudSyncLastTime persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setCloudSyncLastTime('2026-04-11T10:00:00Z');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('cloud_sync_last_time'), '2026-04-11T10:00:00Z');
    });
  });

  // ─── Image Generation Settings ────────────────────────────────────

  group('Image generation settings persistence', () {
    test('setImageGenEnabled persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setImageGenEnabled(true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('image_gen_enabled'), true);
    });

    test('setImageGenBackend persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setImageGenBackend('a1111');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('image_gen_backend'), 'a1111');
    });

    test('setLocalImageGenUrl persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setLocalImageGenUrl('http://192.168.1.100:7860');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('local_image_gen_url'), 'http://192.168.1.100:7860');
    });

    test('setImageGenModel persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setImageGenModel('dall-e-3');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('image_gen_model'), 'dall-e-3');
    });

    test('setImageGenSize persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setImageGenSize('512x512');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('image_gen_size'), '512x512');
    });

    test('setImageGenNegativePrompt persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setImageGenNegativePrompt('ugly, bad anatomy');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('image_gen_negative_prompt'), 'ugly, bad anatomy');
    });

    test('setImageGenStyle persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setImageGenStyle('anime');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('image_gen_style'), 'anime');
    });

    test('setImageGenPromptParadigm persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setImageGenPromptParadigm('tags');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('image_gen_prompt_paradigm'), 'tags');
    });

    test('setImageGenLora persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setImageGenLora('myLora.safetensors');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('image_gen_lora'), 'myLora.safetensors');
    });

    test('setImageGenLoraWeight clamps and persists', () async {
      final svc = await createStorageService();
      await svc.setImageGenLoraWeight(1.5); // should clamp to 1.0
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('image_gen_lora_weight'), 1.0);
    });
  });

  // ─── Web Server Settings ──────────────────────────────────────────

  group('Web server settings persistence', () {
    test('setWebServerEnabled persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setWebServerEnabled(true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('web_server_enabled'), true);
    });

    test('setWebServerPort persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setWebServerPort(9090);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('web_server_port'), 9090);
    });

    test('setWebServerPin persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setWebServerPin('1234');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('web_server_pin'), '1234');
    });
  });

  // ─── Summary Settings ─────────────────────────────────────────────

  group('Summary settings persistence', () {
    test('setSummaryEnabled persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setSummaryEnabled(true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('summary_enabled'), true);
    });

    test('setSummaryInterval clamps and persists', () async {
      final svc = await createStorageService();
      await svc.setSummaryInterval(1); // should clamp to 3
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('summary_interval'), 3);
    });

    test('setSummaryMaxWords clamps and persists', () async {
      final svc = await createStorageService();
      await svc.setSummaryMaxWords(2000); // should clamp to 1000
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('summary_max_words'), 1000);
    });

    test('setSummaryPrompt persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setSummaryPrompt('Custom summary prompt');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('summary_prompt'), 'Custom summary prompt');
    });
  });

  // ─── Banned Phrases ───────────────────────────────────────────────

  group('Banned phrases persistence', () {
    test('setBannedPhrases persists as JSON', () async {
      final svc = await createStorageService();
      await svc.setBannedPhrases(['delve', 'a testament to']);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('banned_phrases'), isNotNull);
      expect(svc.bannedPhrases, ['delve', 'a testament to']);
    });

    test('setBannedPhrases filters empty strings', () async {
      final svc = await createStorageService();
      await svc.setBannedPhrases(['valid', '', 'also valid', '']);
      expect(svc.bannedPhrases, ['valid', 'also valid']);
    });
  });

  // ─── RAG Memory Settings ──────────────────────────────────────────

  group('RAG memory settings persistence', () {
    test('setRagEnabled persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setRagEnabled(true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('rag_enabled'), true);
    });

    test('setRagRetrievalCount clamps and persists', () async {
      final svc = await createStorageService();
      await svc.setRagRetrievalCount(100); // should clamp to 50
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('rag_retrieval_count'), 50);
    });

    test('setRagWindowSize clamps and persists', () async {
      final svc = await createStorageService();
      await svc.setRagWindowSize(1); // should clamp to 2
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('rag_window_size'), 2);
    });

    test('setRagEmbeddingSource persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setRagEmbeddingSource('kobold');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('rag_embedding_source'), 'kobold');
    });

    test('setRagEmbeddingModel persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setRagEmbeddingModel('custom-embed');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('rag_embedding_model'), 'custom-embed');
    });
  });

  // ─── Auto-Persona Settings ────────────────────────────────────────

  group('Auto-persona settings persistence', () {
    test('setAutoPersonaEnabled persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setAutoPersonaEnabled(true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('auto_persona_enabled'), true);
    });

    test('setAutoPersonaInterval clamps and persists', () async {
      final svc = await createStorageService();
      await svc.setAutoPersonaInterval(100); // should clamp to 50
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('auto_persona_interval'), 50);
    });
  });

  // ─── Character Evolution Settings ─────────────────────────────────

  group('Character evolution settings persistence', () {
    test('setCharacterEvolutionEnabled persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setCharacterEvolutionEnabled(true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('character_evolution_enabled'), true);
    });

    test('setEvolutionInterval clamps and persists', () async {
      final svc = await createStorageService();
      await svc.setEvolutionInterval(5); // should clamp to 10
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('evolution_interval'), 10);
    });
  });

  // ─── Realism Engine Settings ──────────────────────────────────────

  group('Realism engine settings persistence', () {
    test('setRealismOneShotEval persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.setRealismOneShotEval(true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('realism_one_shot_eval'), true);
    });
  });

  // ─── Custom Models Path ───────────────────────────────────────────

  group('Custom models path persistence', () {
    test('setCustomModelsPath persists non-empty value', () async {
      final svc = await createStorageService();
      await svc.setCustomModelsPath('/external/models');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('custom_models_path'), '/external/models');
    });

    test('setCustomModelsPath removes key when null', () async {
      final svc = await createStorageService({
        'custom_models_path': '/old/path',
      });
      await svc.setCustomModelsPath(null);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('custom_models_path'), isNull);
    });

    test('setCustomModelsPath removes key when empty', () async {
      final svc = await createStorageService({
        'custom_models_path': '/old/path',
      });
      await svc.setCustomModelsPath('');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('custom_models_path'), isNull);
    });
  });

  // ─── Saved Prompts ────────────────────────────────────────────────

  group('Saved prompts persistence', () {
    test('savePrompt persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.savePrompt('Test Prompt', 'Test content');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('saved_prompts'), isNotNull);
      expect(svc.savedPrompts.any((p) => p['name'] == 'Test Prompt'), true);
    });

    test('deleteSavedPrompt persists removal', () async {
      final svc = await createStorageService();
      await svc.savePrompt('Temp', 'content');
      await svc.deleteSavedPrompt('Temp');
      expect(svc.savedPrompts.any((p) => p['name'] == 'Temp'), false);
    });
  });

  // ─── notifyListeners ──────────────────────────────────────────────

  group('notifyListeners is called on setter', () {
    test('setTemperature triggers notifyListeners', () async {
      final svc = await createStorageService();
      int callCount = 0;
      svc.addListener(() => callCount++);
      await svc.setTemperature(0.9);
      expect(callCount, greaterThanOrEqualTo(1));
    });

    test('setLastUsedModelPath triggers notifyListeners', () async {
      final svc = await createStorageService();
      int callCount = 0;
      svc.addListener(() => callCount++);
      await svc.setLastUsedModelPath('/model.gguf');
      expect(callCount, greaterThanOrEqualTo(1));
    });
  });
}
