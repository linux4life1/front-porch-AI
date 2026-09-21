// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
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
      await svc.generationSettings.setSystemPrompt('Custom prompt');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('system_prompt'), 'Custom prompt');
      expect(svc.generationSettings.systemPrompt, 'Custom prompt');
    });

    test('setMinP persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.generationSettings.setMinP(0.42);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('min_p'), 0.42);
      expect(svc.generationSettings.minP, 0.42);
    });

    test('setTemperature persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.generationSettings.setTemperature(1.5);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('temperature'), 1.5);
      expect(svc.generationSettings.temperature, 1.5);
    });

    test('setBubbleOpacity persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.uiSettings.setBubbleOpacity(0.5);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('bubble_opacity'), 0.5);
      expect(svc.uiSettings.bubbleOpacity, 0.5);
    });

    test('setRepeatPenalty persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.generationSettings.setRepeatPenalty(1.3);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('repeat_penalty'), 1.3);
      expect(svc.generationSettings.repeatPenalty, 1.3);
    });

    test('setRepeatPenaltyTokens persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.generationSettings.setRepeatPenaltyTokens(128);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('repeat_penalty_tokens'), 128);
      expect(svc.generationSettings.repeatPenaltyTokens, 128);
    });

    test('setXtcThreshold persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.generationSettings.setXtcThreshold(0.25);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('xtc_threshold'), 0.25);
    });

    test('setXtcProbability persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.generationSettings.setXtcProbability(0.8);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('xtc_probability'), 0.8);
    });

    test('setDynamicTempEnabled persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.generationSettings.setDynamicTempEnabled(true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('dynamic_temp_enabled'), true);
    });

    test('setDynamicTempRange persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.generationSettings.setDynamicTempRange(1.2);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('dynamic_temp_range'), 1.2);
    });

    test('setMaxLength persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.generationSettings.setMaxLength(2048);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('max_length'), 2048);
      expect(svc.generationSettings.maxLength, 2048);
    });

    test('setMinLength persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.generationSettings.setMinLength(50);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('min_length'), 50);
    });

    test('setContextSize persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.backendSettings.setContextSize(16384);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('context_size'), 16384);
      expect(svc.backendSettings.contextSize, 16384);
    });

    test('setGpuLayers persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.backendSettings.setGpuLayers(33);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('gpu_layers'), 33);
      expect(svc.backendSettings.gpuLayers, 33);
    });

    test('setTextScale persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.uiSettings.setTextScale(1.3);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('text_scale'), 1.3);
    });

    test('setChatBackground persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.uiSettings.setChatBackground('forest.jpg');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('chat_background'), 'forest.jpg');
    });

    test('setKvQuantizationLevel persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.backendSettings.setKvQuantizationLevel(2);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('kv_quantization_level'), 2);
    });

    test(
      'loadSavedPrompt applies the preset into generationSettings',
      () async {
        final svc = await createStorageService({
          'saved_prompts': '[{"name":"TestPrompt","content":"Hello {{char}}"}]',
        });
        svc.presetSettings.loadSavedPrompt('TestPrompt', (p) {
          svc.generationSettings.setSystemPrompt(p);
        });
        expect(svc.generationSettings.systemPrompt, contains('Hello {{char}}'));
        expect(svc.backendSettings.kvQuantizationLevel, isA<int>());
        expect(svc.sttSettings.callBufferSentences, isA<int>());
        await svc.backendSettings.setKvQuantizationLevel(3);
        expect(svc.backendSettings.kvQuantizationLevel, 3);
      },
    );
  });

  // ─── Model Selection (Bug 1 target) ───────────────────────────────

  group('Model selection persistence (Bug 1)', () {
    test('setLastUsedModelPath persists non-null value', () async {
      final svc = await createStorageService();
      await svc.backendSettings.setLastUsedModelPath('/models/llama-7b.gguf');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('last_used_model_path'), '/models/llama-7b.gguf');
      expect(svc.backendSettings.lastUsedModelPath, '/models/llama-7b.gguf');
    });

    test('setLastUsedModelPath removes key when set to null', () async {
      final svc = await createStorageService({
        'last_used_model_path': '/old/model.gguf',
      });
      await svc.backendSettings.setLastUsedModelPath(null);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('last_used_model_path'), isNull);
      expect(svc.backendSettings.lastUsedModelPath, isNull);
    });

    test('setLastUsedModelPath survives simulated restart', () async {
      // Write
      final svc = await createStorageService();
      await svc.backendSettings.setLastUsedModelPath('/models/mistral-7b.gguf');

      // Simulate restart by creating a new service with same prefs backend.
      // SharedPreferences mock instance is cached per-test so the new
      // StorageService reads the same data.
      final svc2 = StorageService();
      await svc2.initialized;
      expect(svc2.backendSettings.lastUsedModelPath, '/models/mistral-7b.gguf');
    });

    test('setAutostartBackend persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.backendSettings.setAutostartBackend(false);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('autostart_backend'), false);
      expect(svc.backendSettings.autostartBackend, false);
    });
  });

  // ─── GPU Acceleration Settings ─────────────────────────────────────

  group('GPU acceleration persistence', () {
    test('setUseCublas persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.backendSettings.setUseCublas(true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('use_cublas'), true);
    });

    test('setUseVulkan persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.backendSettings.setUseVulkan(true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('use_vulkan'), true);
    });

    test('setUseMetal persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.backendSettings.setUseMetal(true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('use_metal'), true);
    });

    test('setUseRocm persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.backendSettings.setUseRocm(true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('use_rocm'), true);
    });
  });

  // ─── Stop Sequences ────────────────────────────────────────────────

  group('Stop sequences persistence', () {
    test('setStopSequences persists to SharedPreferences', () async {
      final svc = await createStorageService();
      final seqs = ['\\nUser:', '<END>'];
      await svc.generationSettings.setStopSequences(seqs);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('stop_sequences'), seqs);
    });

    test('addStopSequence persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.generationSettings.addStopSequence('CUSTOM_STOP');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('stop_sequences'), contains('CUSTOM_STOP'));
    });

    test('removeStopSequence persists to SharedPreferences', () async {
      final svc = await createStorageService({
        'stop_sequences': ['A', 'B', 'C'],
      });
      await svc.generationSettings.removeStopSequence('B');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('stop_sequences'), isNot(contains('B')));
    });
  });

  // ─── External API / Backend Settings ───────────────────────────────

  group('External API settings persistence', () {
    test('setBackendType persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.backendSettings.setBackendType('openRouter');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('backend_type'), 'openRouter');
    });

    test('setRemoteApiKey persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.backendSettings.setRemoteApiKey('sk-test-key');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('remote_api_key'), 'sk-test-key');
    });

    test('setRemoteApiUrl persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.backendSettings.setRemoteApiUrl('https://custom.api/v1');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('remote_api_url'), 'https://custom.api/v1');
    });

    test('setRemoteModelName persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.backendSettings.setRemoteModelName('anthropic/claude-3');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('remote_model_name'), 'anthropic/claude-3');
    });

    test('setReasoningEnabled persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.backendSettings.setReasoningEnabled(true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('reasoning_enabled'), true);
    });

    test('setReasoningEffort persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.backendSettings.setReasoningEffort('high');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('reasoning_effort'), 'high');
    });

    test('setKoboldThinkingModel persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.backendSettings.setKoboldThinkingModel(true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('kobold_thinking_model'), true);
    });
  });

  // ─── Display Buffer Settings ───────────────────────────────────────

  group('Display buffer settings persistence', () {
    test('setDisplayBufferEnabled persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.uiSettings.setDisplayBufferEnabled(false);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('display_buffer_enabled'), false);
    });

    test('setTargetDisplayTps persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.uiSettings.setTargetDisplayTps(12.0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('target_display_tps'), 12.0);
    });

    test('setBufferDurationSeconds persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.uiSettings.setBufferDurationSeconds(5.0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('buffer_duration_seconds'), 5.0);
    });
  });

  // ─── TTS Settings ─────────────────────────────────────────────────

  group('TTS settings persistence', () {
    test('setTtsEnabled persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.ttsSettings.setTtsEnabled(true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('tts_enabled'), true);
    });

    test('setTtsEngine persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.ttsSettings.setTtsEngine('openai');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('tts_engine'), 'openai');
    });

    test('setTtsVoiceModel persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.ttsSettings.setTtsVoiceModel('af_heart');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('tts_voice_model'), 'af_heart');
    });

    test('setTtsSpeechRate persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.ttsSettings.setTtsSpeechRate(1.5);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('tts_speech_rate'), 1.5);
    });

    test('setTtsAutoPlay persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.ttsSettings.setTtsAutoPlay(true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('tts_auto_play'), true);
    });

    test('setOpenaiTtsApiKey persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.ttsSettings.setOpenaiTtsApiKey('test-key');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('openai_tts_api_key'), 'test-key');
    });

    test('setOpenaiTtsModel persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.ttsSettings.setOpenaiTtsModel('tts-1-hd');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('openai_tts_model'), 'tts-1-hd');
    });

    test('setOpenaiTtsBaseUrl persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.ttsSettings.setOpenaiTtsBaseUrl('https://custom.tts/v1');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('openai_tts_base_url'), 'https://custom.tts/v1');
    });

    test('setElevenlabsApiKey persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.ttsSettings.setElevenlabsApiKey('el-key');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('elevenlabs_api_key'), 'el-key');
    });

    test('setElevenlabsModel persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.ttsSettings.setElevenlabsModel('eleven_turbo_v2');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('elevenlabs_model'), 'eleven_turbo_v2');
    });

    test('setElevenlabsStability clamps and persists', () async {
      final svc = await createStorageService();
      await svc.ttsSettings.setElevenlabsStability(1.5); // should clamp to 1.0
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('elevenlabs_stability'), 1.0);
    });

    test('setElevenlabsSimilarity clamps and persists', () async {
      final svc = await createStorageService();
      await svc.ttsSettings.setElevenlabsSimilarity(
        -0.3,
      ); // should clamp to 0.0
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('elevenlabs_similarity'), 0.0);
    });

    test('setElevenlabsStyle clamps and persists', () async {
      final svc = await createStorageService();
      await svc.ttsSettings.setElevenlabsStyle(0.75);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('elevenlabs_style'), 0.75);
    });

    test('setTtsNarrateQuotedOnly persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.ttsSettings.setTtsNarrateQuotedOnly(true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('tts_narrate_quoted_only'), true);
    });

    test('setTtsIgnoreAsterisks persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.ttsSettings.setTtsIgnoreAsterisks(true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('tts_ignore_asterisks'), true);
    });

    test('setTtsConcurrency clamps and persists', () async {
      final svc = await createStorageService();
      await svc.ttsSettings.setTtsConcurrency(999); // should clamp to 8
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('tts_concurrency'), 8);
    });

    test('setDirectorDelay clamps and persists', () async {
      final svc = await createStorageService();
      await svc.ttsSettings.setDirectorDelay(100.0); // should clamp to 60.0
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('director_delay'), 60.0);
    });
  });

  // ─── STT Settings ─────────────────────────────────────────────────

  group('STT settings persistence', () {
    test('setSttEnabled persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.sttSettings.setSttEnabled(true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('stt_enabled'), true);
    });

    test('setWhisperModel persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.sttSettings.setWhisperModel('small.en');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('whisper_model'), 'small.en');
    });

    test('setAutoSendTranscription persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.sttSettings.setAutoSendTranscription(true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('auto_send_transcription'), true);
    });

    test('setSelectedMicId persists non-null value', () async {
      final svc = await createStorageService();
      await svc.sttSettings.setSelectedMicId('mic-123');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('selected_mic_id'), 'mic-123');
    });

    test('setSelectedMicId removes key when null', () async {
      final svc = await createStorageService({'selected_mic_id': 'old'});
      await svc.sttSettings.setSelectedMicId(null);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('selected_mic_id'), isNull);
    });

    test('setCallModelName persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.sttSettings.setCallModelName('voice-model');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('call_model_name'), 'voice-model');
    });

    test('setCallBufferSentences clamps and persists', () async {
      final svc = await createStorageService();
      await svc.sttSettings.setCallBufferSentences(15); // should clamp to 10
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('call_buffer_sentences'), 10);
    });

    test('setCallSystemPrompt persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.sttSettings.setCallSystemPrompt('Be brief.');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('call_system_prompt'), 'Be brief.');
    });
  });

  // ─── Sort / Grid / UI Preferences ─────────────────────────────────

  group('UI preferences persistence', () {
    test('setSortMode persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.uiSettings.setSortMode('recent');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('sort_mode'), 'recent');
    });

    test('setGridScale clamps and persists', () async {
      final svc = await createStorageService();
      await svc.uiSettings.setGridScale(600.0); // should clamp to 450
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('grid_scale'), 450.0);
    });
  });

  // ─── Image Generation Settings ────────────────────────────────────

  group('Image generation settings persistence', () {
    test('setImageGenEnabled persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.imageGenSettings.setImageGenEnabled(true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('image_gen_enabled'), true);
    });

    test('setImageGenBackend persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.imageGenSettings.setImageGenBackend('a1111');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('image_gen_backend'), 'a1111');
    });

    test('setLocalImageGenUrl persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.imageGenSettings.setLocalImageGenUrl(
        'http://192.168.1.100:7860',
      );
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('local_image_gen_url'),
        'http://192.168.1.100:7860',
      );
    });

    test('setImageGenModel persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.imageGenSettings.setImageGenModel('dall-e-3');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('image_gen_model'), 'dall-e-3');
    });

    test('setImageGenSize persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.imageGenSettings.setImageGenSize('512x512');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('image_gen_size'), '512x512');
    });

    test('setImageGenNegativePrompt persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.imageGenSettings.setImageGenNegativePrompt('ugly, bad anatomy');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('image_gen_negative_prompt'), 'ugly, bad anatomy');
    });

    test('setImageGenStyle persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.imageGenSettings.setImageGenStyle('anime');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('image_gen_style'), 'anime');
    });

    test('setImageGenPromptParadigm persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.imageGenSettings.setImageGenPromptParadigm('tags');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('image_gen_prompt_paradigm'), 'tags');
    });

    test('setImageGenLora persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.imageGenSettings.setImageGenLora('myLora.safetensors');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('image_gen_lora'), 'myLora.safetensors');
    });

    test('setImageGenLoraWeight clamps and persists', () async {
      final svc = await createStorageService();
      await svc.imageGenSettings.setImageGenLoraWeight(
        1.5,
      ); // should clamp to 1.0
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('image_gen_lora_weight'), 1.0);
    });

    test('setImageGenSteps persists', () async {
      final svc = await createStorageService();
      await svc.imageGenSettings.setImageGenSteps(30);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('image_gen_steps'), 30);
    });

    test('setImageGenCfgScale persists', () async {
      final svc = await createStorageService();
      await svc.imageGenSettings.setImageGenCfgScale(9.5);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('image_gen_cfg_scale'), 9.5);
    });

    test('setImageGenSampler persists', () async {
      final svc = await createStorageService();
      await svc.imageGenSettings.setImageGenSampler('DPM++ 2M');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('image_gen_sampler'), 'DPM++ 2M');
    });

    test('setImageGenSeed persists', () async {
      final svc = await createStorageService();
      await svc.imageGenSettings.setImageGenSeed(12345);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('image_gen_seed'), 12345);
    });

    test('drawThings gRPC settings persist', () async {
      final svc = await createStorageService();
      await svc.imageGenSettings.setDrawThingsGrpcHost('10.0.0.5');
      await svc.imageGenSettings.setDrawThingsGrpcPort(7860);
      await svc.imageGenSettings.setDrawThingsSampler(5);
      await svc.imageGenSettings.setDrawThingsShift(2.5);
      await svc.imageGenSettings.setDrawThingsSeedMode(1);
      await svc.imageGenSettings.setDrawThingsTeaCache(true);
      await svc.imageGenSettings.setDrawThingsCfgZeroStar(true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('draw_things_grpc_host'), '10.0.0.5');
      expect(prefs.getInt('draw_things_grpc_port'), 7860);
      expect(prefs.getInt('draw_things_sampler'), 5);
      expect(prefs.getDouble('draw_things_shift'), 2.5);
      expect(prefs.getInt('draw_things_seed_mode'), 1);
      expect(prefs.getBool('draw_things_tea_cache'), true);
      expect(prefs.getBool('draw_things_cfg_zero_star'), true);
    });
  });

  // ─── Web Server Settings ──────────────────────────────────────────

  group('Web server settings persistence', () {
    test('setWebServerEnabled persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.webServerSettings.setWebServerEnabled(true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('web_server_enabled'), true);
    });

    test('setWebServerPort persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.webServerSettings.setWebServerPort(9090);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('web_server_port'), 9090);
    });
    // The legacy web-server PIN was removed in the web UI rewrite (replaced by a
    // real account: Argon2id password + optional TOTP). No PIN setting to test.
  });

  // ─── Journal Settings ─────────────────────────────────────────────

  group('Journal settings persistence', () {
    test('journalEnabled defaults to true', () async {
      final svc = await createStorageService();
      expect(svc.memorySettings.journalEnabled, true);
    });

    test('setJournalEnabled persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.memorySettings.setJournalEnabled(false);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('journal_enabled'), false);
    });

    test('setJournalInterval clamps and persists', () async {
      final svc = await createStorageService();
      await svc.memorySettings.setJournalInterval(1); // should clamp to 3
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('journal_interval'), 3);
    });

    test('setJournalMaxCards clamps and persists', () async {
      final svc = await createStorageService();
      await svc.memorySettings.setJournalMaxCards(5000); // should clamp to 1000
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('journal_max_cards'), 1000);
    });
  });

  // ─── Banned Phrases ───────────────────────────────────────────────

  group('Banned phrases persistence', () {
    test('setBannedPhrases persists as JSON', () async {
      final svc = await createStorageService();
      await svc.realismSettings.setBannedPhrases(['delve', 'a testament to']);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('banned_phrases'), isNotNull);
      expect(svc.realismSettings.bannedPhrases, ['delve', 'a testament to']);
    });

    test('setBannedPhrases filters empty strings', () async {
      final svc = await createStorageService();
      await svc.realismSettings.setBannedPhrases([
        'valid',
        '',
        'also valid',
        '',
      ]);
      expect(svc.realismSettings.bannedPhrases, ['valid', 'also valid']);
    });
  });

  // ─── RAG Memory Settings ──────────────────────────────────────────

  group('RAG memory settings persistence', () {
    test('setRagEnabled persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.memorySettings.setRagEnabled(true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('rag_enabled'), true);
    });

    test('setRagRetrievalCount clamps and persists', () async {
      final svc = await createStorageService();
      await svc.memorySettings.setRagRetrievalCount(100); // should clamp to 50
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('rag_retrieval_count'), 50);
    });

    test('setRagWindowSize clamps and persists', () async {
      final svc = await createStorageService();
      await svc.memorySettings.setRagWindowSize(1); // should clamp to 2
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('rag_window_size'), 2);
    });

    test('setRagEmbeddingSource persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.memorySettings.setRagEmbeddingSource('kobold');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('rag_embedding_source'), 'kobold');
    });

    test('setRagEmbeddingModel persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.memorySettings.setRagEmbeddingModel('custom-embed');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('rag_embedding_model'), 'custom-embed');
    });
  });

  // ─── Character Evolution Settings ─────────────────────────────────

  group('Character evolution settings persistence', () {
    test(
      'setCharacterEvolutionEnabled persists to SharedPreferences',
      () async {
        final svc = await createStorageService();
        await svc.memorySettings.setCharacterEvolutionEnabled(true);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool('character_evolution_enabled'), true);
      },
    );

    test('setGrowthInterval clamps and persists', () async {
      final svc = await createStorageService();
      await svc.memorySettings.setGrowthInterval(
        1,
      ); // should clamp to 2 (growth-rings §6)
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('growth_interval'), 2);
      await svc.memorySettings.setGrowthInterval(50); // and down to 20
      expect(prefs.getInt('growth_interval'), 20);
    });
  });

  // ─── Realism Engine Settings ──────────────────────────────────────

  group('Realism engine settings persistence', () {
    test('setRealismOneShotEval persists to SharedPreferences', () async {
      final svc = await createStorageService();
      await svc.realismSettings.setRealismOneShotEval(true);
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
      await svc.presetSettings.savePrompt('Test Prompt', 'Test content');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('saved_prompts'), isNotNull);
      expect(
        svc.presetSettings.savedPrompts.any((p) => p['name'] == 'Test Prompt'),
        true,
      );
    });

    test('deleteSavedPrompt persists removal', () async {
      final svc = await createStorageService();
      await svc.presetSettings.savePrompt('Temp', 'content');
      await svc.presetSettings.deleteSavedPrompt('Temp');
      expect(
        svc.presetSettings.savedPrompts.any((p) => p['name'] == 'Temp'),
        false,
      );
    });
  });

  // ─── notifyListeners ──────────────────────────────────────────────

  group('notifyListeners is called on setter', () {
    test('setTemperature triggers notifyListeners', () async {
      final svc = await createStorageService();
      int callCount = 0;
      svc.addListener(() => callCount++);
      await svc.generationSettings.setTemperature(0.9);
      expect(callCount, greaterThanOrEqualTo(1));
    });

    test('setLastUsedModelPath triggers notifyListeners', () async {
      final svc = await createStorageService();
      int callCount = 0;
      svc.addListener(() => callCount++);
      await svc.backendSettings.setLastUsedModelPath('/model.gguf');
      expect(callCount, greaterThanOrEqualTo(1));
    });
  });

  // ─── Active .kcpps preset introspection ────────────────────────────
  // kcppsModelPath / kcppsMmprojPath feed the vision-capability resolver
  // (a preset-owned model must be interrogatable even though
  // lastUsedModelPath stays empty in preset mode).

  group('Active .kcpps preset getters', () {
    File writeKcpps(Map<String, Object> json) {
      final dir = Directory.systemTemp.createTempSync('fpai_kcpps_');
      return File('${dir.path}/preset.kcpps')
        ..writeAsStringSync(jsonEncode(json));
    }

    test('kcppsModelPath prefers model_param over model', () async {
      final svc = await createStorageService();
      final kcpps = writeKcpps({
        'model_param': '/models/a.gguf',
        'model': '/models/b.gguf',
        'mmproj': '/models/proj.gguf',
      });
      await svc.backendSettings.setActiveKcppsPath(kcpps.path);
      expect(svc.backendSettings.kcppsModelPath, '/models/a.gguf');
      expect(svc.backendSettings.kcppsMmprojPath, '/models/proj.gguf');
      expect(svc.backendSettings.kcppsHasModel, isTrue);
    });

    test('kcppsModelPath falls back to model key', () async {
      final svc = await createStorageService();
      final kcpps = writeKcpps({'model': '/models/b.gguf'});
      await svc.backendSettings.setActiveKcppsPath(kcpps.path);
      expect(svc.backendSettings.kcppsModelPath, '/models/b.gguf');
      expect(svc.backendSettings.kcppsMmprojPath, isNull);
    });

    test('empty/absent keys and no active preset return null', () async {
      final svc = await createStorageService();
      final kcpps = writeKcpps({'model_param': '  ', 'mmproj': ''});
      await svc.backendSettings.setActiveKcppsPath(kcpps.path);
      expect(svc.backendSettings.kcppsModelPath, isNull);
      expect(svc.backendSettings.kcppsHasModel, isFalse);
      expect(svc.backendSettings.kcppsMmprojPath, isNull);

      await svc.backendSettings.setActiveKcppsPath(null);
      expect(svc.backendSettings.kcppsModelPath, isNull);
      expect(svc.backendSettings.kcppsMmprojPath, isNull);
    });

    test('kcppsModelFileExists reflects the referenced file on disk', () async {
      final svc = await createStorageService();
      final dir = Directory.systemTemp.createTempSync('fpai_kcpps_');
      final model = File('${dir.path}/real.gguf')..writeAsBytesSync([0]);
      final kcpps = File('${dir.path}/preset.kcpps')
        ..writeAsStringSync(jsonEncode({'model_param': model.path}));
      await svc.backendSettings.setActiveKcppsPath(kcpps.path);
      expect(svc.backendSettings.kcppsModelFileExists, isTrue);
      model.deleteSync();
      expect(svc.backendSettings.kcppsModelFileExists, isFalse);
    });
  });
}
