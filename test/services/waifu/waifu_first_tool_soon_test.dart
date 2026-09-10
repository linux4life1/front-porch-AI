// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Old contract (mutation-regex first step only, max_tokens 0, hello
// unconstrained) let every model sit in the think channel instead of
// calling a tool. Assertions below match the new leash.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/tool_choice_style_probe.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';

class _CaptureLlm extends LLMService {
  GenerationParams? last;

  @override
  Stream<String> generateStream(GenerationParams params) async* {}

  @override
  Future<LlmToolResponse?> generateWithTools(
    GenerationParams params,
    List<Map<String, dynamic>> tools,
  ) async {
    last = params;
    return const LlmToolResponse(calls: [], text: '');
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'Capture';
}

void main() {
  test(
    'first generate requires a tool; after one lands, a tool is optional',
    () async {
      final root = await Directory.systemTemp.createTemp('waifu_first_tool_');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final llm = ScriptedWaifuLlm([
        const LlmToolResponse(
          calls: [
            LlmToolCall(
              name: 'write',
              arguments: {
                'path': 'PageTurn.swift',
                'contents': 'import Metal\n',
              },
            ),
          ],
          text: '',
        ),
        const LlmToolResponse(calls: [], text: 'Mesh is on disk.'),
      ]);
      final session = WaifuSession(
        folderRoot: root.path,
        coworker: CharacterCard(name: 'Iris'),
      );
      await WaifuHarness(
        session: session,
        llm: llm,
      ).send('implement a page-turn animation in Swift');
      expect(llm.calls, isNotEmpty);
      expect(llm.calls.first.forceTool, isTrue);
      expect(llm.calls.first.tools, isNotEmpty);
      expect(llm.calls.length, greaterThan(1));
      expect(llm.calls[1].forceTool, isFalse);
    },
  );

  test(
    'tool generate requires a tool and caps thinking; never max_tokens 0',
    () async {
      final cap = _CaptureLlm();
      await LlmServiceWaifuLlm(() => cap).generate(
        systemPrompt: 's',
        prompt: 'p',
        tools: const [
          {
            'type': 'function',
            'function': {'name': 'write'},
          },
        ],
      );
      expect(cap.last, isNotNull);
      expect(cap.last!.toolChoice, kToolChoiceRequired);
      expect(cap.last!.reasoningEnabled, isTrue);
      expect(cap.last!.reasoningEffort, isEmpty);
      expect(cap.last!.reasoningMaxTokens, 512);
      expect(cap.last!.reasoningMaxTokens, kWaifuThinkCapTokens);
      expect(kWaifuThinkCapTokens, lessThan(2000));
      expect(cap.last!.reasoningMaxTokens, greaterThan(0));

      await LlmServiceWaifuLlm(() => cap).generate(
        systemPrompt: 's',
        prompt: 'p',
        tools: const [
          {
            'type': 'function',
            'function': {'name': 'write'},
          },
        ],
        forceTool: false,
      );
      expect(cap.last!.toolChoice, isNull);

      await LlmServiceWaifuLlm(
        () => cap,
      ).generate(systemPrompt: 's', prompt: 'p', tools: const []);
      expect(cap.last!.toolChoice, isNull);
      expect(cap.last!.reasoningEnabled, isTrue);
      expect(cap.last!.reasoningMaxTokens, kWaifuWrapThinkCapTokens);
    },
  );

  test('a plain hello still has to call a tool, not think a novel', () async {
    final root = await Directory.systemTemp.createTemp('waifu_hello_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final llm = ScriptedWaifuLlm([
      const LlmToolResponse(
        calls: [
          LlmToolCall(name: 'glob', arguments: {'pattern': '*'}),
        ],
        text: '',
      ),
      const LlmToolResponse(calls: [], text: 'Hey. What are we building?'),
    ]);
    final session = WaifuSession(
      folderRoot: root.path,
      coworker: CharacterCard(name: 'Iris'),
    );
    await WaifuHarness(session: session, llm: llm).send('hey');
    expect(llm.calls, isNotEmpty);
    expect(llm.calls.first.forceTool, isTrue);
    expect(llm.calls.first.tools, isNotEmpty);
  });
}
