// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Local (KoboldCpp) thinking capability, read from the GGUF chat template
// (2026-08-15).
//
// Why this exists rather than a poke: the remote probe learns a model's menu
// from a provider's "Supported values are: …" 400. KoboldCpp never produces
// one — it forwards enable_thinking / reasoning_effort straight to the chat
// template — so poking it would spend a request to learn nothing AND burn the
// "already probed" flag. The template IS the capability, and it is on disk.
//
// The four template shapes below are the real ones, in the order that
// matters: harmony (gpt-oss) carries reasoning_effort AND channel markers,
// Qwen3 carries enable_thinking AND <think>, so a naive marker-first check
// would call both of them "always thinks" and hide controls that work.
//
// Red-proven (2026-08-15):
//   * checking markers before the switches → the harmony and Qwen3 cases fail
//     (both misread as `always`);
//   * dropping the '<|channel|>analysis' marker → the harmony-without-effort
//     case fails (a thinking model reported as having no thinking mode);
//   * returning a graded set for `toggle` → the "no strength chips" case
//     fails (decorative chips come back).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:front_porch_ai/services/capability/capability.dart';
import 'package:front_porch_ai/services/reasoning_effort.dart';

/// Qwen3-style: a real on/off kwarg, and the think tags it emits when on.
const _qwen3 = '''
{%- if enable_thinking is defined and enable_thinking is false %}
    {{- '<think>\\n\\n</think>\\n\\n' }}
{%- endif %}
''';

/// gpt-oss / harmony: graded effort, and channels instead of `<think>`.
const _harmony = '''
{{- "Reasoning: " + reasoning_effort + "\\n\\n" }}
{{- "<|channel|>analysis<|message|>" }}
''';

/// A harmony-shaped template with NO effort knob — thinking still happens.
const _harmonyNoEffort = '<|start|>assistant<|channel|>analysis<|message|>';

/// R1-style distill: the think tag is forced open, with no switch at all.
const _r1 = "{{- '<｜Assistant｜>' }}{{- '<think>\\n' }}";

/// Plain instruct model: nothing to do with thinking.
const _llama3 = '''
{% for message in messages %}
{{- '<|start_header_id|>' + message['role'] + '<|end_header_id|>' }}
{% endfor %}
''';

/// Heretic / uncensored Gemma-4: the switch exists, then a `{% set %}`
/// overwrites it so request `enable_thinking:false` never reaches render.
const _hereticGemma = '''
{%- set enable_thinking = true %}
{%- if enable_thinking is defined and enable_thinking -%}
{{- '<|think|>' -}}
{%- endif -%}
{%- if not enable_thinking | default(false) -%}
{{- '<|channel>thought\\n<channel|>' -}}
{%- endif -%}
''';

void main() {
  group('detecting what a local template supports', () {
    test('a graded template (gpt-oss) reports graded', () {
      expect(
        detectThinkingFromChatTemplate(_harmony),
        ThinkingSupport.graded,
        reason: 'reasoning_effort is honoured, so the strength chips are real',
      );
    });

    test('a toggle template (Qwen3) reports toggle, not always', () {
      expect(
        detectThinkingFromChatTemplate(_qwen3),
        ThinkingSupport.toggle,
        reason:
            'it carries <think> too — but enable_thinking is the more '
            'specific control and it means Off genuinely works',
      );
    });

    test('think markers with no switch report always', () {
      expect(detectThinkingFromChatTemplate(_r1), ThinkingSupport.always);
      expect(
        detectThinkingFromChatTemplate(_harmonyNoEffort),
        ThinkingSupport.always,
        reason:
            'harmony reasoners never write <think>; missing the channel '
            'marker would report a thinking model as having no thinking mode',
      );
    });

    test('a plain instruct template reports none', () {
      expect(detectThinkingFromChatTemplate(_llama3), ThinkingSupport.none);
      expect(detectThinkingFromChatTemplate(''), ThinkingSupport.none);
    });

    test('heretic set-true is toggle (Off stays) AND hard-on', () {
      expect(
        detectThinkingFromChatTemplate(_hereticGemma),
        ThinkingSupport.toggle,
        reason:
            'the template still mentions enable_thinking — locking Off '
            'would hide a switch we can honour via thinking_budget: 0',
      );
      expect(chatTemplateHardEnablesThinking(_hereticGemma), isTrue);
      expect(chatTemplateHardEnablesThinking(_qwen3), isFalse);
      expect(
        chatTemplateHardEnablesThinking(
          '{%- if enable_thinking | default(true) -%}x{%- endif -%}',
        ),
        isFalse,
        reason:
            'default(true) only fires when the kwarg is missing; we always '
            'send it, so this is not a hard-on overwrite',
      );
      expect(chatTemplateHardEnablesThinking(''), isFalse);
    });
  });

  group('the effort set each verdict implies', () {
    test('only graded offers strength levels', () {
      expect(
        effortsForThinkingSupport(ThinkingSupport.graded),
        containsAll(<String>['low', 'medium', 'high']),
      );
      for (final s in [
        ThinkingSupport.toggle,
        ThinkingSupport.always,
        ThinkingSupport.none,
      ]) {
        expect(effortsForThinkingSupport(s), {
          'none',
        }, reason: '$s has no strength levels, so it must not advertise any');
      }
    });

    test('the shared chip helper turns those into the right rows', () {
      // The point of reusing the shared vocabulary: chips fall out of the
      // existing helper instead of a second local-only rule.
      rememberReasoningEffortsForModel(
        '/models/graded.gguf',
        effortsForThinkingSupport(ThinkingSupport.graded),
        persist: false,
      );
      rememberReasoningEffortsForModel(
        '/models/toggle.gguf',
        effortsForThinkingSupport(ThinkingSupport.toggle),
        persist: false,
      );
      expect(reasoningEffortChipsFor('/models/graded.gguf'), [
        'low',
        'medium',
        'high',
      ]);
      expect(
        reasoningEffortChipsFor('/models/toggle.gguf'),
        isEmpty,
        reason:
            'an on/off-only model must show NO strength chips — '
            'decorative chips are exactly what this feature removes',
      );
    });
  });

  group('reading the template off a file', () {
    test('a missing file resolves to null, and null claims nothing', () async {
      ReasoningSupportResolver.instance.clearForTest();
      final verdict = await ReasoningSupportResolver.instance.resolveLocalGguf(
        '/definitely/not/here/model.gguf',
      );
      expect(verdict, isNull);
      expect(
        reasoningEffortSupportedFor('/definitely/not/here/model.gguf'),
        isNull,
        reason:
            'an unreadable model must fall back to the generic chips, '
            'never to a guessed capability',
      );
    });

    test('an empty path is not resolved at all', () async {
      ReasoningSupportResolver.instance.clearForTest();
      expect(
        await ReasoningSupportResolver.instance.resolveLocalGguf(''),
        isNull,
      );
      expect(ReasoningSupportResolver.instance.isResolved(''), isFalse);
    });

    test(
      'a miss is cached so a torn file is not re-read every rebuild',
      () async {
        ReasoningSupportResolver.instance.clearForTest();
        const path = '/definitely/not/here/again.gguf';
        await ReasoningSupportResolver.instance.resolveLocalGguf(path);
        expect(
          ReasoningSupportResolver.instance.isResolved(path),
          isTrue,
          reason:
              'peek() is called from build — an uncached miss would hit the '
              'filesystem on every frame',
        );
      },
    );

    test('peek never resolves on its own (it is the build-safe read)', () {
      ReasoningSupportResolver.instance.clearForTest();
      expect(
        ReasoningSupportResolver.instance.peek('/some/model.gguf'),
        isNull,
      );
      expect(
        ReasoningSupportResolver.instance.isResolved('/some/model.gguf'),
        isFalse,
        reason: 'peek must not populate the cache — it must stay a pure read',
      );
    });
  });

  group('oMLX status + on-disk template', () {
    // Live-settled 2026-08-14 against oMLX at :8000: /props 404s, a
    // completions poke would load the model, thinking_default is a
    // classification (gpt-oss is null but graded), and chat_template.jinja
    // sits next to the weights. This table is that settlement.

    setUp(() {
      ReasoningSupportResolver.instance.clearForTest();
      clearReasoningEffortCatalog();
    });
    tearDown(() {
      ReasoningSupportResolver.instance.clearForTest();
      clearReasoningEffortCatalog();
    });

    test('a graded template wins even when thinking_default is null', () {
      expect(
        detectThinkingFromOmlxEntry(
          chatTemplate: _harmony,
          thinkingDefault: null,
        ),
        ThinkingSupport.graded,
        reason:
            'gpt-oss on this machine reports thinking_default=null — '
            'the template is the only honest graded signal',
      );
    });

    test('a toggle template wins over thinking_default false', () {
      expect(
        detectThinkingFromOmlxEntry(
          chatTemplate: _qwen3,
          thinkingDefault: false,
        ),
        ThinkingSupport.toggle,
      );
    });

    test('a silent template with a classified thinking_default is toggle', () {
      expect(
        detectThinkingFromOmlxEntry(
          chatTemplate: _llama3,
          thinkingDefault: false,
        ),
        ThinkingSupport.toggle,
        reason:
            'oMLX marked it as a thinking model; the engine still has '
            'enable_thinking even when the jinja never names it',
      );
      expect(
        detectThinkingFromOmlxEntry(chatTemplate: null, thinkingDefault: true),
        ThinkingSupport.toggle,
      );
    });

    test('a silent template with no classification is none, not unknown', () {
      expect(
        detectThinkingFromOmlxEntry(
          chatTemplate: _llama3,
          thinkingDefault: null,
        ),
        ThinkingSupport.none,
      );
    });

    test('no template and no classification claims nothing', () {
      expect(
        detectThinkingFromOmlxEntry(chatTemplate: null, thinkingDefault: null),
        isNull,
      );
      expect(
        detectThinkingFromOmlxEntry(chatTemplate: '', thinkingDefault: null),
        isNull,
      );
    });

    test(
      'readChatTemplateFromModelDir prefers jinja over tokenizer_config',
      () async {
        final dir = await Directory.systemTemp.createTemp('fpai_omlx_tmpl_');
        addTearDown(() => dir.delete(recursive: true));
        await File('${dir.path}/chat_template.jinja').writeAsString(_harmony);
        await File(
          '${dir.path}/tokenizer_config.json',
        ).writeAsString(jsonEncode({'chat_template': _llama3}));
        expect(await readChatTemplateFromModelDir(dir.path), _harmony);
      },
    );

    test(
      'resolveOmlx registers graded chips from a status + jinja pair',
      () async {
        final dir = await Directory.systemTemp.createTemp('fpai_omlx_res_');
        addTearDown(() => dir.delete(recursive: true));
        await File('${dir.path}/chat_template.jinja').writeAsString(_harmony);

        var hits = 0;
        ReasoningSupportResolver.instance.httpClientFactory = () =>
            MockClient((request) async {
              hits++;
              expect(request.url.path, '/v1/models/status');
              return http.Response(
                jsonEncode({
                  'models': [
                    {
                      'id': 'GPT-OSS-120B-MLX-3.6bit',
                      'model_path': dir.path,
                      'thinking_default': null,
                    },
                  ],
                }),
                200,
              );
            });

        final verdict = await ReasoningSupportResolver.instance.resolveOmlx(
          apiUrl: 'http://localhost:8000/v1',
          modelName: 'GPT-OSS-120B-MLX-3.6bit',
        );
        expect(verdict, ThinkingSupport.graded);
        expect(reasoningEffortChipsFor('GPT-OSS-120B-MLX-3.6bit'), [
          'low',
          'medium',
          'high',
        ]);
        expect(hits, 1);

        // Cached — a second resolve must not hit the network.
        await ReasoningSupportResolver.instance.resolveOmlx(
          apiUrl: 'http://localhost:8000/v1',
          modelName: 'GPT-OSS-120B-MLX-3.6bit',
        );
        expect(hits, 1);
      },
    );

    test(
      'resolveOmlx registers heretic jinja as hard-on, not mandatory',
      () async {
        final dir = await Directory.systemTemp.createTemp('fpai_omlx_heretic_');
        addTearDown(() => dir.delete(recursive: true));
        await File(
          '${dir.path}/chat_template.jinja',
        ).writeAsString(_hereticGemma);

        ReasoningSupportResolver.instance.httpClientFactory = () =>
            MockClient((request) async {
              return http.Response(
                jsonEncode({
                  'models': [
                    {
                      'id': 'gemma-heretic',
                      'model_path': dir.path,
                      'thinking_default': false,
                    },
                  ],
                }),
                200,
              );
            });

        final verdict = await ReasoningSupportResolver.instance.resolveOmlx(
          apiUrl: 'http://localhost:8000/v1',
          modelName: 'gemma-heretic',
        );
        expect(verdict, ThinkingSupport.toggle);
        expect(reasoningTemplateForcesThinking('gemma-heretic'), isTrue);
        expect(
          reasoningEffortIsMandatory('gemma-heretic'),
          isFalse,
          reason: 'Off stays available — evals clamp via thinking_budget: 0',
        );
        expect(
          thinkingBudgetClampForThinkOff('gemma-heretic', thinkOn: false),
          0,
        );
      },
    );

    test('a failed status fetch is not cached as a verdict', () async {
      var hits = 0;
      ReasoningSupportResolver.instance.httpClientFactory = () =>
          MockClient((request) async {
            hits++;
            return http.Response('nope', 500);
          });
      expect(
        await ReasoningSupportResolver.instance.resolveOmlx(
          apiUrl: 'http://localhost:8000/v1',
          modelName: 'anything',
        ),
        isNull,
      );
      expect(
        ReasoningSupportResolver.instance.isResolved('anything'),
        isFalse,
        reason:
            'caching a downed server would brand the model unknown '
            'for the rest of the session',
      );
      expect(
        reasoningEffortSupportedFor('anything'),
        isNull,
        reason: 'a failed fetch must leave generic chips, never a guess',
      );
      await ReasoningSupportResolver.instance.resolveOmlx(
        apiUrl: 'http://localhost:8000/v1',
        modelName: 'anything',
      );
      expect(hits, 2);
    });
  });

  group('LM Studio listing + on-disk GGUF', () {
    // Live-settled 2026-08-15 against LM Studio 0.4.21 at :1234:
    // a completions poke returns a 400 listing (server enum, NOT per-model)
    // AND JIT-loads the model. /api/v0/models has no path. /props 404s.
    // Read the GGUF instead.

    setUp(() {
      ReasoningSupportResolver.instance.clearForTest();
      clearReasoningEffortCatalog();
    });
    tearDown(() {
      ReasoningSupportResolver.instance.clearForTest();
      clearReasoningEffortCatalog();
      lmStudioModelsRootOverride = null;
    });

    test('the live LM Studio 400 is parseable (underscore form)', () {
      const verbatim =
          "Invalid 'reasoning_effort' value: 'fpai_probe'. "
          'Supported values: none, minimal, low, medium, high, xhigh.';
      expect(
        supportedReasoningEffortsFromError(verbatim),
        {'none', 'minimal', 'low', 'medium', 'high', 'xhigh'},
        reason:
            'the live 0.4.21 string uses reasoning_effort (underscore) '
            'and "Supported values:" without "are" — missing either '
            'would drop the listing on the floor',
      );
    });

    test('findLmStudioGguf matches the id and skips mmproj', () async {
      final dir = await Directory.systemTemp.createTemp('fpai_lms_find_');
      addTearDown(() => dir.delete(recursive: true));
      final pub = Directory('${dir.path}/lmstudio-community')..createSync();
      await File(
        '${pub.path}/Qwen2.5-0.5B-Instruct-Q8_0.gguf',
      ).writeAsBytes([0]);
      await File('${pub.path}/mmproj-BF16.gguf').writeAsBytes([0]);
      await File('${pub.path}/Other-Model-Q8_0.gguf').writeAsBytes([0]);

      final found = await findLmStudioGguf(
        modelsRoot: dir.path,
        modelId: 'qwen2.5-0.5b-instruct',
        publisher: 'lmstudio-community',
        quantization: 'Q8_0',
      );
      expect(found, endsWith('Qwen2.5-0.5B-Instruct-Q8_0.gguf'));
      expect(found, isNot(contains('mmproj')));
    });

    test(
      'resolveLmStudio registers none from a silent GGUF, never pokes',
      () async {
        final dir = await Directory.systemTemp.createTemp('fpai_lms_res_');
        addTearDown(() => dir.delete(recursive: true));
        final pub = Directory('${dir.path}/lmstudio-community')..createSync();
        await File(
          '${pub.path}/Qwen2.5-0.5B-Instruct-Q8_0.gguf',
        ).writeAsBytes(_buildGgufTemplate(_llama3));
        lmStudioModelsRootOverride = dir.path;

        var hits = 0;
        var poked = false;
        ReasoningSupportResolver.instance.httpClientFactory = () =>
            MockClient((request) async {
              hits++;
              if (request.method == 'POST') poked = true;
              expect(request.url.path, '/api/v0/models');
              return http.Response(
                jsonEncode({
                  'data': [
                    {
                      'id': 'qwen2.5-0.5b-instruct',
                      'type': 'llm',
                      'publisher': 'lmstudio-community',
                      'compatibility_type': 'gguf',
                      'quantization': 'Q8_0',
                      'state': 'not-loaded',
                    },
                  ],
                }),
                200,
              );
            });

        final verdict = await ReasoningSupportResolver.instance.resolveLmStudio(
          apiUrl: 'http://localhost:1234/v1',
          modelName: 'qwen2.5-0.5b-instruct',
        );
        expect(verdict, ThinkingSupport.none);
        expect(reasoningEffortChipsFor('qwen2.5-0.5b-instruct'), isEmpty);
        expect(hits, 1);
        expect(poked, isFalse, reason: 'a poke would JIT-load the model');
      },
    );

    test('a failed LMS listing is not cached as a verdict', () async {
      var hits = 0;
      ReasoningSupportResolver.instance.httpClientFactory = () =>
          MockClient((request) async {
            hits++;
            return http.Response('nope', 404);
          });
      expect(
        await ReasoningSupportResolver.instance.resolveLmStudio(
          apiUrl: 'http://localhost:1234/v1',
          modelName: 'qwen2.5-0.5b-instruct',
        ),
        isNull,
      );
      expect(
        ReasoningSupportResolver.instance.isResolved('qwen2.5-0.5b-instruct'),
        isFalse,
      );
      await ReasoningSupportResolver.instance.resolveLmStudio(
        apiUrl: 'http://localhost:1234/v1',
        modelName: 'qwen2.5-0.5b-instruct',
      );
      expect(hits, 2);
    });
  });
}

Uint8List _buildGgufTemplate(String template) {
  final builder = BytesBuilder();
  builder.add(utf8.encode('GGUF'));
  builder.add(_u32(3));
  builder.add(_u64(0)); // tensors
  builder.add(_u64(1)); // kv count
  final key = utf8.encode('tokenizer.chat_template');
  builder.add(_u64(key.length));
  builder.add(key);
  builder.add(_u32(8)); // string
  final val = utf8.encode(template);
  builder.add(_u64(val.length));
  builder.add(val);
  return Uint8List.fromList(builder.takeBytes());
}

Uint8List _u32(int v) => Uint8List(4)..buffer.asUint32List()[0] = v;
Uint8List _u64(int v) => Uint8List(8)..buffer.asUint64List()[0] = v;
