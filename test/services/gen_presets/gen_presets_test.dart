// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/models/chat_generation_settings.dart';
import 'package:front_porch_ai/services/gen_presets/gen_presets.dart';
import 'package:front_porch_ai/services/storage/settings/remote_model_memory.dart';
import 'package:front_porch_ai/services/storage/storage.dart';

class _Rig {
  _Rig(
    this.prefs, {
    Future<RecommendedSamplers> Function(ChatModelId)? lookup,
    DateTime Function()? now,
  }) : generation = GenerationSettings(),
       backend = BackendSettings(),
       presets = GenPresetSettings() {
    for (final s in <SettingsBase>[generation, backend, presets]) {
      s.initializeBase(prefs, () => follower.onSettingsChanged());
    }
    generation.load();
    backend.load();
    presets.load();
    follower = GenPresetFollower(
      generation: generation,
      backend: backend,
      presets: presets,
      lookup: lookup ?? (_) async => RecommendedSamplers.unknown,
      now: now ?? () => clock,
      timer: (_, fire) {
        final t = _ManualTimer(fire);
        timers.add(t);
        return t;
      },
    );
  }

  final timers = <_ManualTimer>[];
  int get pendingSwitches => timers.where((t) => t.isActive).length;

  final SharedPreferences prefs;
  final GenerationSettings generation;
  final BackendSettings backend;
  final GenPresetSettings presets;
  late final GenPresetFollower follower;
  DateTime clock = DateTime.utc(2026, 1, 1);

  SamplerValues get live => SamplerValues.capture(generation, backend);

  /// The model stays put long enough to count, and the switch finishes.
  Future<void> settle() async {
    for (final t in List.of(timers)) {
      t.fire();
    }
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }
}

class _ManualTimer implements Timer {
  _ManualTimer(this._fire);
  void Function()? _fire;

  void fire() {
    final f = _fire;
    _fire = null;
    f?.call();
  }

  @override
  void cancel() => _fire = null;
  @override
  bool get isActive => _fire != null;
  @override
  int get tick => 0;
}

Future<_Rig> _rig({
  Map<String, Object> prefs = const {},
  Future<RecommendedSamplers> Function(ChatModelId)? lookup,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  return _Rig(await SharedPreferences.getInstance(), lookup: lookup);
}

const _known = RecommendedSamplers(
  SamplerValues(temperature: 0.6),
  RecommendedSource.family,
  familyLabel: 'Qwen3 (thinking)',
);

const _cydonia = '/models/Cydonia-24B-Q4_K_M.gguf';
const _qwen = '/models/Qwen3-30B-A3B-Q4_K_M.gguf';

void main() {
  group('recommended samplers', () {
    test('GGUF general.sampling.* maps onto the preset fields', () {
      final v = samplingFromGgufMeta({
        'general.sampling.temp': 0.6,
        'general.sampling.top_k': 20,
        'general.sampling.top_p': 0.95,
        'general.sampling.min_p': 0.0,
        'general.sampling.penalty_repeat': 1.05,
        'general.sampling.penalty_last_n': -1,
        'general.sampling.xtc_probability': 0.5,
        'general.sampling.xtc_threshold': 0.1,
        'general.name': 'Qwen3',
      });
      expect(v.temperature, 0.6);
      expect(v.topK, 20);
      expect(v.topP, 0.95);
      expect(v.minP, 0.0);
      expect(v.repeatPenalty, 1.05);
      expect(v.repeatPenaltyTokens, isNull, reason: '-1 is not a count');
      expect(v.xtcProbability, 0.5);
      expect(v.xtcThreshold, 0.1);
      expect(samplingFromGgufMeta({'general.name': 'x'}).isEmpty, isTrue);
    });

    test('provider default_parameters map, junk is ignored', () {
      final v = CatalogSamplerDefaults.fromDefaultParameters({
        'temperature': 1.0,
        'top_p': 0.95,
        'top_k': 64,
        'repetition_penalty': 1.1,
        'frequency_penalty': 0.3,
      });
      expect(v.toJson(), {
        'temperature': 1.0,
        'topP': 0.95,
        'topK': 64,
        'repeatPenalty': 1.1,
      });
      expect(CatalogSamplerDefaults.fromDefaultParameters(null).isEmpty, true);
      expect(
        CatalogSamplerDefaults.fromDefaultParameters({
          'temperature': 'hot',
        }).isEmpty,
        true,
      );
    });

    test('family table picks the narrowest family and skips Mistral', () {
      expect(
        samplerFamilyFor('Qwen3-30B-A3B-Instruct-2507')!.label,
        'Qwen3 Instruct',
      );
      expect(
        samplerFamilyFor('qwen/qwen3-235b-a22b')!.label,
        'Qwen3 (thinking)',
      );
      expect(samplerFamilyFor('google_gemma-3-27b-it-Q4')!.values.topK, 64);
      expect(
        samplerFamilyFor('moonshotai/kimi-k2-thinking')!.label,
        'Kimi K2 Thinking',
      );
      expect(samplerFamilyFor('Mistral-Small-3.2-24B'), isNull);
      expect(samplerFamilyFor('Cydonia-24B-v4.1'), isNull);
    });

    test('the model file wins, then the family table, then nothing', () async {
      final fromFile = await recommendedSamplersFor(
        ChatModelId.local(_qwen),
        readFile: (_) async => const SamplerValues(temperature: 0.55),
      );
      expect(fromFile.source, RecommendedSource.modelFile);
      expect(fromFile.values.temperature, 0.55);

      final fromFamily = await recommendedSamplersFor(
        ChatModelId.local(_qwen),
        readFile: (_) async => const SamplerValues(),
      );
      expect(fromFamily.source, RecommendedSource.family);
      expect(fromFamily.values.temperature, 0.6);
      expect(fromFamily.sourceWords, 'recommended for Qwen3 (thinking)');
      // A reset fills what the family does not publish from the app.
      expect(fromFamily.resetValues.dryMultiplier, 0.0);
      expect(fromFamily.resetValues.maxLength, 2048);

      final unknown = await recommendedSamplersFor(
        ChatModelId.local(_cydonia),
        readFile: (_) async => const SamplerValues(),
      );
      expect(unknown.isEmpty, isTrue);
    });

    test('a remote model uses its provider list before the family', () async {
      CatalogSamplerDefaults.instance.clearForTest();
      CatalogSamplerDefaults.instance.remember('google/gemma-3-27b-it', {
        'temperature': 0.8,
      });
      final rec = await recommendedSamplersFor(
        ChatModelId.remote(
          'https://openrouter.ai/api/v1',
          'google/gemma-3-27b-it',
        ),
      );
      expect(rec.source, RecommendedSource.provider);
      expect(rec.values.temperature, 0.8);
      CatalogSamplerDefaults.instance.clearForTest();
    });

    test('app defaults equal a fresh GenerationSettings', () async {
      final r = await _rig();
      expect(SamplerValues.appDefaults.matchedBy(r.live), isTrue);
    });
  });

  group('preset store', () {
    test('saves, links and survives a reload; delete drops links', () async {
      final r = await _rig();
      await r.generation.setTemperature(1.05);
      await r.presets.savePreset('Warm', r.live);
      await r.presets.setSlot('Warm');
      await r.presets.link(ChatModelId.local(_cydonia).key, 'Warm');

      final again = GenPresetSettings()..initializeBase(r.prefs, () {});
      again.load();
      expect(again.presets['Warm']!.temperature, 1.05);
      expect(again.slot, 'Warm');
      expect(again.linkedPreset('local:cydonia-24b-q4_k_m.gguf'), 'Warm');

      await again.deletePreset('Warm');
      expect(again.links, isEmpty);
      expect(again.slot, isNull);
    });

    test('a damaged prefs value loads as empty instead of throwing', () async {
      final r = await _rig(
        prefs: {'gen_presets': '{not json', 'gen_preset_links': '[1]'},
      );
      expect(r.presets.presets, isEmpty);
      expect(r.presets.links, isEmpty);
    });

    test('a local link follows the file name, not the folder', () {
      expect(
        ChatModelId.local('/a/Cydonia.gguf').key,
        ChatModelId.local(r'C:\other\Cydonia.gguf'.replaceAll(r'\', '/')).key,
      );
      expect(ChatModelId.local('/a/Cydonia.gguf').label, 'Cydonia');
    });
  });

  group('model switch', () {
    test('starting the app applies nothing', () async {
      final r = await _rig(
        prefs: {'last_used_model_path': _qwen},
        lookup: (_) async => const RecommendedSamplers(
          SamplerValues(temperature: 0.6),
          RecommendedSource.modelFile,
        ),
      );
      await r.follower.start();
      expect(r.generation.temperature, 0.7);
      expect(r.follower.notice.value, isNull);
      expect(r.follower.recommended.value.values.temperature, 0.6);
    });

    test('a linked preset loads, and Undo puts the old values back', () async {
      final r = await _rig(prefs: {'last_used_model_path': _cydonia});
      await r.follower.start();
      await r.presets.savePreset(
        'Qwen precise',
        r.live.over(SamplerValues.appDefaults).copyTemp(0.6),
      );
      await r.presets.link(ChatModelId.local(_qwen).key, 'Qwen precise');
      await r.generation.setTemperature(1.2);

      await r.backend.setLastUsedModelPath(_qwen);
      await r.settle();
      expect(r.generation.temperature, 0.6);
      expect(r.presets.slot, 'Qwen precise');
      final notice = r.follower.notice.value!;
      expect(notice.message, contains('“Qwen precise”'));

      expect(await r.follower.undo(notice.id), isTrue);
      expect(r.generation.temperature, 1.2);
      expect(r.presets.slot, isNull);
      expect(r.follower.notice.value, isNull);
    });

    test('an unlinked model gets its recommended values only', () async {
      final r = await _rig(
        prefs: {'last_used_model_path': _cydonia},
        lookup: (m) async => m.label.startsWith('Qwen3')
            ? const RecommendedSamplers(
                SamplerValues(temperature: 0.6, topK: 20),
                RecommendedSource.family,
                familyLabel: 'Qwen3 (thinking)',
              )
            : RecommendedSamplers.unknown,
      );
      await r.follower.start();
      await r.generation.setDryMultiplier(0.8);

      await r.backend.setLastUsedModelPath(_qwen);
      await r.settle();
      expect(r.generation.temperature, 0.6);
      expect(r.generation.topK, 20);
      expect(r.generation.dryMultiplier, 0.8, reason: 'not published, kept');
      expect(
        r.follower.notice.value!.message,
        contains('recommended for Qwen3 (thinking)'),
      );
    });

    test('a model nothing knows keeps the values, with no toast', () async {
      final r = await _rig(prefs: {'last_used_model_path': _qwen});
      await r.follower.start();
      await r.generation.setTemperature(1.3);
      await r.backend.setLastUsedModelPath(_cydonia);
      await r.settle();
      expect(r.generation.temperature, 1.3);
      expect(r.follower.notice.value, isNull);
    });

    test('quick back-to-back switches undo to before the first', () async {
      final r = await _rig(
        prefs: {'last_used_model_path': _cydonia},
        lookup: (m) async => m.label == 'Cydonia-24B-Q4_K_M'
            ? RecommendedSamplers.unknown
            : _known,
      );
      await r.follower.start();
      await r.generation.setTemperature(1.3);
      await r.presets.savePreset(
        'Hot',
        SamplerValues.appDefaults.copyTemp(1.9),
      );
      await r.presets.link(ChatModelId.local('/m/B.gguf').key, 'Hot');

      await r.backend.setLastUsedModelPath(_qwen);
      await r.settle();
      r.clock = r.clock.add(const Duration(seconds: 2));
      await r.backend.setLastUsedModelPath('/m/B.gguf');
      await r.settle();
      expect(r.generation.temperature, 1.9);
      await r.follower.undo(r.follower.notice.value!.id);
      expect(r.generation.temperature, 1.3);

      // A later switch is its own move.
      await r.backend.setLastUsedModelPath(_qwen);
      await r.settle();
      r.clock = r.clock.add(const Duration(minutes: 1));
      await r.backend.setLastUsedModelPath('/m/B.gguf');
      await r.settle();
      await r.follower.undo(r.follower.notice.value!.id);
      expect(r.generation.temperature, 0.6);
    });

    test('a remote model switch counts too', () async {
      final r = await _rig(
        prefs: {
          'backend_type': 'openRouter',
          'remote_api_url': 'https://openrouter.ai/api/v1',
          'remote_model_name': 'z-ai/glm-4.6',
        },
      );
      await r.follower.start();
      await r.presets.savePreset(
        'Kimi',
        SamplerValues.appDefaults.copyTemp(0.65),
      );
      final kimi = ChatModelId.remote(
        remoteModelSlot(
          backend: 'openRouter',
          url: 'https://openrouter.ai/api/v1',
        ),
        'moonshotai/kimi-k2',
      );
      await r.presets.link(kimi.key, 'Kimi');
      await r.backend.setRemoteModelName('moonshotai/kimi-k2');
      await r.settle();
      expect(r.generation.temperature, 0.65);
    });
  });

  group('switch safety', () {
    test('typing a model name only switches on the name it stops on', () async {
      final looked = <String>[];
      final r = await _rig(
        prefs: {
          'backend_type': 'openRouter',
          'remote_api_url': 'https://openrouter.ai/api/v1',
          'remote_model_name': 'z-ai/glm-4.6',
        },
        lookup: (m) async {
          looked.add(m.key);
          return RecommendedSamplers.unknown;
        },
      );
      await r.follower.start();
      await r.presets.savePreset(
        'Four-oh',
        SamplerValues.appDefaults.copyTemp(0.3),
      );
      final slot = remoteModelSlot(
        backend: 'openRouter',
        url: 'https://openrouter.ai/api/v1',
      );
      await r.presets.link(
        ChatModelId.remote(slot, 'openai/gpt-4o').key,
        'Four-oh',
      );
      looked.clear();

      const typed = 'openai/gpt-4o-mini';
      for (var i = 1; i <= typed.length; i++) {
        await r.backend.setRemoteModelName(typed.substring(0, i));
        await Future<void>.delayed(Duration.zero);
      }
      expect(r.generation.temperature, 0.7, reason: 'gpt-4o was a prefix');
      expect(r.pendingSwitches, 1);
      await r.settle();
      expect(r.generation.temperature, 0.7);
      expect(r.presets.slot, isNull);
      expect(r.follower.notice.value, isNull);
      expect(looked, [ChatModelId.remote(slot, typed).key]);
      expect(r.follower.model.key, ChatModelId.remote(slot, typed).key);
    });

    test('the first switch keeps tuning nobody saved, once', () async {
      final r = await _rig(
        prefs: {'last_used_model_path': _cydonia},
        lookup: (m) async =>
            m.label.startsWith('Qwen3') ? _known : RecommendedSamplers.unknown,
      );
      await r.follower.start();
      await r.generation.setTemperature(1.25);
      await r.generation.setMinP(0.05);

      await r.backend.setLastUsedModelPath(_qwen);
      await r.settle();
      expect(r.generation.temperature, 0.6);
      final kept = r.presets.presets[GenPresetFollower.keptPresetName]!;
      expect(kept.temperature, 1.25);
      expect(kept.minP, 0.05);
      expect(r.follower.notice.value!.message, contains('“My settings”'));

      // Deleting it is the user's call; it does not come back.
      await r.presets.deletePreset(GenPresetFollower.keptPresetName);
      await r.backend.setLastUsedModelPath(_cydonia);
      await r.settle();
      await r.generation.setTemperature(1.4);
      await r.backend.setLastUsedModelPath(_qwen);
      await r.settle();
      expect(r.presets.presets, isEmpty);
    });

    test('values left at the app defaults are not saved as a preset', () async {
      final r = await _rig(
        prefs: {'last_used_model_path': _cydonia},
        lookup: (m) async =>
            m.label.startsWith('Qwen3') ? _known : RecommendedSamplers.unknown,
      );
      await r.follower.start();
      await r.backend.setLastUsedModelPath(_qwen);
      await r.settle();
      expect(r.generation.temperature, 0.6);
      expect(r.presets.presets, isEmpty);
      expect(r.follower.notice.value!.message, isNot(contains('My settings')));
    });

    test('Llama 3 and Gemma 3 do not claim 30B-style names', () {
      expect(samplerFamilyFor('Llama-3.1-8B-Instruct')?.label, 'Llama 3');
      expect(samplerFamilyFor('llama-30b-supercot'), isNull);
      expect(samplerFamilyFor('gemma-3-27b-it')?.label, 'Gemma 3');
    });
  });

  test('loading a preset into a chat keeps its prompt choice', () {
    final chat = ChatGenerationSettings(
      systemPromptSource: 'user',
      temperature: 1.4,
      bannedPhrases: const ['x'],
    );
    final loaded = GenPresetActions.loadIntoChat(
      chat,
      const SamplerValues(temperature: 0.6, topK: 20),
      'Qwen precise',
    );
    expect(loaded.temperature, 0.6);
    expect(loaded.topK, 20);
    expect(loaded.systemPromptSource, 'user');
    expect(loaded.bannedPhrases, ['x']);
    expect(loaded.genPresetName, 'Qwen precise');

    final cleared = GenPresetActions.loadIntoChat(loaded, null, null);
    expect(cleared.temperature, isNull);
    expect(cleared.genPresetName, isNull);
    expect(cleared.systemPromptSource, 'user');
  });
}

extension on SamplerValues {
  SamplerValues copyTemp(double t) => SamplerValues(temperature: t).over(this);
}
